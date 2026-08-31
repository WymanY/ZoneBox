@preconcurrency import AVFoundation
import CoreMedia
import CoreVideo
@preconcurrency import ScreenCaptureKit
import ZoneBoxCore

@MainActor
final class PinMirrorSession {
    let panel = PinMirrorPanel()

    /// Hold off re-cutting the stream until the window frame has stopped
    /// changing for this long.
    private static let resizeSettleDelay: TimeInterval = 0.12
    /// Upper bound on how long the mirror may show a stretched capture during
    /// a continuous drag before the stream is re-cut anyway. Kept long because
    /// re-cutting mid-drag competes with the resize the user is performing.
    private static let resizeStaleLimit: TimeInterval = 1.5

    private let output: PinMirrorOutput
    private var stream: SCStream?
    private var isStopped = false
    private var lastShownFrameAX: CGRect?
    private var lastStreamPixelSize: CGSize = .zero
    private var desiredPixelSize: CGSize?
    private var desiredSetAt = Date.distantPast
    private var driftBeganAt = Date.distantPast
    private var capturePaused = false
    private var pendingResumeFrameAX: CGRect?

    init(identity: WindowIdentity, onFailure: @escaping @MainActor (Error) -> Void) {
        output = PinMirrorOutput(
            renderer: panel.renderer,
            identity: identity,
            onFailure: { error in
                Task { @MainActor in onFailure(error) }
            }
        )
    }

    func start(window: SCWindow) async throws {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let scale = max(CGFloat(filter.pointPixelScale), 1)
        let width = max(Int(ceil(window.frame.width * scale)), 1)
        let height = max(Int(ceil(window.frame.height * scale)), 1)
        let configuration = streamConfiguration(width: width, height: height)
        lastStreamPixelSize = CGSize(width: width, height: height)

        let stream = SCStream(filter: filter, configuration: configuration, delegate: output)
        try stream.addStreamOutput(
            output,
            type: .screen,
            sampleHandlerQueue: output.queue
        )
        self.stream = stream
        try await stream.startCapture()
    }

    func show(frameAX: CGRect, primaryFlipHeight: CGFloat, reorder: Bool) {
        guard !isStopped else { return }
        lastShownFrameAX = frameAX
        if capturePaused {
            pendingResumeFrameAX = frameAX
        } else {
            updateStreamSize(for: frameAX)
        }
        panel.place(
            frame: CoordinateConverter.appKitRect(
                fromAX: frameAX,
                primaryFlipHeight: primaryFlipHeight
            ),
            reorder: reorder
        )
    }

    func setCapturePaused(_ paused: Bool) {
        guard !isStopped, capturePaused != paused else { return }
        capturePaused = paused
        if paused {
            output.pause()
            return
        }
        output.resume()
        if let frameAX = pendingResumeFrameAX ?? lastShownFrameAX {
            pendingResumeFrameAX = nil
            let target = pixelSize(for: frameAX)
            if !Self.isClose(target, lastStreamPixelSize) { applyStreamSize(target) }
        }
    }

    private func pixelSize(for frameAX: CGRect) -> CGSize {
        let scale = max(panel.backingScaleFactor, 1)
        return CGSize(
            width: max((frameAX.width * scale).rounded(), 1),
            height: max((frameAX.height * scale).rounded(), 1)
        )
    }

    /// Reconfiguring an `SCStream` flushes its capture pipeline, so doing it on
    /// every frame of an interactive resize is what makes the mirror stutter.
    /// Ride the resize out with the existing capture scaled into the panel and
    /// re-cut the stream once the frame settles, or once the mirror has been
    /// stretched for too long.
    private func updateStreamSize(for frameAX: CGRect) {
        guard stream != nil else { return }
        let target = pixelSize(for: frameAX)
        guard !Self.isClose(target, lastStreamPixelSize) else {
            desiredPixelSize = nil
            driftBeganAt = .distantPast
            return
        }

        let now = Date()
        if desiredPixelSize == nil { driftBeganAt = now }
        let stale = now.timeIntervalSince(driftBeganAt) >= Self.resizeStaleLimit

        if let desired = desiredPixelSize, Self.isClose(desired, target) {
            let settled = now.timeIntervalSince(desiredSetAt) >= Self.resizeSettleDelay
            guard settled || stale else { return }
        } else {
            desiredPixelSize = target
            desiredSetAt = now
            guard stale else { return }
        }
        applyStreamSize(target)
    }

