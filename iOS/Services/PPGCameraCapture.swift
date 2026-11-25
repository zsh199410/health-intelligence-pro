import AVFoundation
import Combine
import HealthCore

/// Session, capture state and sample callbacks are confined to one serial queue.
/// Presentation snapshots are published on the main thread.
final class PPGCameraCapture: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    @Published private(set) var message = "等待开始采集"
    @Published private(set) var busy = false

    @Published private(set) var waveform: [PPGCameraFrame] = []
    @Published private(set) var estimate: PPGPulseEstimator.Estimate?

    private var lastPreviewTime: Double?
    private var contactFrames = 0
    private let queue = DispatchQueue(label: "health.ppg.capture")
    private var captureID: UUID?
    private var session: AVCaptureSession?
    private var camera: AVCaptureDevice?
    private var output: AVCaptureVideoDataOutput?
    private var frames = [PPGCameraFrame]()

    func start() {
        queue.async {
            guard self.captureID == nil else { return }
            let id = UUID()
            self.captureID = id
            self.contactFrames = 0
            self.lastPreviewTime = nil
            DispatchQueue.main.async {
                self.waveform = []
                self.estimate = nil
            }
            self.publish("等待相机权限", busy: true)
            AVCaptureDevice.requestAccess(for: .video) { allowed in
                self.queue.async {
                    guard self.captureID == id else { return }
                    guard allowed else {
                        self.finish("相机权限未开启，请在系统设置中允许访问后重试。")
                        return
                    }
                    self.configure(id: id)
                }
            }
        }
    }

    func stop() {
        queue.async {
            if self.captureID != nil { self.finish("采集已停止") }
        }
    }

    private func configure(id: UUID) {
        guard ProcessInfo.processInfo.thermalState.rawValue < ProcessInfo.ThermalState.serious.rawValue else {
            finish("设备温度较高，请稍后重试。")
            return
        }
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              camera.hasTorch, camera.isTorchAvailable,
              let input = try? AVCaptureDeviceInput(device: camera) else {
            finish("当前设备无法使用后置相机或补光灯。")
            return
        }

        let session = AVCaptureSession()
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        if session.canSetSessionPreset(.vga640x480) { session.sessionPreset = .vga640x480 }
        guard session.canAddInput(input) else { finish("无法连接相机输入。"); return }
        session.addInput(input)
        guard session.canAddOutput(output) else { finish("无法读取相机画面。"); return }
        session.addOutput(output)
        output.setSampleBufferDelegate(self, queue: queue)
        self.session = session
        self.camera = camera
        self.output = output
        session.startRunning()
        guard session.isRunning else { finish("相机启动失败，请稍后重试。"); return }

        do {
            try camera.lockForConfiguration()
            defer { camera.unlockForConfiguration() }
            try camera.setTorchModeOn(level: 0.1)
        } catch {
            finish("补光灯暂时不可用，请稍后重试。")
            return
        }

        publish("采集中，请保持手指静止。", busy: true)
        queue.asyncAfter(deadline: .now() + 12) { [weak self] in
            guard let self, self.captureID == id else { return }
            let quality = PPGCaptureQuality.assess(self.frames)
            guard quality == .readyForAnalysis else { self.finish(self.description(for: quality)); return }
            guard Double(self.contactFrames) >= 0.90 * Double(self.frames.count) else {
                self.finish("指尖覆盖信号不稳定，请调整位置后重测。")
                return
            }
            guard let estimate = PPGPulseEstimator.estimate(self.frames) else {
                self.finish("未提取到足够稳定的脉搏间期，请保持静止后重测。")
                return
            }
            DispatchQueue.main.async { self.estimate = estimate }
            self.finish("已完成本次光学采集。")
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard output === self.output else { return }
        guard ProcessInfo.processInfo.thermalState.rawValue < ProcessInfo.ThermalState.serious.rawValue else {
            finish("设备温度升高，采集已停止。")
            return
        }
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer),
              CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_32BGRA,
              CVPixelBufferLockBaseAddress(buffer, .readOnly) == kCVReturnSuccess else { return }
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        var sum = 0
        var green = 0
        var blue = 0
        var clipped = 0
        var count = 0
        let pixels = base.assumingMemoryBound(to: UInt8.self)
        for y in stride(from: height / 4, to: height * 3 / 4, by: 8) {
            for x in stride(from: width / 4, to: width * 3 / 4, by: 8) {
                let offset = y * rowBytes + x * 4
                let red = Int(pixels[offset + 2])
                green += Int(pixels[offset + 1])
                blue += Int(pixels[offset])
                sum += red
                if red == 0 || red == 255 { clipped += 1 }
                count += 1
            }
        }
        guard count > 0 else { return }
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        guard timestamp.isFinite else { finish("相机帧时间异常，请重测。"); return }
        // A red-dominant, illuminated ROI is a contact heuristic, not a
        // validated classifier. Aggregate only channel statistics on-device.
        if sum > count * 40 && Double(sum) > 1.25 * Double(max(green, blue)) {
            contactFrames += 1
        }
        frames.append(PPGCameraFrame(timestamp: timestamp,
                                     redLevel: Double(sum) / Double(255 * count),
                                     clippedFraction: Double(clipped) / Double(count)))
        if lastPreviewTime == nil || timestamp - (lastPreviewTime ?? timestamp) >= 0.2 {
            lastPreviewTime = timestamp
            let visible = Array(frames.filter { timestamp - $0.timestamp <= 4 })
            DispatchQueue.main.async { self.waveform = visible }
        }
    }

    private func finish(_ message: String) {
        captureID = nil
        if let camera, camera.isTorchActive, (try? camera.lockForConfiguration()) != nil {
            camera.torchMode = .off
            camera.unlockForConfiguration()
        }
        output?.setSampleBufferDelegate(nil, queue: nil)
        session?.stopRunning()
        session = nil
        output = nil
        camera = nil
        frames.removeAll()
        publish(message, busy: false)
    }

    private func publish(_ message: String, busy: Bool) {
        DispatchQueue.main.async {
            self.message = message
            self.busy = busy
        }
    }

    private func description(for result: PPGCaptureQuality.Result) -> String {
        switch result {
        case .readyForAnalysis: return "帧时序、曝光及信号变化通过初筛。"
        case .invalidFrame: return "画面数据异常，请重新采集。"
        case .insufficientDuration: return "有效采集时间不足，请重试。"
        case .irregularTiming: return "采样不连续，请保持设备静止后重试。"
        case .excessiveClipping: return "画面过亮或过暗，请轻轻调整指尖位置。"
        case .flatSignal: return "未观察到足够的信号变化，请调整指尖位置。"
        }
    }
}
