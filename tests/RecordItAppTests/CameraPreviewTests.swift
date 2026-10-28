import AppKit
import AVFoundation
import XCTest
@testable import RecordItApp

@MainActor
final class CameraPreviewTests: XCTestCase {
    func testPreviewAppliesThePreferredCameraFormatAfterAddingTheInput() {
        var configurationSteps: [String] = []

        addPreviewCameraInputThenApplySelectedFormat(
            addInput: { configurationSteps.append("input") },
            applyFormat: { configurationSteps.append("format") }
        )

        XCTAssertEqual(configurationSteps, ["input", "format"])
    }

    func testPreviewShowsTheSelectedCameraWheneverACameraModeIsIdle() {
        XCTAssertEqual(cameraPreviewCameraID(
            showsPreview: true, capturesCamera: true, selectedCameraID: "razer",
            isRecording: false, isBusy: false
        ), "razer")
    }

    func testPreviewStaysAwayWhenTurnedOffRecordingOrWithoutACamera() {
        XCTAssertNil(cameraPreviewCameraID(
            showsPreview: false, capturesCamera: true, selectedCameraID: "razer",
            isRecording: false, isBusy: false
        ))
        XCTAssertNil(cameraPreviewCameraID(
            showsPreview: true, capturesCamera: false, selectedCameraID: "razer",
            isRecording: false, isBusy: false
        ))
        XCTAssertNil(cameraPreviewCameraID(
            showsPreview: true, capturesCamera: true, selectedCameraID: nil,
            isRecording: false, isBusy: false
        ))
        XCTAssertNil(cameraPreviewCameraID(
            showsPreview: true, capturesCamera: true, selectedCameraID: "razer",
            isRecording: true, isBusy: false
        ))
        XCTAssertNil(cameraPreviewCameraID(
            showsPreview: true, capturesCamera: true, selectedCameraID: "razer",
            isRecording: false, isBusy: true
        ))
    }

    func testInlinePreviewStartsTheSelectedCameraAndStopsWhenHidden() async {
        let sessions = FakeCameraPreviewSessionFactory()
        let preview = InlineCameraPreviewController(makeSessionController: sessions.make)

        await preview.show(cameraID: "razer")

        XCTAssertTrue(preview.isPreviewOpen)
        XCTAssertEqual(preview.model?.state, .running)
        XCTAssertEqual(sessions.made.map(\.startedCameraIDs), [["razer"]])

        await preview.hide()

        XCTAssertFalse(preview.isPreviewOpen)
        XCTAssertNil(preview.model)
        XCTAssertEqual(sessions.made.first?.stopCallCount, 1)
    }

    func testInlinePreviewSwitchesCamerasByStoppingTheOldSessionFirst() async {
        let sessions = FakeCameraPreviewSessionFactory()
        let preview = InlineCameraPreviewController(makeSessionController: sessions.make)

        await preview.show(cameraID: "razer")
        await preview.show(cameraID: "facetime")

        XCTAssertEqual(sessions.made.count, 2)
        XCTAssertEqual(sessions.made[0].stopCallCount, 1)
        XCTAssertEqual(sessions.made[1].startedCameraIDs, ["facetime"])
        XCTAssertEqual(preview.model?.cameraID, "facetime")
        XCTAssertEqual(preview.model?.state, .running)
    }

    func testInlinePreviewIgnoresShowingTheCameraItIsAlreadyShowing() async {
        let sessions = FakeCameraPreviewSessionFactory()
        let preview = InlineCameraPreviewController(makeSessionController: sessions.make)

        await preview.show(cameraID: "razer")
        await preview.show(cameraID: "razer")

        XCTAssertEqual(sessions.made.count, 1)
        XCTAssertEqual(sessions.made[0].stopCallCount, 0)
    }

    func testHidingAClosedInlinePreviewDoesNothing() async {
        let sessions = FakeCameraPreviewSessionFactory()
        let preview = InlineCameraPreviewController(makeSessionController: sessions.make)

        await preview.hide()

        XCTAssertFalse(preview.isPreviewOpen)
        XCTAssertTrue(sessions.made.isEmpty)
    }

    func testPreviewButtonRequiresAnIdleSelectedCamera() {
        XCTAssertFalse(cameraPreviewButtonIsDisabled(
            hasSelectedCamera: true,
            isRecording: false,
            isBusy: false
        ))
        XCTAssertTrue(cameraPreviewButtonIsDisabled(
            hasSelectedCamera: false,
            isRecording: false,
            isBusy: false
        ))
        XCTAssertTrue(cameraPreviewButtonIsDisabled(
            hasSelectedCamera: true,
            isRecording: true,
            isBusy: false
        ))
        XCTAssertTrue(cameraPreviewButtonIsDisabled(
            hasSelectedCamera: true,
            isRecording: false,
            isBusy: true
        ))
    }

    func testPreviewStartsAndStopsTheSelectedCameraSession() async {
        let controller = FakeCameraPreviewSessionController()
        let model = CameraPreviewModel(cameraID: "razer", controller: controller)

        await model.start()

        XCTAssertEqual(controller.startedCameraIDs, ["razer"])
        XCTAssertEqual(model.state, .running)

        await model.stop()

        XCTAssertEqual(controller.stopCallCount, 1)
        XCTAssertEqual(model.state, .idle)
    }

    func testPreviewReportsCameraStartupErrors() async {
        let controller = FakeCameraPreviewSessionController()
        controller.startError = RecordItError.message("Camera unavailable")
        let model = CameraPreviewModel(cameraID: "missing", controller: controller)

        await model.start()

        XCTAssertEqual(model.state, .failed("Camera unavailable"))
    }
}

@MainActor
private final class FakeCameraPreviewSessionFactory {
    private(set) var made: [FakeCameraPreviewSessionController] = []

    func make() -> any CameraPreviewSessionControlling {
        let controller = FakeCameraPreviewSessionController()
        made.append(controller)
        return controller
    }
}

private final class FakeCameraPreviewSessionController: CameraPreviewSessionControlling {
    let session = AVCaptureSession()
    var startedCameraIDs: [String] = []
    var stopCallCount = 0
    var startError: Error?

    func start(cameraID: String) async throws {
        startedCameraIDs.append(cameraID)
        if let startError { throw startError }
    }

    func stop() async {
        stopCallCount += 1
    }
}