    private func applyStreamSize(_ size: CGSize) {
        guard let stream else { return }
        desiredPixelSize = nil
        driftBeganAt = .distantPast
        lastStreamPixelSize = size
        let configuration = streamConfiguration(width: Int(size.width), height: Int(size.height))
        Task { [weak self] in
            do {
                try await stream.updateConfiguration(configuration)
            } catch {
                Log.pin.debug("Mirror resize failed: \(error.localizedDescription, privacy: .public)")
                self?.lastStreamPixelSize = .zero
            }
        }
    }

    private static func isClose(_ lhs: CGSize, _ rhs: CGSize) -> Bool {
        abs(lhs.width - rhs.width) < 2 && abs(lhs.height - rhs.height) < 2
    }

    private func streamConfiguration(width: Int, height: Int) -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        configuration.width = width
        configuration.height = height
        // A ceiling, not a target: ScreenCaptureKit only emits a frame when the
        // window actually redraws, so an idle mirror still costs nothing. Held
        // at 30 because a resize redraws every frame, and capturing a large
        // window at 60 there competes with the resize itself.
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        configuration.queueDepth = 3
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.showsCursor = false
        configuration.capturesAudio = false
        configuration.scalesToFit = true
        configuration.preservesAspectRatio = false
        configuration.shouldBeOpaque = false
        configuration.ignoreShadowsSingleWindow = true
        configuration.backgroundColor = CGColor.clear
        return configuration
    }

    func hide() {
        panel.orderOut(nil)
    }

    func stop() {
        guard !isStopped else { return }
        isStopped = true
        panel.orderOut(nil)
        panel.close()
        output.invalidate()

        guard let stream else { return }
        self.stream = nil
        Task {
            do {
                try await stream.stopCapture()
            } catch {
                Log.pin.debug("Mirror stop failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}

private final class PinMirrorOutput: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    let queue = DispatchQueue(label: "com.fancyzone.pin-mirror", qos: .userInteractive)

    private let renderer: AVSampleBufferVideoRenderer
    private let identity: WindowIdentity
    private let lock = NSLock()
    private var failureHandler: ((Error) -> Void)?
    private var didLogFirstFrame = false
    private var isPaused = false

    init(
        renderer: AVSampleBufferVideoRenderer,
        identity: WindowIdentity,
        onFailure: @escaping (Error) -> Void
    ) {
        self.renderer = renderer
        self.identity = identity
        failureHandler = onFailure
        super.init()
    }

    func invalidate() {
        lock.lock()
        failureHandler = nil
        lock.unlock()
    }

    func pause() {
        lock.lock()
        isPaused = true
        lock.unlock()
        renderer.flush()
    }

    func resume() {
        lock.lock()
        isPaused = false
        lock.unlock()
    }

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {
        lock.lock()
        let paused = isPaused
        lock.unlock()
        guard !paused else { return }
        guard outputType == .screen,
              sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(
                  sampleBuffer,
                  createIfNecessary: false
              ) as? [[SCStreamFrameInfo: Any]],
              let statusRaw = attachments.first?[.status] as? Int,
              SCFrameStatus(rawValue: statusRaw) == .complete
        else { return }

        lock.lock()
        let isFirstFrame = !didLogFirstFrame
        didLogFirstFrame = true
        lock.unlock()

        renderer.enqueue(sampleBuffer)
        if isFirstFrame {
            Log.pin.info(
                "Mirror first frame pid=\(self.identity.pid, privacy: .public) window=\(self.identity.windowNumber, privacy: .public)"
            )
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        lock.lock()
        let handler = failureHandler
        lock.unlock()
        handler?(error)
    }
}
