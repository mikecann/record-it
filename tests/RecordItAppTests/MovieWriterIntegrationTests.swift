import AVFoundation
import CoreMedia
import CoreVideo
import XCTest
@testable import RecordItApp

final class MovieWriterIntegrationTests: XCTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        // Hosted CI and restricted environments may have no hardware encoder.
        // Keep the real encoding checks enabled by default on developer Macs.
        if ProcessInfo.processInfo.environment["RECORD_IT_SKIP_HARDWARE_TESTS"] == "1" {
            throw XCTSkip("Hardware video encoding is disabled for this test run.")
        }
    }

    func testWriterFinalizesAPlayableVariableFrameRateHEVCMovie() async throws {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("record-it-\(UUID().uuidString).mov")
        defer { try? FileManager.default.removeItem(at: outputURL) }
        let encoder = try XCTUnwrap(preferredHardwareVideoEncoder(
            in: HardwareVideoEncoderCatalog.availableEncoders(),
            savedID: ""
        ))
        let writer = try MovieWriter(
            outputURL: outputURL,
            width: 128,
            height: 128,
            includesAudio: false,
            encoderConfiguration: EncoderConfiguration(
                encoder: encoder,
                rateControl: preferredRateControl(
                    savedMode: .vbr,
                    supportedModes: encoder.supportedRateControls
                ) ?? .cbr,
                bitRateMbps: 10,
                maximumBitRateMbps: 15,
                qualityParameter: 20
            )
        )

        for frame in [0, 1, 3] {
            writer.appendVideo(try videoSampleBuffer(frame: frame, width: 128, height: 128))
        }
        let progress = writer.progress()
        XCTAssertEqual(progress.videoSamplesWritten, 2)
        XCTAssertEqual(progress.videoTimelineDuration, 0.1, accuracy: 0.001)
        XCTAssertEqual(progress.writerStatus, .writing)
        try await writer.finish()

        let asset = AVURLAsset(url: outputURL)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        let size = try await track.load(.naturalSize)
        let nominalFrameRate = try await track.load(.nominalFrameRate)
        let duration = try await asset.load(.duration)
        XCTAssertEqual(size.width, 128)
        XCTAssertEqual(size.height, 128)
        XCTAssertGreaterThan(nominalFrameRate, 0)
        XCTAssertLessThanOrEqual(nominalFrameRate, 30)
        XCTAssertGreaterThan(duration.seconds, 0)

        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
        )
        reader.add(output)
        XCTAssertTrue(reader.startReading())
        var frameCount = 0
        while output.copyNextSampleBuffer() != nil {
            frameCount += 1
        }
        XCTAssertEqual(frameCount, 3, "Sparse screen updates should not manufacture catch-up frames.")
    }

    func testACameraDelayMovesThePictureEarlierAndTagsTheFile() async throws {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("record-it-camera-delay-\(UUID().uuidString).mov")
        defer { try? FileManager.default.removeItem(at: outputURL) }
        let encoder = try XCTUnwrap(preferredHardwareVideoEncoder(
            in: HardwareVideoEncoderCatalog.availableEncoders(),
            savedID: ""
        ))
        // The webcam's picture runs 0.1 s (three frames) behind its sound.
        let writer = try MovieWriter(
            outputURL: outputURL,
            width: 128,
            height: 128,
            includesAudio: false,
            encoderConfiguration: EncoderConfiguration(
                encoder: encoder,
                rateControl: preferredRateControl(
                    savedMode: .vbr,
                    supportedModes: encoder.supportedRateControls
                ) ?? .cbr,
                bitRateMbps: 10,
                maximumBitRateMbps: 15,
                qualityParameter: 20
            ),
            cameraDelay: CMTime(value: 1, timescale: 10)
        )
        for frame in 0...6 {
            writer.appendVideo(try videoSampleBuffer(frame: frame, width: 128, height: 128))
        }
        try await writer.finish()

        // Frame 3 was seen at 0.1 s, but it shows what was in front of the
        // camera at the start, so it plays first; frame 4 plays a frame later.
        let frames = try await decodedFrames(outputURL)
        let first = try XCTUnwrap(frames.first)
        XCTAssertEqual(first.time, 0, accuracy: 0.001)
        XCTAssertEqual(Double(first.level), 120, accuracy: 12, "frame 3's picture")
        let second = try XCTUnwrap(frames.dropFirst().first)
        XCTAssertEqual(second.time, 1.0 / 30, accuracy: 0.001)
        XCTAssertEqual(Double(second.level), 160, accuracy: 12, "frame 4's picture")

        // The file says it's been corrected, so an editor doesn't do it again.
        let metadata = try await AVURLAsset(url: outputURL).load(.metadata)
        let tag = metadata.first { $0.identifier == AVMetadataItem.identifier(forKey: MovieWriter.cameraDelayKey, keySpace: .quickTimeMetadata) }
        let value = try await tag?.load(.stringValue)
        XCTAssertEqual(value, "0.100")
    }

    func testWriterPreservesALongStaticGapWithoutEncodingHundredsOfDuplicateFrames() async throws {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("record-it-static-gap-\(UUID().uuidString).mov")
        defer { try? FileManager.default.removeItem(at: outputURL) }
        let encoder = try XCTUnwrap(preferredHardwareVideoEncoder(
            in: HardwareVideoEncoderCatalog.availableEncoders(),
            savedID: ""
        ))
        let writer = try MovieWriter(
            outputURL: outputURL,
            width: 128,
            height: 128,
            includesAudio: false,
            encoderConfiguration: EncoderConfiguration(
                encoder: encoder,
                rateControl: preferredRateControl(
                    savedMode: .vbr,
                    supportedModes: encoder.supportedRateControls
                ) ?? .cbr,
                bitRateMbps: 10,
                maximumBitRateMbps: 15,
                qualityParameter: 20
            )
        )

        for frame in [0, 1, 300] {
            writer.appendVideo(try videoSampleBuffer(frame: frame, width: 128, height: 128))
        }
        try await writer.finish()

        let asset = AVURLAsset(url: outputURL)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        let duration = try await asset.load(.duration)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        reader.add(output)
        XCTAssertTrue(reader.startReading())
        var frameCount = 0
        while output.copyNextSampleBuffer() != nil { frameCount += 1 }

        XCTAssertLessThanOrEqual(frameCount, 10, "A static gap must stay bounded instead of generating catch-up frames.")
        XCTAssertGreaterThanOrEqual(duration.seconds, 10)
    }

    func testWriterAcceptsEveryRateControlAdvertisedByEveryHardwareEncoder() async throws {
        let encoders = HardwareVideoEncoderCatalog.availableEncoders()
        XCTAssertFalse(encoders.isEmpty)

        for encoder in encoders {
            for rateControl in RateControlMode.allCases where encoder.supportedRateControls.contains(rateControl) {
                let outputURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("record-it-\(rateControl.rawValue)-\(UUID().uuidString).mov")
                defer { try? FileManager.default.removeItem(at: outputURL) }
                let writer = try MovieWriter(
                    outputURL: outputURL,
                    width: 128,
                    height: 128,
                    includesAudio: false,
                    encoderConfiguration: EncoderConfiguration(
                        encoder: encoder,
                        rateControl: rateControl,
                        bitRateMbps: 10,
                        maximumBitRateMbps: 15,
                        qualityParameter: 20
                    )
                )

                writer.appendVideo(try videoSampleBuffer(frame: 0, width: 128, height: 128))
                writer.appendVideo(try videoSampleBuffer(frame: 1, width: 128, height: 128))
                try await writer.finish()

                XCTAssertGreaterThan(
                    try FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? Int ?? 0,
                    0,
                    "\(encoder.displayName) with \(rateControl.displayName) should produce a non-empty movie."
                )
            }
        }
    }

    func testWriterAcceptsEveryScreenQualityPresetOnEveryHardwareEncoder() async throws {
        let encoders = HardwareVideoEncoderCatalog.availableEncoders()
        XCTAssertTrue(
            encoders.contains { $0.codec == .hevc && $0.supportsConstantQuality },
            "The HEVC hardware encoder should support constant-quality screen recording."
        )

        for encoder in encoders {
            for quality in ScreenQuality.allCases {
                let outputURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("record-it-\(quality.rawValue)-\(UUID().uuidString).mov")
                defer { try? FileManager.default.removeItem(at: outputURL) }
                let base = EncoderConfiguration(
                    encoder: encoder,
                    rateControl: preferredRateControl(
                        savedMode: .cqp,
                        supportedModes: encoder.supportedRateControls
                    ) ?? .cbr,
                    bitRateMbps: 10,
                    maximumBitRateMbps: 15,
                    qualityParameter: 30
                )
                let writer = try MovieWriter(
                    outputURL: outputURL,
                    width: 128,
                    height: 128,
                    includesAudio: false,
                    encoderConfiguration: screenEncoderConfiguration(base: base, quality: quality)
                )

                writer.appendVideo(try videoSampleBuffer(frame: 0, width: 128, height: 128))
                writer.appendVideo(try videoSampleBuffer(frame: 1, width: 128, height: 128))
                try await writer.finish()

                XCTAssertGreaterThan(
                    try FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? Int ?? 0,
                    0,
                    "\(encoder.displayName) with \(quality.displayName) should produce a non-empty movie."
                )
            }
        }
    }

    func testAnUnfinishedMovieIsStillPlayableUpToTheLastFragment() async throws {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("record-it-\(UUID().uuidString).mov")
        defer { try? FileManager.default.removeItem(at: outputURL) }
        let encoder = try XCTUnwrap(preferredHardwareVideoEncoder(
            in: HardwareVideoEncoderCatalog.availableEncoders(),
            savedID: ""
        ))
        var writer: MovieWriter? = try MovieWriter(
            outputURL: outputURL,
            width: 128,
            height: 128,
            includesAudio: false,
            encoderConfiguration: EncoderConfiguration(
                encoder: encoder,
                rateControl: .cbr,
                bitRateMbps: 5,
                maximumBitRateMbps: 5,
                qualityParameter: 20
            )
        )

        // Fifteen seconds of timeline, then the app "crashes" without finishing.
        for frame in stride(from: 0, through: 450, by: 15) {
            writer?.appendVideo(try videoSampleBuffer(frame: frame, width: 128, height: 128))
            try await Task.sleep(for: .milliseconds(20))
        }
        try await Task.sleep(for: .milliseconds(500))
        writer = nil

        let asset = AVURLAsset(url: outputURL)
        let duration = try await asset.load(.duration)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        XCTAssertFalse(tracks.isEmpty)
        XCTAssertGreaterThanOrEqual(duration.seconds, 5)
    }
}

