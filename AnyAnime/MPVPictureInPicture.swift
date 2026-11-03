import AVKit
import CoreVideo
import Libmpv

/// PiP needs sample buffers; a CAMetalLayer cannot be used as its content source.
/// The same mpv decoder/audio session renders small CPU frames only while PiP is in use.
/// Render API calls run on their own queue, without locks/waits on the client API thread.
final class MPVSoftwareVideoOutput {
    private let queue = DispatchQueue(label: "AnPinime.PiP.frames", qos: .userInitiated)
    private var context: OpaquePointer?
    private var timer: DispatchSourceTimer?
    private var dimensions: (Int32, Int32) = (640, 360)
    var frame: ((CVPixelBuffer) -> Void)?

    func prepare(handle: OpaquePointer, size: CGSize, completion: @escaping (Bool) -> Void) {
        let factor = min(1, 640 / max(1, max(size.width, size.height)))
        let width = Int32(max(4, Int(size.width * factor) / 4 * 4))
        let height = Int32(max(4, Int(size.height * factor) / 4 * 4))
        queue.async { [self] in
            dimensions = (width, height)
            let api = strdup("sw")!
            defer { free(api) }
            var parameters = [mpv_render_param(type: MPV_RENDER_PARAM_API_TYPE, data: UnsafeMutableRawPointer(api)),
                              mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil)]
            let result = mpv_render_context_create(&context, handle, &parameters)
            DispatchQueue.main.async { completion(result >= 0) }
        }
    }

    func start() {
        queue.async { [self] in
            guard context != nil, timer == nil else { return }
            let clock = DispatchSource.makeTimerSource(queue: queue)
            clock.schedule(deadline: .now(), repeating: 1.0 / 30.0, leeway: .milliseconds(3))
            clock.setEventHandler { [weak self] in self?.render() }
            timer = clock; clock.resume()
        }
    }

    private func render() {
        guard let context, mpv_render_context_update(context) & 1 != 0 else { return }
        var pixelBuffer: CVPixelBuffer?
        let attributes = [kCVPixelBufferIOSurfacePropertiesKey: [:], kCVPixelBufferBytesPerRowAlignmentKey: 64] as CFDictionary
        guard CVPixelBufferCreate(kCFAllocatorDefault, Int(dimensions.0), Int(dimensions.1), kCVPixelFormatType_32BGRA,
                                  attributes, &pixelBuffer) == kCVReturnSuccess, let pixelBuffer else { return }
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        guard let pixels = CVPixelBufferGetBaseAddress(pixelBuffer) else { return }
        var size = [dimensions.0, dimensions.1]
        var stride = CVPixelBufferGetBytesPerRow(pixelBuffer)
        var block: Int32 = 0
        let format = strdup("bgr0")!
        defer { free(format) }
        let result: Int32 = size.withUnsafeMutableBufferPointer { sizePointer in
            withUnsafeMutablePointer(to: &stride) { stridePointer in
                withUnsafeMutablePointer(to: &block) { blockPointer in
                    var parameters = [
                        mpv_render_param(type: MPV_RENDER_PARAM_SW_SIZE, data: sizePointer.baseAddress.map(UnsafeMutableRawPointer.init)),
                        mpv_render_param(type: MPV_RENDER_PARAM_SW_FORMAT, data: UnsafeMutableRawPointer(format)),
                        mpv_render_param(type: MPV_RENDER_PARAM_SW_STRIDE, data: UnsafeMutableRawPointer(stridePointer)),
                        mpv_render_param(type: MPV_RENDER_PARAM_SW_POINTER, data: pixels),
                        mpv_render_param(type: MPV_RENDER_PARAM_BLOCK_FOR_TARGET_TIME, data: UnsafeMutableRawPointer(blockPointer)),
                        mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil)
                    ]
                    return mpv_render_context_render(context, &parameters)
                }
            }
        }
        guard result >= 0 else { return }
        // bgr0 has no alpha; sample buffers use opaque BGRA.
        let bytes = pixels.assumingMemoryBound(to: UInt8.self)
        for row in 0..<Int(dimensions.1) {
            for column in 0..<Int(dimensions.0) { bytes[row * stride + column * 4 + 3] = 255 }
        }
        DispatchQueue.main.async { [weak self] in self?.frame?(pixelBuffer) }
    }

    /// Free before destroying mpv. Completion never blocks the main/client thread.
    func stop(completion: @escaping () -> Void) {
        queue.async { [self] in
            timer?.cancel(); timer = nil
            if let context { mpv_render_context_free(context) }; context = nil
            DispatchQueue.main.async { completion() }
        }
    }
}

