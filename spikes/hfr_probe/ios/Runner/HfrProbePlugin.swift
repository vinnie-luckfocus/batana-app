import AVFoundation
import Flutter

/// HFR 采集探针的 iOS 平台实现。
///
/// - listFormats：枚举后置相机 maxFrameRate > 60 的 AVCaptureDevice.Format；
/// - startCapture：锁定格式与帧时长，AVCaptureVideoDataOutput 逐帧回传
///   呈现时间戳（纳秒，主机单调时钟）；可选 AVCaptureMovieFileOutput 落盘；
/// - stopCapture：停止会话并返回摘要。
final class HfrProbePlugin: NSObject {
  private var eventSink: FlutterEventSink?
  private var session: AVCaptureSession?
  private var movieOutput: AVCaptureMovieFileOutput?
  private var videoURL: URL?
  private var cachedFormats: [AVCaptureDevice.Format] = []
  private var frameCount: Int = 0
  private var frameDelegate: Any?

  static func register(with registrar: FlutterPluginRegistrar) {
    let instance = HfrProbePlugin()
    let methods = FlutterMethodChannel(
      name: "batana.hfr/methods", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(instance, channel: methods)
    let events = FlutterEventChannel(
      name: "batana.hfr/frames", binaryMessenger: registrar.messenger())
    events.setStreamHandler(instance)
  }
}

extension HfrProbePlugin: FlutterPlugin {

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "listFormats":
      listFormats(result: result)
    case "startCapture":
      guard let args = call.arguments as? [String: Any],
        let formatId = args["formatId"] as? String
      else {
        result(FlutterError(code: "BAD_ARGS", message: "缺少 formatId", details: nil))
        return
      }
      let targetFps = (args["targetFps"] as? Double) ?? 240.0
      let record = (args["record"] as? Bool) ?? false
      startCapture(formatId: formatId, targetFps: targetFps, record: record, result: result)
    case "stopCapture":
      stopCapture(result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func listFormats(result: @escaping FlutterResult) {
    AVCaptureDevice.requestAccess(for: .video) { granted in
      guard granted else {
        result(FlutterError(code: "PERMISSION", message: "相机权限被拒绝", details: nil))
        return
      }
      var items: [[String: Any]] = []
      var formats: [AVCaptureDevice.Format] = []
      let positions: [AVCaptureDevice.Position] = [.back, .front]
      for position in positions {
        guard
          let device = AVCaptureDevice.default(
            .builtInWideAngleCamera, for: .video, position: position)
        else { continue }
        for format in device.formats {
          let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
          for range in format.videoSupportedFrameRateRanges where range.maxFrameRate > 60 {
            formats.append(format)
            items.append([
              "id": "\(formats.count - 1)",
              "width": Int(dims.width),
              "height": Int(dims.height),
              "minFps": range.minFrameRate,
              "maxFps": range.maxFrameRate,
              "platform": "ios",
            ])
            break
          }
        }
      }
      self.cachedFormats = formats
      result(items)
    }
  }

  private func startCapture(
    formatId: String, targetFps: Double, record: Bool, result: @escaping FlutterResult
  ) {
    guard let index = Int(formatId), cachedFormats.indices.contains(index) else {
      result(FlutterError(code: "BAD_FORMAT", message: "未知格式 id: \(formatId)", details: nil))
      return
    }
    let format = cachedFormats[index]
    guard
      let device = AVCaptureDevice.default(
        .builtInWideAngleCamera, for: .video, position: .back)
    else {
      result(FlutterError(code: "NO_DEVICE", message: "无后置相机", details: nil))
      return
    }
    do {
      let session = AVCaptureSession()
      session.beginConfiguration()
      session.sessionPreset = .inputPriority

      try device.lockForConfiguration()
      device.activeFormat = format
      let frameDuration = CMTime(value: 1, timescale: CMTimeScale(targetFps))
      device.activeVideoMinFrameDuration = frameDuration
      device.activeVideoMaxFrameDuration = frameDuration
      device.unlockForConfiguration()

      let input = try AVCaptureDeviceInput(device: device)
      guard session.canAddInput(input) else {
        throw NSError(domain: "hfr", code: 1, userInfo: [
          NSLocalizedDescriptionKey: "无法添加相机输入",
        ])
      }
      session.addInput(input)

      let output = AVCaptureVideoDataOutput()
      output.alwaysDiscardsLateVideoFrames = true
      let delegate = FrameSink { [weak self] tsNs in
        self?.frameCount += 1
        let sink = self?.eventSink
        DispatchQueue.main.async { sink?(tsNs) }
      }
      output.setSampleBufferDelegate(delegate, queue: DispatchQueue(label: "hfr.frames"))
      frameDelegate = delegate
      guard session.canAddOutput(output) else {
        throw NSError(domain: "hfr", code: 2, userInfo: [
          NSLocalizedDescriptionKey: "无法添加数据输出",
        ])
      }
      session.addOutput(output)

      if record {
        let movie = AVCaptureMovieFileOutput()
        if session.canAddOutput(movie) {
          session.addOutput(movie)
          movieOutput = movie
        }
      }

      session.commitConfiguration()
      self.session = session
      frameCount = 0
      session.startRunning()

      if record, let movie = movieOutput {
        let url = FileManager.default.temporaryDirectory
          .appendingPathComponent("hfr_probe_\(Int(Date().timeIntervalSince1970)).mov")
        videoURL = url
        movie.startRecording(to: url, recordingDelegate: self)
      }
      result(nil)
    } catch {
      result(FlutterError(code: "START_FAILED", message: "\(error)", details: nil))
    }
  }

  private func stopCapture(result: @escaping FlutterResult) {
    let frames = frameCount
    let movie = movieOutput
    if movie?.isRecording == true {
      // 录像结束回调里再返回路径，这里先停采集。
      movie?.stopRecording()
    }
    session?.stopRunning()
    session = nil
    movieOutput = nil
    result([
      "frames": frames,
      "videoPath": movie != nil ? (videoURL?.path ?? NSNull()) : NSNull(),
    ])
    videoURL = nil
  }
}

extension HfrProbePlugin: FlutterStreamHandler {
  func onListen(withArguments _: Any?, eventSink events: @escaping FlutterEventSink)
    -> FlutterError?
  {
    eventSink = events
    return nil
  }

  func onCancel(withArguments _: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }
}

extension HfrProbePlugin: AVCaptureFileOutputRecordingDelegate {
  func fileOutput(
    _: AVCaptureFileOutput, didFinishRecordingTo _: URL,
    from _: [AVCaptureConnection], error: Error?
  ) {
    if let error {
      NSLog("hfr_probe 录像结束带错误: \(error)")
    }
  }
}

/// 逐帧回调：取样本的呈现时间戳（主机单调时钟）转成纳秒。
private final class FrameSink: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
  private let onFrame: (Int64) -> Void

  init(onFrame: @escaping (Int64) -> Void) {
    self.onFrame = onFrame
  }

  func captureOutput(
    _: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
    from _: AVCaptureConnection
  ) {
    let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
    guard pts.isValid else { return }
    let ns = CMTimeConvertScale(pts, timescale: 1_000_000_000, method: .roundAwayFromZero)
    onFrame(ns.value)
  }
}