/// Each decoded frame's time and the grey level of its first pixel.
private func decodedFrames(_ url: URL) async throws -> [(time: Double, level: Int)] {
    let asset = AVURLAsset(url: url)
    let tracks = try await asset.loadTracks(withMediaType: .video)
    let track = try XCTUnwrap(tracks.first)
    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderTrackOutput(
        track: track,
        outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
    )
    reader.add(output)
    XCTAssertTrue(reader.startReading())
    var frames: [(time: Double, level: Int)] = []
    while let sample = output.copyNextSampleBuffer() {
        guard let pixels = CMSampleBufferGetImageBuffer(sample) else { continue }
        CVPixelBufferLockBaseAddress(pixels, .readOnly)
        let level = CVPixelBufferGetBaseAddress(pixels).map { Int($0.load(fromByteOffset: 4 * 64 * 128 + 4 * 64, as: UInt8.self)) } ?? -1
        CVPixelBufferUnlockBaseAddress(pixels, .readOnly)
        frames.append((CMSampleBufferGetPresentationTimeStamp(sample).seconds, level))
    }
    return frames
}

private func videoSampleBuffer(frame: Int, width: Int, height: Int) throws -> CMSampleBuffer {
    var pixelBuffer: CVPixelBuffer?
    let attributes: [CFString: Any] = [
        kCVPixelBufferCGImageCompatibilityKey: true,
        kCVPixelBufferCGBitmapContextCompatibilityKey: true
    ]
    let pixelStatus = CVPixelBufferCreate(
        kCFAllocatorDefault,
        width,
        height,
        kCVPixelFormatType_32BGRA,
        attributes as CFDictionary,
        &pixelBuffer
    )
    guard pixelStatus == kCVReturnSuccess, let pixelBuffer else {
        throw RecordItError.message("Could not create a test pixel buffer.")
    }

    CVPixelBufferLockBaseAddress(pixelBuffer, [])
    if let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) {
        memset(baseAddress, Int32(frame * 40), CVPixelBufferGetDataSize(pixelBuffer))
    }
    CVPixelBufferUnlockBaseAddress(pixelBuffer, [])

    var formatDescription: CMVideoFormatDescription?
    try checkOSStatus(
        CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescriptionOut: &formatDescription
        )
    )
    guard let formatDescription else {
        throw RecordItError.message("Could not create a test video format.")
    }

    var timing = CMSampleTimingInfo(
        duration: CMTime(value: 1, timescale: 30),
        presentationTimeStamp: CMTime(value: CMTimeValue(frame), timescale: 30),
        decodeTimeStamp: .invalid
    )
    var sampleBuffer: CMSampleBuffer?
    try checkOSStatus(
        CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescription: formatDescription,
            sampleTiming: &timing,
            sampleBufferOut: &sampleBuffer
        )
    )
    guard let sampleBuffer else {
        throw RecordItError.message("Could not create a test video sample.")
    }
    return sampleBuffer
}

private func checkOSStatus(_ status: OSStatus) throws {
    guard status == noErr else {
        throw RecordItError.message("Core Media returned OSStatus \(status).")
    }
}
