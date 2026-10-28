import AppKit
import AVFoundation
import SwiftUI

protocol CameraPreviewSessionControlling: AnyObject {
    var session: AVCaptureSession { get }

    func start(cameraID: String) async throws
    func stop() async
}

enum CameraPreviewState: Equatable {
    case idle
    case starting
    case running
    case stopping
    case failed(String)
}

@MainActor
final class CameraPreviewModel: ObservableObject {
    @Published private(set) var state: CameraPreviewState = .idle

    let cameraID: String
    private let controller: any CameraPreviewSessionControlling
    private var stopRequested = false

    init(
        cameraID: String,
        controller: any CameraPreviewSessionControlling = SystemCameraPreviewSessionController()
    ) {
        self.cameraID = cameraID
        self.controller = controller
    }

    var session: AVCaptureSession { controller.session }

    func start() async {
        guard state != .running, state != .starting else { return }
        stopRequested = false
        state = .starting

        do {
            try await controller.start(cameraID: cameraID)
            guard !stopRequested, !Task.isCancelled else {
                await controller.stop()
                state = .idle
                return
            }
            state = .running
        } catch {
            state = stopRequested || Task.isCancelled
                ? .idle
                : .failed(error.localizedDescription)
        }
    }

    func stop() async {
        guard state != .idle, state != .stopping else { return }
        stopRequested = true
        state = .stopping
        await controller.stop()
        state = .idle
    }
}

final class SystemCameraPreviewSessionController: CameraPreviewSessionControlling, @unchecked Sendable {
    let session = AVCaptureSession()

    private let sessionQueue = DispatchQueue(label: "com.mikerosoft.record-it.camera-preview")
    private var configurationLockedDevice: AVCaptureDevice?

    func start(cameraID: String) async throws {
        guard await requestCameraPreviewAccess() else {
            throw RecordItError.message(
                "Camera access is required. Enable it in Privacy & Security → Camera."
            )
        }

        try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async { [self] in
                do {
                    // Reapply the exact format every time the preview opens. Another
                    // camera app may have changed the device format since the last run.
                    try configureSession(cameraID: cameraID)
                    if !session.isRunning {
                        session.startRunning()
                    }
                    guard session.isRunning else {
                        throw RecordItError.message("The camera preview could not be started.")
                    }
                    if let activeInput = session.inputs
                        .compactMap({ $0 as? AVCaptureDeviceInput })
                        .first(where: { $0.device.hasMediaType(.video) }) {
                        let activeFormat = activeInput.device.activeFormat
                        let dimensions = CMVideoFormatDescriptionGetDimensions(
                            activeFormat.formatDescription
                        )
                        let duration = activeInput.device.activeVideoMinFrameDuration
                        let frameRate = duration.seconds > 0 ? 1 / duration.seconds : 0
                        RecordingDiagnostics.shared.log(
                            "camera.preview running format=\(dimensions.width)x\(dimensions.height) "
                                + "fps=\(String(format: "%.6f", frameRate))"
                        )
                    }
                    continuation.resume()
                } catch {
                    releaseDeviceConfigurationLock()
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func stop() async {
        await withCheckedContinuation { continuation in
            sessionQueue.async { [self] in
                if session.isRunning {
                    session.stopRunning()
                }
                releaseDeviceConfigurationLock()
                continuation.resume()
            }
        }
    }

    private func configureSession(cameraID: String) throws {
        guard let device = CaptureDeviceCatalog.camera(withID: cameraID) else {
            throw RecordItError.message("The selected camera is no longer available.")
        }
        guard let format = CaptureDeviceCatalog.preferredDeviceFormat(for: device) else {
            throw RecordItError.message("The selected camera has no format that supports 30 fps.")
        }
        let frameRateRanges = format.videoSupportedFrameRateRanges
        let frameRateOptions = frameRateRanges.map {
            CameraFrameRateRangeOption(
                minimumFrameRate: $0.minFrameRate,
                maximumFrameRate: $0.maxFrameRate
            )
        }
        guard let frameRateRangeIndex = preferredCameraFrameRateRangeIndex(in: frameRateOptions) else {
            throw RecordItError.message("The selected camera did not report a usable frame duration.")
        }
        let frameRateRange = frameRateRanges[frameRateRangeIndex]

        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.inputs.forEach(session.removeInput)

        let input = try AVCaptureDeviceInput(device: device)
        try addPreviewCameraInputThenApplySelectedFormat {
            guard session.canAddInput(input) else {
                throw RecordItError.message("The selected camera could not be added to the preview.")
            }
            session.addInput(input)
        } applyFormat: {
            try device.lockForConfiguration()
            configurationLockedDevice = device

            // On macOS, setting activeFormat directly makes the selected input
            // format authoritative only while the configuration lock is held.
            // Keep the lock until Preview closes, otherwise startRunning() is
            // allowed to silently replace 4K30 with a lower format.
            device.activeFormat = format
            // Use the duration reported by the hardware rather than constructing
            // an idealized 1/30 value. Some UVC cameras advertise a slightly
            // different timing and raise an Objective-C exception for 1/30.
            device.activeVideoMinFrameDuration = frameRateRange.minFrameDuration
            device.activeVideoMaxFrameDuration = frameRateRange.minFrameDuration
        }
    }

    private func releaseDeviceConfigurationLock() {
        configurationLockedDevice?.unlockForConfiguration()
        configurationLockedDevice = nil
    }
}

func addPreviewCameraInputThenApplySelectedFormat(
    addInput: () throws -> Void,
    applyFormat: () throws -> Void
) rethrows {
    // AVCaptureDevice can reject or replace an active format until its input
    // belongs to the session, so keep this ordering explicit and tested.
    try addInput()
    try applyFormat()
}

@MainActor
final class InlineCameraPreviewController: ObservableObject {
    @Published private(set) var model: CameraPreviewModel?

    private let makeSessionController: @MainActor () -> any CameraPreviewSessionControlling
    // Show and hide run one at a time. A new camera session must not start
    // while the previous one still holds the device's configuration lock.
    private var lastTransition: Task<Void, Never>?

    init(
        makeSessionController: @escaping @MainActor () -> any CameraPreviewSessionControlling = {
            SystemCameraPreviewSessionController()
        }
    ) {
        self.makeSessionController = makeSessionController
    }

    var isPreviewOpen: Bool { model != nil }

    func show(cameraID: String) async {
        await runAfterPreviousTransition { [self] in
            guard model?.cameraID != cameraID else { return }
            await stopCurrentPreview()
            let model = CameraPreviewModel(cameraID: cameraID, controller: makeSessionController())
            self.model = model
            await model.start()
        }
    }

    func hide() async {
        await runAfterPreviousTransition { [self] in
            await stopCurrentPreview()
        }
    }

    private func stopCurrentPreview() async {
        guard let model else { return }
        self.model = nil
        await model.stop()
    }

    private func runAfterPreviousTransition(_ transition: @escaping @MainActor () async -> Void) async {
        let previous = lastTransition
        let task = Task { @MainActor in
            await previous?.value
            await transition()
        }
        lastTransition = task
        await task.value
    }
}

@MainActor
struct InlineCameraPreviewPanel: View {
    let cameraName: String
    @ObservedObject var model: CameraPreviewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                CameraPreviewSurface(session: model.session)
                    .accessibilityLabel("Live camera preview for \(cameraName)")

                switch model.state {
                case .idle, .starting:
                    ProgressView("Starting camera…")
                        .padding(16)
                        .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 10))
                case .failed(let message):
                    VStack(spacing: 12) {
                        Image(systemName: "video.slash.fill")
                            .font(.system(size: 30))
                        Text(message)
                            .multilineTextAlignment(.center)
                        Button("Try Again") {
                            Task { await model.start() }
                        }
                    }
                    .frame(maxWidth: 360)
                    .padding(22)
                    .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 12))
                case .running, .stopping:
                    EmptyView()
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.black)
            // Size from the full window width. Without the fixed vertical size
            // the Grid row proposes almost no height and the picture shrinks.
            .aspectRatio(16 / 9, contentMode: .fit)
            .fixedSize(horizontal: false, vertical: true)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            HStack(spacing: 6) {
                previewStatus
                Text("Preview only. Nothing is being recorded.")
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
        }
    }

    @ViewBuilder
    private var previewStatus: some View {
        switch model.state {
        case .running:
            Label("Live", systemImage: "circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Label("Unavailable", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        case .idle, .starting, .stopping:
            ProgressView()
                .controlSize(.mini)
        }
    }
}

