package com.batana.hfr_probe

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.hardware.camera2.CameraCaptureSession
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraConstrainedHighSpeedCaptureSession
import android.hardware.camera2.CameraDevice
import android.hardware.camera2.CameraManager
import android.hardware.camera2.CaptureRequest
import android.hardware.camera2.TotalCaptureResult
import android.hardware.camera2.params.StreamConfigurationMap
import android.media.MediaRecorder
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.util.Range
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/**
 * HFR 采集探针的 Android 平台实现。
 *
 * - listFormats：枚举支持 CONSTRAINED_HIGH_SPEED_VIDEO 的相机，
 *   展开高速录像尺寸与帧率区间（上限 ≥ 100fps）；
 * - startCapture：以 MediaRecorder Surface 建立受约束高速采集会话，
 *   setRepeatingBurst 逐帧回传 SENSOR_TIMESTAMP（纳秒）；
 *   record=false 时录像文件在结束后删除（高速会话要求必须有录制/预览 Surface）；
 * - stopCapture：停止会话并返回摘要。
 */
class MainActivity : FlutterActivity() {
    private var sink: EventChannel.EventSink? = null
    private var pendingAction: (() -> Unit)? = null

    private var device: CameraDevice? = null
    private var session: CameraConstrainedHighSpeedCaptureSession? = null
    private var recorder: MediaRecorder? = null
    private var videoFile: File? = null
    private var keepVideo = false
    private var frameCount = 0L