@MainActor
final class MPVPictureInPicture: NSObject, AVPictureInPictureControllerDelegate, AVPictureInPictureSampleBufferPlaybackDelegate {
    let layer = AVSampleBufferDisplayLayer()
    private let output = MPVSoftwareVideoOutput()
    private let playback: PlaybackState
    private var controller: AVPictureInPictureController?
    private var timebase: CMTimebase?
    private var possibility: NSKeyValueObservation?
    private var wantsStart = false
    private var starting = false
    private var stopped = false
    private var cleanupComplete = false
    private var stopCompletions: [() -> Void] = []
    private var prepared = false
    private let command: (String, Double) -> Void
    private let restoreVideo: () -> Void
    private let finished: () -> Void
    #if DEBUG
    private(set) var frameCount = 0
    private(set) var visibleFrameCount = 0
    #endif

    init(playback: PlaybackState, command: @escaping (String, Double) -> Void,
         restoreVideo: @escaping () -> Void, finished: @escaping () -> Void) {
        self.playback = playback; self.command = command; self.restoreVideo = restoreVideo; self.finished = finished
        super.init()
        var clock: CMTimebase?
        if CMTimebaseCreateWithSourceClock(allocator: kCFAllocatorDefault, sourceClock: CMClockGetHostTimeClock(), timebaseOut: &clock) == noErr {
            timebase = clock; layer.controlTimebase = clock
        }
        layer.videoGravity = .resizeAspect; layer.backgroundColor = UIColor.black.cgColor; layer.isOpaque = true
        output.frame = { [weak self] pixelBuffer in self?.enqueue(pixelBuffer) }
    }