private struct CameraPreviewSurface: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> CameraPreviewNSView {
        CameraPreviewNSView(session: session)
    }

    func updateNSView(_ nsView: CameraPreviewNSView, context: Context) {
        nsView.session = session
    }
}

private final class CameraPreviewNSView: NSView {
    private let previewLayer = AVCaptureVideoPreviewLayer()

    var session: AVCaptureSession? {
        get { previewLayer.session }
        set { previewLayer.session = newValue }
    }

    init(session: AVCaptureSession) {
        super.init(frame: .zero)
        wantsLayer = true
        layer = CALayer()
        layer?.backgroundColor = NSColor.black.cgColor
        previewLayer.session = session
        previewLayer.videoGravity = .resizeAspect
        layer?.addSublayer(previewLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        previewLayer.frame = bounds
    }
}

/// The camera the preview should be showing, or nil for no preview. The
/// preview comes up by itself in Camera and Both modes and comes back after
/// a take; the recorder needs the camera while a take is starting or running.
func cameraPreviewCameraID(
    showsPreview: Bool,
    capturesCamera: Bool,
    selectedCameraID: String?,
    isRecording: Bool,
    isBusy: Bool
) -> String? {
    guard showsPreview, capturesCamera, !isRecording, !isBusy else { return nil }
    return selectedCameraID
}

func cameraPreviewButtonIsDisabled(
    hasSelectedCamera: Bool,
    isRecording: Bool,
    isBusy: Bool
) -> Bool {
    !hasSelectedCamera || isRecording || isBusy
}

private func requestCameraPreviewAccess() async -> Bool {
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized:
        true
    case .notDetermined:
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .video) { granted in
                continuation.resume(returning: granted)
            }
        }
    case .denied, .restricted:
        false
    @unknown default:
        false
    }
}