    private var thread: HandlerThread? = null
    private var worker: Handler? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "batana.hfr/methods")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "listFormats" -> withPermission(result) {
                        try {
                            result.success(listFormats())
                        } catch (e: Exception) {
                            result.error("LIST_FAILED", e.message, null)
                        }
                    }

                    "startCapture" -> withPermission(result) {
                        try {
                            val formatId = call.argument<String>("formatId")
                                ?: throw IllegalArgumentException("缺少 formatId")
                            keepVideo = call.argument<Boolean>("record") ?: false
                            startCapture(formatId, keepVideo)
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("START_FAILED", e.message, null)
                        }
                    }

                    "stopCapture" -> result.success(stopCapture())
                    else -> result.notImplemented()
                }
            }
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "batana.hfr/frames")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    sink = events
                }

                override fun onCancel(arguments: Any?) {
                    sink = null
                }
            })
    }

    private fun withPermission(result: MethodChannel.Result, action: () -> Unit) {
        if (checkSelfPermission(Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) {
            action()
        } else {
            pendingAction = action
            requestPermissions(arrayOf(Manifest.permission.CAMERA), REQ_CAMERA)
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQ_CAMERA) {
            val action = pendingAction
            pendingAction = null
            if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED && action != null) {
                action()
            }
        }
    }

    private data class HighSpeedFormat(
        val cameraId: String,
        val width: Int,
        val height: Int,
        val range: Range<Int>,
    )

    private fun enumerateFormats(): List<HighSpeedFormat> {
        val cm = getSystemService(Context.CAMERA_SERVICE) as CameraManager
        val out = mutableListOf<HighSpeedFormat>()
        for (id in cm.cameraIdList) {
            val ch = cm.getCameraCharacteristics(id)
            val caps = ch.get(CameraCharacteristics.REQUEST_AVAILABLE_CAPABILITIES) ?: continue
            if (!caps.contains(
                    CameraCharacteristics.REQUEST_AVAILABLE_CAPABILITIES_CONSTRAINED_HIGH_SPEED_VIDEO
                )
            ) {
                continue
            }
            val map = ch.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP) ?: continue
            val sizes = map.highSpeedVideoSizes ?: continue
            for (size in sizes) {
                for (range in map.getHighSpeedVideoFpsRangesFor(size)) {
                    if (range.upper < 100) continue
                    out.add(HighSpeedFormat(id, size.width, size.height, range))
                }
            }
        }
        return out
    }

    private fun listFormats(): List<Map<String, Any>> {
        return enumerateFormats().map { f ->
            mapOf(
                "id" to "${f.cameraId}|${f.width}x${f.height}|${f.range.lower}-${f.range.upper}",
                "width" to f.width,
                "height" to f.height,
                "minFps" to f.range.lower.toDouble(),
                "maxFps" to f.range.upper.toDouble(),
                "platform" to "android",
            )
        }
    }

    private fun startCapture(formatId: String, record: Boolean) {
        val parts = formatId.split("|")
        require(parts.size == 3) { "未知格式 id: $formatId" }
        val cameraId = parts[0]
        val (w, h) = parts[1].split("x").map { it.toInt() }
        val (lo, hi) = parts[2].split("-").map { it.toInt() }
        val fpsRange = Range(lo, hi)

        thread = HandlerThread("hfr").also { it.start() }
        worker = Handler(thread!!.looper)
        val cm = getSystemService(Context.CAMERA_SERVICE) as CameraManager

        // 打开相机
        val openLatch = CountDownLatch(1)
        var openError: Exception? = null
        cm.openCamera(cameraId, object : CameraDevice.StateCallback() {
            override fun onOpened(d: CameraDevice) {
                device = d
                openLatch.countDown()
            }

            override fun onDisconnected(d: CameraDevice) {
                d.close()
                openError = IllegalStateException("相机被断开")
                openLatch.countDown()
            }

            override fun onError(d: CameraDevice, error: Int) {
                d.close()
                openError = IllegalStateException("相机打开失败: $error")
                openLatch.countDown()
            }
        }, worker)
        if (!openLatch.await(5, TimeUnit.SECONDS)) throw IllegalStateException("相机打开超时")
        openError?.let { throw it }

        // MediaRecorder Surface（高速会话的目标；不保留录像时结束后删文件）
        val file = File(cacheDir, "hfr_probe_${System.currentTimeMillis()}.mp4")
        val rec =
            (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) MediaRecorder(this)
            else @Suppress("DEPRECATION") MediaRecorder()).apply {
                setVideoSource(MediaRecorder.VideoSource.SURFACE)
                setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
                setOutputFile(file.absolutePath)
                setVideoEncodingBitRate(60_000_000)
                setVideoFrameRate(hi)
                setVideoSize(w, h)
                setVideoEncoder(MediaRecorder.VideoEncoder.H264)
                prepare()
            }
        recorder = rec
        videoFile = file

        // 受约束高速采集会话
        val dev = device ?: throw IllegalStateException("相机未就绪")
        val sessionLatch = CountDownLatch(1)
        var sessionError: Exception? = null
        dev.createConstrainedHighSpeedCaptureSession(
            listOf(rec.surface),
            object : CameraCaptureSession.StateCallback() {
                override fun onConfigured(s: CameraCaptureSession) {
                    try {
                        val hs = s as CameraConstrainedHighSpeedCaptureSession
                        val req = dev.createCaptureRequest(CameraDevice.TEMPLATE_RECORD).apply {
                            addTarget(rec.surface)
                            set(CaptureRequest.CONTROL_AE_TARGET_FPS_RANGE, fpsRange)
                            set(CaptureRequest.CONTROL_MODE, CaptureRequest.CONTROL_MODE_AUTO)
                        }
                        frameCount = 0
                        hs.setRepeatingBurst(
                            hs.createHighSpeedRequestList(req.build()),
                            object : CameraCaptureSession.CaptureCallback() {
                                override fun onCaptureCompleted(
                                    session: CameraCaptureSession,
                                    request: CaptureRequest,
                                    result: TotalCaptureResult
                                ) {
                                    val ts = result.get(
                                        android.hardware.camera2.CaptureResult.SENSOR_TIMESTAMP
                                    ) ?: return
                                    frameCount++
                                    mainHandler.post { sink?.success(ts) }
                                }
                            },
                            worker,
                        )
                        session = hs
                    } catch (e: Exception) {
                        sessionError = e
                    }
                    sessionLatch.countDown()
                }

                override fun onConfigureFailed(s: CameraCaptureSession) {
                    sessionError = IllegalStateException("高速会话配置失败")
                    sessionLatch.countDown()
                }
            },
            worker,
        )
        if (!sessionLatch.await(5, TimeUnit.SECONDS)) throw IllegalStateException("会话配置超时")
        sessionError?.let { throw it }
        rec.start()
    }

    private fun stopCapture(): Map<String, Any?> {
        try {
            session?.stopRepeating()
        } catch (_: Exception) {
        }
        try {
            session?.close()
        } catch (_: Exception) {
        }
        session = null
        try {
            device?.close()
        } catch (_: Exception) {
        }
        device = null
        try {
            recorder?.stop()
        } catch (_: Exception) {
        }
        recorder?.reset()
        recorder?.release()
        recorder = null
        thread?.quitSafely()
        thread = null
        worker = null
        val path = videoFile?.absolutePath
        if (!keepVideo) {
            videoFile?.delete()
        }
        videoFile = null
        return mapOf(
            "frames" to frameCount,
            "videoPath" to if (keepVideo) path else null,
        )
    }

    override fun onDestroy() {
        if (session != null || device != null) stopCapture()
        super.onDestroy()
    }

    private companion object {
        const val REQ_CAMERA = 41
    }
}