    func prepare(handle: OpaquePointer, size: CGSize, start: Bool) {
        guard !stopped else { return }
        wantsStart = start
        playback.pictureInPicturePending = start
        let content = AVPictureInPictureController.ContentSource(sampleBufferDisplayLayer: layer, playbackDelegate: self)
        controller = AVPictureInPictureController(contentSource: content)
        controller?.delegate = self
        controller?.canStartPictureInPictureAutomaticallyFromInline = true
        possibility = controller?.observe(\.isPictureInPicturePossible, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.startIfPossible() }
        }
        output.prepare(handle: handle, size: size) { [weak self] success in
            guard let self, !self.stopped else { return }
            guard success else { self.fail("Thiết bị chưa khởi tạo được hình ảnh cho PiP."); return }
            self.prepared = true
            // Copy-back hardware decoding gives the software renderer readable video frames.
            self.command("pipOutput", 1)
            self.invalidatePlaybackState()
            self.output.start()
        }
        if start {
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard let self, !self.stopped, !self.playback.pictureInPictureActive else { return }
                self.fail("iOS chưa mở được cửa sổ PiP. Hãy thử nút cửa sổ nổi khi đang xem.")
            }
        }
    }

    private func enqueue(_ buffer: CVPixelBuffer) {
        guard prepared, !stopped else { return }
        if layer.status == .failed { layer.flush() }
        guard layer.isReadyForMoreMediaData else { return }
        var description: CMVideoFormatDescription?
        guard CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: buffer,
                                                          formatDescriptionOut: &description) == noErr, let description else { return }
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 30),
                                        presentationTimeStamp: timebase.map(CMTimebaseGetTime) ?? CMTime(seconds: playback.currentTime, preferredTimescale: 600), decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        guard CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: buffer,
            formatDescription: description, sampleTiming: &timing, sampleBufferOut: &sample) == noErr, let sample else { return }
        layer.enqueue(sample)
        #if DEBUG
        frameCount += 1
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        if let bytes = CVPixelBufferGetBaseAddress(buffer)?.assumingMemoryBound(to: UInt8.self) {
            let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer), stride = CVPixelBufferGetBytesPerRow(buffer)
            var values: [UInt8] = []
            for y in [height / 4, height / 2, 3 * height / 4] {
                for x in [width / 4, width / 2, 3 * width / 4] {
                    for channel in 0..<3 { values.append(bytes[y * stride + x * 4 + channel]) }
                }
            }
            if Int(values.max() ?? 0) - Int(values.min() ?? 0) > 30 { visibleFrameCount += 1 }
        }
        CVPixelBufferUnlockBaseAddress(buffer, .readOnly)
        #endif
        startIfPossible()
    }

    private func startIfPossible() {
        guard wantsStart, !starting, !stopped, controller?.isPictureInPicturePossible == true else { return }
        starting = true; controller?.startPictureInPicture()
    }

    func invalidatePlaybackState() {
        if let timebase {
            CMTimebaseSetTime(timebase, time: CMTime(seconds: playback.currentTime, preferredTimescale: 600))
            CMTimebaseSetRate(timebase, rate: playback.userPaused ? 0 : playback.rate)
        }
        controller?.invalidatePlaybackState()
    }

    func stop(restore: Bool, completion: @escaping () -> Void = {}) {
        if cleanupComplete { completion(); return }
        stopCompletions.append(completion)
        guard !stopped else { return }
        stopped = true; wantsStart = false
        possibility = nil
        controller?.delegate = nil; controller?.stopPictureInPicture(); controller = nil
        playback.pictureInPicturePending = false
        // Do not synchronously publish during representable destruction.
        Task { @MainActor [weak playback] in playback?.pictureInPictureActive = false }
        output.frame = nil
        output.stop { [self] in
            layer.flushAndRemoveImage(); layer.removeFromSuperlayer()
            if restore { restoreVideo() }
            cleanupComplete = true
            let callbacks = stopCompletions; stopCompletions = []
            callbacks.forEach { $0() }
        }
    }

    private func fail(_ message: String) {
        playback.pictureInPictureError = message
        stop(restore: true) { [weak self] in self?.finished() }
    }
    func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        playback.pictureInPicturePending = true
    }
    func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        playback.pictureInPictureActive = true; playback.pictureInPicturePending = false; playback.pictureInPictureError = nil
    }
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        fail("Chưa mở được PiP: " + error.localizedDescription)
    }
    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        stop(restore: true) { [weak self] in self?.finished() }
    }
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
                                    restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        completionHandler(true)
    }
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, setPlaying playing: Bool) {
        command(playing ? "play" : "pause", 0); pictureInPictureController.invalidatePlaybackState()
    }
    func pictureInPictureControllerTimeRangeForPlayback(_ pictureInPictureController: AVPictureInPictureController) -> CMTimeRange {
        CMTimeRange(start: .zero, duration: CMTime(seconds: max(1, playback.duration), preferredTimescale: 600))
    }
    func pictureInPictureControllerIsPlaybackPaused(_ pictureInPictureController: AVPictureInPictureController) -> Bool { playback.userPaused }
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, didTransitionToRenderSize newRenderSize: CMVideoDimensions) { }
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, skipByInterval skipInterval: CMTime,
                                    completion: @escaping () -> Void) {
        command("seek", min(playback.duration, max(0, playback.currentTime + skipInterval.seconds))); completion()
    }
}
