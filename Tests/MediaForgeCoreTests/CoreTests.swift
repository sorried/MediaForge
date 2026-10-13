import XCTest
@testable import MediaForgeCore
import Foundation

final class CoreTests: XCTestCase {
    func testCancelledProbeDoesNotReadMissingInput() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let missing = folder.appendingPathComponent("missing.mp4")
        let tools = FFmpegToolchain(ffmpegURL: missing, ffprobeURL: missing)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await MediaProbe(toolchain: tools).inspect(missing)
        }
        do {
            _ = try await task.value
            XCTFail("Expected probe cancellation")
        } catch is CancellationError {
            XCTAssertFalse(FileManager.default.fileExists(atPath: missing.path))
        }
    }

    func testSettingsValidationAndCodable() throws {
        XCTAssertThrowsError(try ConversionSettings(trimStart: .nan).validate())
        XCTAssertThrowsError(try ConversionSettings(trimStart: 2, trimEnd: 1).validate())
        XCTAssertThrowsError(try ConversionSettings(width: 101).validate())
        XCTAssertThrowsError(try ConversionSettings(audioBitrateKbps: 0).validate())
        XCTAssertThrowsError(try ConversionSettings(frameRate: .infinity).validate())
        XCTAssertThrowsError(try AppSettings(maxConcurrentJobs: 0).validate())
        let preset = ConversionPreset(name: "Small", profile: .mp4, settings: .init(width: 320))
        XCTAssertEqual(try JSONDecoder().decode(ConversionPreset.self, from: JSONEncoder().encode(preset)), preset)
    }
    func testCapabilityCancellationStopsActiveChildBeforeNextQuery() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let fifo = folder.appendingPathComponent("ready-pipe")
        let made = try await ProcessRunner().run(executable: URL(fileURLWithPath: "/usr/bin/mkfifo"), arguments: [fifo.path])
        XCTAssertEqual(made.exitCode, 0)
        let calls = folder.appendingPathComponent("calls")
        let executable = folder.appendingPathComponent("engine")
        let encoder = JSONEncoder()
        encoder.outputFormatting = .withoutEscapingSlashes
        let fifoLiteral = String(decoding: try encoder.encode(fifo.path), as: UTF8.self)
        let callsLiteral = String(decoding: try encoder.encode(calls.path), as: UTF8.self)
        let script = "#!/usr/bin/python3\nimport sys,signal\nfrom pathlib import Path\nsignal.signal(signal.SIGTERM,signal.SIG_IGN)\nwith open(" + callsLiteral + ",'a') as f: f.write(' '.join(sys.argv[1:])+'\\n')\nwith open(" + fifoLiteral + ",'w') as f: f.write('ready')\nsignal.pause()\n"
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let ready = expectation(description: "Capability child ready")
        let reader = Task {
            try await ProcessRunner().run(executable: URL(fileURLWithPath: "/usr/bin/python3"), arguments: ["-c", "import sys; data=open(sys.argv[1]).read(); sys.stdout.write(data); sys.stdout.flush()", fifo.path], timeout: 5, stdoutChunk: { _ in ready.fulfill() })
        }
        let tools = FFmpegToolchain(ffmpegURL: executable, ffprobeURL: executable)
        let task = Task { try await tools.capabilities() }
        await fulfillment(of: [ready], timeout: 5)
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Expected capability cancellation")
        } catch is CancellationError {
            XCTAssertEqual(try String(contentsOf: calls, encoding: .utf8), "-version\n")
        }
        reader.cancel()
        _ = await reader.result
    }

    func testCancelledCapabilityDiscoveryDoesNotLaunch() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let executable = folder.appendingPathComponent("engine")
        let marker = folder.appendingPathComponent("launched")
        let script = "#!/bin/sh\ntouch '" + marker.path + "'\nexit 0\n"
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let tools = FFmpegToolchain(ffmpegURL: executable, ffprobeURL: executable)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await tools.capabilities()
        }
        do {
            _ = try await task.value
            XCTFail("Expected capability cancellation")
        } catch is CancellationError {
            XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
        }
    }

    func testCapabilityDiscoveryRejectsMalformedEncoderFlags() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let wrapper = folder.appendingPathComponent("capabilities")
        let script = "#!/usr/bin/python3\nimport sys\nif '-encoders' in sys.argv:\n    print(' A..... flac valid\\n A12345 aac malformed\\n V????? mpeg4 malformed')\nelif '-muxers' in sys.argv:\n    print(' E flac FLAC\\n E mp4 MP4')\nelse:\n    print('fixture version')\n"
        try script.write(to: wrapper, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: wrapper.path)
        let capabilities = try await FFmpegToolchain(ffmpegURL: wrapper, ffprobeURL: wrapper).capabilities()
        XCTAssertEqual(capabilities.encoders, ["flac"])
        XCTAssertTrue(capabilities.supports(.flac))
        XCTAssertFalse(capabilities.supports(.mp4))
    }

    func testCapabilityErrorsIdentifyActualFailedCommand() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let executable = folder.appendingPathComponent("mock-engine")
        for failedArgument in ["-version", "-encoders", "-muxers"] {
            let invocations = folder.appendingPathComponent("invocations")
            try Data().write(to: invocations)
            let script = "#!/bin/sh\nprintf 'called\\n' >> '" + invocations.path + "'\nfor argument in \"$@\"; do\n  if [ \"$argument\" = \"" + failedArgument + "\" ]; then echo \"failure " + failedArgument + "\" >&2; exit 7; fi\ndone\nexit 0\n"
            try script.write(to: executable, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
            let toolchain = FFmpegToolchain(ffmpegURL: executable, ffprobeURL: executable)
            do {
                _ = try await toolchain.capabilities()
                XCTFail("Expected capability failure")
            } catch MediaForgeError.processFailed(let code, let message) {
                XCTAssertEqual(code, 7)
                XCTAssertTrue(message.contains("failure " + failedArgument))
            }
            let calls = try String(contentsOf: invocations, encoding: .utf8).split(separator: "\n").count
            XCTAssertEqual(calls, ["-version", "-encoders", "-muxers"].firstIndex(of: failedArgument)! + 1)
        }
    }

    func testProbeFrameRateRejectsMalformedRationals() {
        XCTAssertEqual(MediaProbe.frameRate("30000/1001"), 30000.0 / 1001)
        XCTAssertEqual(MediaProbe.frameRate("24/1"), 24)
        XCTAssertNil(MediaProbe.frameRate(nil))
        for value in ["", "24", "0/0", "1/0", "-1/2", "1/-2", "nan/1", "inf/1", "1/inf", "24/junk/1", "24//1", "/1", "1/", "1e308/1e-308"] {
            XCTAssertNil(MediaProbe.frameRate(value), value)
        }
    }

    func testOutputValidationRequiresPreservedAudio() throws {
        let url = URL(fileURLWithPath: "/output.mp4")
        let tools = FFmpegToolchain(ffmpegURL: URL(fileURLWithPath: "/ffmpeg"), ffprobeURL: URL(fileURLWithPath: "/ffprobe"))
        let engine = ConversionEngine(toolchain: tools)
        let capabilities = FFmpegCapabilities(version: "test", encoders: ["mpeg4", "aac"], muxers: ["mp4"])
        let request = ConversionRequest(inputURL: URL(fileURLWithPath: "/input.mp4"), outputURL: url, profile: .mp4)
        let video = MediaStream(index: 0, codecType: "video", codecName: "mpeg4")
        var metadata = MediaMetadata(url: url, formatName: "mp4", duration: 1, size: 100, streams: [video])
        XCTAssertThrowsError(try engine.validateOutput(metadata, request: request, expectedDuration: 1, expectsAudio: true, capabilities: capabilities))
        XCTAssertNoThrow(try engine.validateOutput(metadata, request: request, expectedDuration: 1, expectsAudio: false, capabilities: capabilities))
        metadata.streams.append(MediaStream(index: 1, codecType: "audio", codecName: "aac"))
        XCTAssertNoThrow(try engine.validateOutput(metadata, request: request, expectedDuration: 1, expectsAudio: true, capabilities: capabilities))
    }

    func testOutputValidationRejectsMissingOrInvalidDuration() throws {
        let url = URL(fileURLWithPath: "/output.mp4")
        let engine = ConversionEngine(toolchain: .init(ffmpegURL: url, ffprobeURL: url))
        let capabilities = FFmpegCapabilities(version: "test", encoders: ["mpeg4", "aac"], muxers: ["mp4"])
        let request = ConversionRequest(inputURL: URL(fileURLWithPath: "/input.mp4"), outputURL: url, profile: .mp4)
        let video = MediaStream(index: 0, codecType: "video", codecName: "mpeg4")
        for duration in [nil, 0, -1, 10, Double.nan, Double.infinity] as [Double?] {
            let metadata = MediaMetadata(url: url, formatName: "mp4", duration: duration, size: 100, streams: [video])
            XCTAssertThrowsError(try engine.validateOutput(metadata, request: request, expectedDuration: 1, expectsAudio: false, capabilities: capabilities))
        }
    }

    func testImageDimensionValidation() throws {
        XCTAssertNoThrow(try ConversionSettings(width: 7, height: 5).validate(requiresEvenDimensions: false))
        XCTAssertNoThrow(try ConversionSettings(width: 1, height: 16384).validate(requiresEvenDimensions: false))
        XCTAssertNoThrow(try ConversionSettings(width: 2, height: 16384).validate())
        for profile in [OutputProfile.png, .jpeg, .webp] {
            XCTAssertNoThrow(try AppSettings(presets: [.init(name: "Odd image", profile: profile, settings: .init(width: 7, height: 5))]).validate())
        }
        XCTAssertThrowsError(try AppSettings(presets: [.init(name: "Odd video", profile: .mp4, settings: .init(width: 7, height: 5))]).validate())
        for dimension in [0, -1, 16385] {
            XCTAssertThrowsError(try ConversionSettings(width: dimension).validate(requiresEvenDimensions: false))
            XCTAssertThrowsError(try ConversionSettings(height: dimension).validate(requiresEvenDimensions: false))
        }
        for dimension in [1, 5, 7, 16383] {
            XCTAssertThrowsError(try ConversionSettings(width: dimension).validate())
            XCTAssertThrowsError(try ConversionSettings(height: dimension).validate(requiresEvenDimensions: true))
        }
    }
    func testRealOddImageDimensions() async throws {
        let tools = try toolchain()
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let input = folder.appendingPathComponent("input.mp4")
        try await fixture(input, tools: tools)
        let capabilities = try await tools.capabilities()
        XCTAssertTrue(capabilities.supports(.png), "Integration engine must support PNG")
        XCTAssertTrue(capabilities.supports(.jpeg), "Integration engine must support JPEG")
        if !capabilities.supports(.webp) { print("Unavailable odd-image integration profile: webp") }
        for profile in [OutputProfile.png, .jpeg, .webp] where capabilities.supports(profile) {
            let output = folder.appendingPathComponent("odd." + profile.fileExtension)
            let result = try await ConversionEngine(toolchain: tools).convert(.init(inputURL: input, outputURL: output, profile: profile, settings: .init(width: 7, height: 5)))
            let video = result.metadata.streams.first { $0.codecType == "video" }
            XCTAssertEqual(video?.width, 7, profile.title)
            XCTAssertEqual(video?.height, 5, profile.title)
            let decoded = try await ProcessRunner().run(executable: tools.ffmpegURL, arguments: ["-hide_banner", "-loglevel", "error", "-i", output.path, "-frames:v", "1", "-pix_fmt", "rgb24", "-f", "rawvideo", "pipe:1"])
            XCTAssertEqual(decoded.exitCode, 0, decoded.stderrText)
            XCTAssertEqual(decoded.stdout.count, 7 * 5 * 3, profile.title)
        }
    }
    func testCapabilitiesDoNotPromiseH264OrMP3() {
        let capabilities = FFmpegCapabilities(version: "test", encoders: ["mpeg4", "aac", "flac"], muxers: ["mp4", "flac"])
        XCTAssertTrue(capabilities.supports(.mp4))
        XCTAssertFalse(capabilities.supports(.mp3))
        XCTAssertTrue(capabilities.detail(for: .mp4).contains("not H.264"))
    }
    func testAdditionalFormatCompositionAndUnavailableEncoders() throws {
        let native = FFmpegCapabilities(version: "native", encoders: ["aac", "mpeg4", "mpeg2video", "pcm_s16le", "pcm_s16be", "vorbis", "opus"], muxers: ["adts", "aiff", "ogg", "opus", "matroska", "webm", "avi", "mp4", "mpegts", "image2"])
        XCTAssertTrue(native.supports(.aac))
        XCTAssertTrue(native.supports(.aiff))
        XCTAssertTrue(native.supports(.mkv))
        XCTAssertTrue(native.supports(.avi))
        XCTAssertTrue(native.supports(.m4v))
        XCTAssertTrue(native.supports(.ts))
        XCTAssertFalse(native.supports(.ogg))
        XCTAssertFalse(native.supports(.opus))
        XCTAssertFalse(native.supports(.webm))
        XCTAssertFalse(native.supports(.webp))
        XCTAssertEqual(try native.composition(for: .ts).muxer, "mpegts")
        XCTAssertEqual(try native.composition(for: .ts).videoCodec, "mpeg2video")
        XCTAssertEqual(try native.composition(for: .avi).audioCodec, "pcm_s16le")
        XCTAssertEqual(try native.composition(for: .m4v).muxer, "mp4")
        let external = FFmpegCapabilities(version: "external", encoders: ["libvpx-vp9", "libopus", "libvorbis", "libwebp"], muxers: ["webm", "opus", "ogg", "image2"])
        XCTAssertTrue(external.supports(.webm))
        XCTAssertTrue(external.supports(.opus))
        XCTAssertTrue(external.supports(.ogg))
        XCTAssertTrue(external.supports(.webp))
        XCTAssertEqual(try external.composition(for: .webm).audioCodec, "opus")
        XCTAssertThrowsError(try external.composition(for: .webm, preference: .hardware))
    }
    func testAspectRatioArgumentsAndExplicitStretch() throws {
        let tools = FFmpegToolchain(ffmpegURL: URL(fileURLWithPath: "/ffmpeg"), ffprobeURL: URL(fileURLWithPath: "/ffprobe"))
        let capabilities = FFmpegCapabilities(version: "test", encoders: ["mpeg4", "aac"], muxers: ["mp4"])
        var request = ConversionRequest(inputURL: URL(fileURLWithPath: "/input"), outputURL: URL(fileURLWithPath: "/output"), profile: .mp4, settings: .init(width: 128, height: 128))
        let engine = ConversionEngine(toolchain: tools)
        let fit = try engine.makeArguments(request: request, temporary: request.outputURL, capabilities: capabilities)
        XCTAssertTrue(fit.contains("scale=128:128:force_original_aspect_ratio=decrease:force_divisible_by=2,pad=128:128:(ow-iw)/2:(oh-ih)/2,setsar=1"))
        request.settings.preserveAspectRatio = false
        let stretch = try engine.makeArguments(request: request, temporary: request.outputURL, capabilities: capabilities)
        XCTAssertTrue(stretch.contains("scale=128:128,setsar=1"))
        XCTAssertFalse(stretch.contains(where: { $0.contains("pad=") }))
        XCTAssertFalse(try JSONDecoder().decode(ConversionSettings.self, from: JSONEncoder().encode(request.settings)).preserveAspectRatio)
    }
    func testRealAspectRatioFitHasCenteredBlackBorders() async throws {
        let tools = try toolchain()
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let input = folder.appendingPathComponent("input.mp4")
        try await fixture(input, tools: tools)
        let output = folder.appendingPathComponent("square.mp4")
        let conversion = try await ConversionEngine(toolchain: tools).convert(.init(inputURL: input, outputURL: output, profile: .mp4, settings: .init(width: 128, height: 128, videoEncoderPreference: .software)))
        let video = conversion.metadata.streams.first { $0.codecType == "video" }
        XCTAssertEqual(video?.width, 128)
        XCTAssertEqual(video?.height, 128)
        let decoded = try await ProcessRunner().run(executable: tools.ffmpegURL, arguments: ["-hide_banner", "-loglevel", "error", "-i", output.path, "-frames:v", "1", "-pix_fmt", "rgb24", "-f", "rawvideo", "pipe:1"])
        XCTAssertEqual(decoded.exitCode, 0)
        XCTAssertEqual(decoded.stdout.count, 128 * 128 * 3)
        guard decoded.stdout.count == 128 * 128 * 3 else { return }
        let bytes = [UInt8](decoded.stdout)
        let firstRow = bytes[0..<(128 * 3)]
        let lastRow = bytes[(127 * 128 * 3)...]
        XCTAssertLessThan(firstRow.max() ?? 255, 12)
        XCTAssertLessThan(lastRow.max() ?? 255, 12)
        let middleRow = bytes[(64 * 128 * 3)..<(65 * 128 * 3)]
        XCTAssertGreaterThan(middleRow.max() ?? 0, 100)
    }
    func testM4AMuxerAndMissingContainer() {
        let capabilities = FFmpegCapabilities(version: "test", encoders: ["aac"], muxers: ["ipod"])
        XCTAssertTrue(capabilities.supports(.m4a))
        XCTAssertFalse(capabilities.supports(.mp4))
        XCTAssertFalse(FFmpegCapabilities(version: "test", encoders: ["aac"], muxers: []).supports(.m4a))
    }
    func testStdoutOverflowFailsExplicitly() async throws {
        do {
            _ = try await ProcessRunner().run(executable: URL(fileURLWithPath: "/usr/bin/python3"), arguments: ["-c", "import os; os.write(1,b'a'*9000000)"])
            XCTFail("Expected capture overflow")
        } catch let error as MediaForgeError {
            XCTAssertTrue(error.localizedDescription.contains("capture limit"))
        }
    }
    func testTargetSizeBudgetAndAudioSettings() throws {
        let budget = try TargetSizeBudget(targetSizeMB: 10, duration: 60, audioBitrateKbps: 128, hasAudio: true)
        XCTAssertThrowsError(try TargetSizeBudget(targetSizeMB: 0.0000001, duration: 0.00001, audioBitrateKbps: 128, hasAudio: false))
        let minimum = try TargetSizeBudget(targetSizeMB: 0.000001, duration: 0.00001, audioBitrateKbps: 128, hasAudio: false)
        XCTAssertEqual(minimum.targetBytes, 1)
        XCTAssertEqual(budget.targetBytes, 10_000_000)
        XCTAssertEqual(budget.videoBitrateKbps, 1152)
        XCTAssertThrowsError(try TargetSizeBudget(targetSizeMB: 0.001, duration: 60, audioBitrateKbps: 320, hasAudio: true))
        XCTAssertThrowsError(try ConversionSettings(sampleRate: 12345).validate())
        XCTAssertThrowsError(try ConversionSettings(channels: 3).validate())
        XCTAssertThrowsError(try ConversionSettings(targetSizeMB: .nan).validate())
        let capabilities = FFmpegCapabilities(version: "test", encoders: ["mpeg4"], muxers: ["mp4"])
        XCTAssertEqual(try capabilities.videoEncoder(preference: .software), "mpeg4")
        #if !os(macOS)
        XCTAssertThrowsError(try capabilities.videoEncoder(preference: .hardware))
        #else
        let native = FFmpegCapabilities(version: "test", encoders: ["h264_videotoolbox", "aac", "mpeg4"], muxers: ["mp4"])
        let url = URL(fileURLWithPath: "/fixture.mp4")
        let engine = ConversionEngine(toolchain: .init(ffmpegURL: url, ffprobeURL: url))
        for preference in VideoEncoderPreference.allCases {
            let request = ConversionRequest(inputURL: url, outputURL: url, profile: .mp4, settings: .init(videoEncoderPreference: preference))
            let arguments = try engine.makeArguments(request: request, temporary: url, capabilities: native)
            if preference == .software { XCTAssertFalse(arguments.contains("-allow_sw")) }
            else {
                let index = try XCTUnwrap(arguments.firstIndex(of: "-allow_sw"))
                XCTAssertEqual(arguments[index + 1], preference == .automatic ? "1" : "0")
            }
        }
        #endif
    }
    func testOutputValidationRejectsWrongFrameRate() throws {
        let url = URL(fileURLWithPath: "/output.mp4")
        let engine = ConversionEngine(toolchain: .init(ffmpegURL: url, ffprobeURL: url))
        let capabilities = FFmpegCapabilities(version: "test", encoders: ["mpeg4", "aac"], muxers: ["mp4"])
        let request = ConversionRequest(inputURL: URL(fileURLWithPath: "/input.mp4"), outputURL: url, profile: .mp4, settings: .init(frameRate: 24))
        for rate in [nil, 30.0, Double.nan, Double.infinity] as [Double?] {
            let video = MediaStream(index: 0, codecType: "video", codecName: "mpeg4", frameRate: rate)
            let metadata = MediaMetadata(url: url, formatName: "mp4", duration: 1, size: 100, streams: [video])
            XCTAssertThrowsError(try engine.validateOutput(metadata, request: request, expectedDuration: 1, expectsAudio: false, capabilities: capabilities))
        }
    }

    func testDecodeVerificationHonorsCancellationBeforeLaunch() async {
        let missing = URL(fileURLWithPath: "/does/not/exist")
        let engine = ConversionEngine(toolchain: .init(ffmpegURL: missing, ffprobeURL: missing))
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await engine.verifyDecoding(missing)
        }
        do {
            try await task.value
            XCTFail("Expected cancellation before decoder launch")
        } catch is CancellationError {}
        catch { XCTFail("Wrong error: \(error)") }
    }

    func testDecodeVerificationRejectsEmptyAudioStream() async throws {
        let tools = try toolchain()
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let empty = folder.appendingPathComponent("empty.wav")
        let created = try await ProcessRunner().run(executable: URL(fileURLWithPath: "/usr/bin/python3"), arguments: ["-c", "import sys,wave; w=wave.open(sys.argv[1],'wb'); w.setparams((1,2,44100,0,'NONE','not compressed')); w.close()", empty.path])
        XCTAssertEqual(created.exitCode, 0)
        do {
            try await ConversionEngine(toolchain: tools).verifyDecoding(empty)
            XCTFail("Expected empty-stream rejection")
        } catch MediaForgeError.processFailed(let code, let diagnostics) {
            XCTAssertNotEqual(code, 0)
            XCTAssertTrue(diagnostics.lowercased().contains("empty output"), diagnostics)
        }
    }

    func testDecodeVerificationRejectsInvalidMedia() async throws {
        let tools = try toolchain()
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let invalid = folder.appendingPathComponent("broken.mp4")
        try Data("not a media file".utf8).write(to: invalid)
        do {
            try await ConversionEngine(toolchain: tools).verifyDecoding(invalid)
            XCTFail("Expected decoding failure")
        } catch MediaForgeError.processFailed(let code, let diagnostics) {
            XCTAssertNotEqual(code, 0)
            XCTAssertFalse(diagnostics.isEmpty)
        }
    }

    func testRealRequestedFrameRate() async throws {
        let tools = try toolchain()
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let input = folder.appendingPathComponent("input.mp4")
        try await fixture(input, tools: tools)
        for rate in [24.0, 30000.0 / 1001] {
            let output = folder.appendingPathComponent("rate-" + String(rate) + ".mp4")
            let result = try await ConversionEngine(toolchain: tools).convert(.init(inputURL: input, outputURL: output, profile: .mp4, settings: .init(frameRate: rate, videoEncoderPreference: .software)))
            let actual = try XCTUnwrap(result.metadata.streams.first { $0.codecType == "video" }?.frameRate)
            XCTAssertEqual(actual, rate, accuracy: 0.01)
            XCTAssertTrue(result.metadata.hasAudio)
        }
    }

    func testRealAudioControlsAndMeasuredTargetSize() async throws {
        let tools = try toolchain()
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let input = folder.appendingPathComponent("input.mp4")
        try await fixture(input, tools: tools)
        let engine = ConversionEngine(toolchain: tools)
        let audio = try await engine.convert(.init(inputURL: input, outputURL: folder.appendingPathComponent("mono.wav"), profile: .wav, settings: .init(sampleRate: 48000, channels: 1)))
        XCTAssertEqual(audio.metadata.streams.first?.sampleRate, 48000)
        XCTAssertEqual(audio.metadata.streams.first?.channels, 1)
        let target = try await engine.convert(.init(inputURL: input, outputURL: folder.appendingPathComponent("budget.mp4"), profile: .mp4, settings: .init(targetSizeMB: 0.25, videoEncoderPreference: .software)))
        XCTAssertEqual(target.requestedTargetSizeBytes, 250000)
        XCTAssertNotNil(target.targetSizeDeviationFraction)
        XCTAssertEqual(target.targetSizeDeviationFraction ?? 0, Double(target.metadata.size) / 250000 - 1, accuracy: 0.00001)
    }
    func testStreamingProgressDoesNotAccumulateCapturedOutput() async throws {
        let chunks = ProgressRecorder()
        let result = try await ProcessRunner().run(executable: URL(fileURLWithPath: "/usr/bin/python3"), arguments: ["-c", "import os; os.write(1, b\"x\" * 9000000)"], captureStdout: false, stdoutChunk: { bytes in
            chunks.append(.init(fraction: nil, processedSeconds: Double(bytes.count), speed: nil, frame: nil))
        })
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.isEmpty)
        XCTAssertEqual(chunks.values.reduce(0) { $0 + $1.processedSeconds }, 9000000)
    }

    func testLegacySettingsDecodeWithDefaults() throws {
        let settings = try JSONDecoder().decode(ConversionSettings.self, from: Data(#"{"width":320,"removeAudio":true}"#.utf8))
        XCTAssertEqual(settings.width, 320)
        XCTAssertTrue(settings.removeAudio)
        XCTAssertEqual(settings.videoEncoderPreference, .automatic)
        XCTAssertNil(settings.sampleRate)
        XCTAssertTrue(settings.preserveAspectRatio)
    }
    func testQueueBoundedSchedulingTransitionsAndRecovery() throws {
        func request() -> ConversionRequest {
            .init(inputURL: URL(fileURLWithPath: "/input"), outputURL: URL(fileURLWithPath: "/output"), profile: .mp4)
        }
        var queue = try QueueState(limit: 2)
        let first = request(), second = request(), third = request()
        try queue.enqueue(first)
        try queue.enqueue(second)
        try queue.enqueue(third)
        XCTAssertThrowsError(try queue.enqueue(first))
        XCTAssertEqual(queue.claimNext()?.id, first.id)
        XCTAssertEqual(queue.claimNext()?.id, second.id)
        XCTAssertNil(queue.claimNext())
        XCTAssertThrowsError(try queue.finish(id: third.id, status: .completed))
        try queue.finish(id: first.id, status: .completed)
        XCTAssertEqual(queue.claimNext()?.id, third.id)
        XCTAssertThrowsError(try queue.finish(id: first.id, status: .failed))
        var restored = try JSONDecoder().decode(QueueState.self, from: JSONEncoder().encode(queue))
        restored.recoverInterruptedJobs()
        XCTAssertEqual(restored.jobs.map(\.status), [.completed, .waiting, .waiting])
        try restored.finish(id: second.id, status: .cancelled)
        XCTAssertEqual(restored.claimNext()?.id, third.id)
    }
    func testRealConversionWithLongUnicodeSourceName() async throws {
        let tools = try toolchain()
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let input = folder.appendingPathComponent(String(repeating: "я", count: 125) + ".mp4")
        try await fixture(input, tools: tools)
        let original = try Data(contentsOf: input)
        let output = OutputManager.suggestedURL(input: input, directory: folder, profile: .flac)
        let converted = try await ConversionEngine(toolchain: tools).convert(.init(inputURL: input, outputURL: output, profile: .flac))
        XCTAssertEqual(converted.outputURL, output)
        XCTAssertTrue(converted.metadata.hasAudio)
        XCTAssertLessThanOrEqual(output.lastPathComponent.utf8.count, 255)
        XCTAssertEqual(try Data(contentsOf: input), original)
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: folder.path).contains { $0.hasPrefix(".mediaforge-") })
    }

    func testLongUnicodeOutputNamesCanBePublished() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        for stem in [String(repeating: "a", count: 250), String(repeating: "я", count: 120)] {
            let input = folder.appendingPathComponent(stem + ".wav")
            try Data("original".utf8).write(to: input)
            let first = OutputManager.suggestedURL(input: input, directory: folder, profile: .flac)
            let second = OutputManager.suggestedURL(input: input, directory: folder, profile: .flac, reserved: [first])
            XCTAssertLessThanOrEqual(first.lastPathComponent.utf8.count, 255)
            XCTAssertLessThanOrEqual(second.lastPathComponent.utf8.count, 255)
            XCTAssertNotEqual(first, second)
            let staged = folder.appendingPathComponent(UUID().uuidString)
            try Data("converted".utf8).write(to: staged)
            try OutputManager.commit(temporary: staged, destination: second)
            XCTAssertEqual(try Data(contentsOf: second), Data("converted".utf8))
            XCTAssertEqual(try Data(contentsOf: input), Data("original".utf8))
        }
    }

    func testOutputNamingHonorsStandardizedReservations() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let input = folder.appendingPathComponent("source.mov")
        let reserved = URL(fileURLWithPath: folder.path + "/nested/../source-converted.mp4")
        let suggested = OutputManager.suggestedURL(input: input, directory: folder, profile: .mp4, reserved: [reserved])
        XCTAssertEqual(suggested.lastPathComponent, "source-converted-2.mp4")
        XCTAssertNotEqual(suggested.standardizedFileURL, reserved.standardizedFileURL)
    }

    func testOutputNamingAndExclusiveCommit() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let input = folder.appendingPathComponent("source.mov")
        let first = OutputManager.suggestedURL(input: input, directory: folder, profile: .mp4)
        let second = OutputManager.suggestedURL(input: input, directory: folder, profile: .mp4, reserved: [first])
        XCTAssertEqual(first.lastPathComponent, "source-converted.mp4")
        XCTAssertEqual(second.lastPathComponent, "source-converted-2.mp4")
        let temporary = folder.appendingPathComponent("temporary")
        try Data("first".utf8).write(to: temporary)
        try OutputManager.commit(temporary: temporary, destination: first)
        let other = folder.appendingPathComponent("other")
        try Data("other".utf8).write(to: other)
        XCTAssertThrowsError(try OutputManager.commit(temporary: other, destination: first))
        XCTAssertEqual(try Data(contentsOf: first), Data("first".utf8))
    }
    func testPublicationRejectsSymlinksEmptyFilesAndDanglingDestinations() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("source.mov")
        let output = folder.appendingPathComponent("source-converted.mp4")
        let missing = folder.appendingPathComponent("missing")
        try FileManager.default.createSymbolicLink(at: output, withDestinationURL: missing)
        XCTAssertEqual(OutputManager.suggestedURL(input: source, directory: folder, profile: .mp4).lastPathComponent, "source-converted-2.mp4")
        let staged = folder.appendingPathComponent("staged")
        try Data("converted".utf8).write(to: staged)
        XCTAssertThrowsError(try OutputManager.commit(temporary: staged, destination: output))
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: output.path), missing.path)
        XCTAssertFalse(FileManager.default.fileExists(atPath: missing.path))
        let alias = folder.appendingPathComponent("alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: staged)
        let destination = folder.appendingPathComponent("result.mp4")
        XCTAssertThrowsError(try OutputManager.commit(temporary: alias, destination: destination))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        let empty = folder.appendingPathComponent("empty")
        try Data().write(to: empty)
        XCTAssertThrowsError(try OutputManager.commit(temporary: empty, destination: destination))
        XCTAssertThrowsError(try OutputManager.commit(temporary: staged, destination: staged))
        XCTAssertEqual(try Data(contentsOf: staged), Data("converted".utf8))
    }

    func testHistoryRejectsNonlocalStorageURL() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let local = folder.appendingPathComponent("history.json")
        let original = Data("preserved local file".utf8)
        try original.write(to: local)
        var components = URLComponents()
        components.scheme = "https"
        components.host = "example.invalid"
        components.path = local.path
        XCTAssertThrowsError(try HistoryStore(url: XCTUnwrap(components.url)))
        XCTAssertEqual(try Data(contentsOf: local), original)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), ["history.json"])
    }

    func testHistoryRejectsSymlinkAndOversizedFile() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let oversized = folder.appendingPathComponent("large.json")
        try Data().write(to: oversized)
        let handle = try FileHandle(forWritingTo: oversized)
        try handle.truncate(atOffset: 32 * 1024 * 1024 + 1)
        try handle.close()
        let alias = folder.appendingPathComponent("alias.json")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: oversized)
        for url in [oversized, alias, folder] {
            let store = try HistoryStore(url: url)
            do {
                _ = try await store.load()
                XCTFail("Expected invalid history rejection")
            } catch MediaForgeError.fileOperation(let message) {
                XCTAssertTrue(message.contains("regular file"), message)
            }
        }
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: oversized.path)[.size] as? NSNumber, NSNumber(value: 32 * 1024 * 1024 + 1))
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: alias.path), oversized.path)
    }

    func testHistoryPersistenceBoundedAndCorruptionPreserved() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("history.json")
        let store = try HistoryStore(url: url, limit: 2)
        let request = ConversionRequest(inputURL: folder.appendingPathComponent("input"), outputURL: folder.appendingPathComponent("output"), profile: .mp4)
        let first = HistoryEntry(request: request, status: .completed)
        let second = HistoryEntry(request: request, status: .failed, errorMessage: "error")
        let third = HistoryEntry(request: request, status: .cancelled)
        try await store.append(first)
        try await store.append(second)
        try await store.append(third)
        let entries = try await store.load()
        XCTAssertEqual(entries.map(\.id), [second.id, third.id])
        XCTAssertEqual(entries.first?.errorMessage, "error")
        let corrupted = Data("broken history".utf8)
        try corrupted.write(to: url)
        do { try await store.append(first); XCTFail("Expected corruption to be preserved") }
        catch { XCTAssertEqual(try Data(contentsOf: url), corrupted) }
    }
    func testProgressAcrossChunkBoundaries() {
        let progress = ProgressRecorder()
        let parser = FFmpegProgressParser(duration: 10, callback: { progress.append($0) })
        parser.consume(Data("out_time_".utf8))
        parser.consume(Data("us=2500000\nframe=30\nspeed=2x\nprogress=continue\n".utf8))
        XCTAssertEqual(progress.values.first?.fraction, 0.25)
        XCTAssertEqual(progress.values.first?.frame, 30)
    }
    func testProgressRejectsNonfiniteTimesAndUnknownFields() {
        let progress = ProgressRecorder()
        let parser = FFmpegProgressParser(duration: .infinity, callback: { progress.append($0) })
        for value in ["nan", "inf", "-inf", "-100", "invalid"] {
            parser.consume(Data(("unknown=ignored\nout_time_us=" + value + "\nprogress=continue\n").utf8))
        }
        XCTAssertEqual(progress.values.count, 5)
        for update in progress.values {
            XCTAssertEqual(update.processedSeconds, 0)
            XCTAssertNil(update.fraction)
        }
        parser.consume(Data(repeating: 97, count: 70000))
        parser.consume(Data("out_time_us=1000000\nprogress=continue\n".utf8))
        XCTAssertEqual(progress.values.last?.processedSeconds, 1)
    }

    func testLargeStderrKeepsFailureTailWithoutBlocking() async throws {
        let output = try await ProcessRunner().run(executable: URL(fileURLWithPath: "/usr/bin/python3"), arguments: ["-c", "import os; os.write(2,b'a'*9000000); os.write(2,b'final failure detail'); raise SystemExit(7)"])
        XCTAssertEqual(output.exitCode, 7)
        XCTAssertEqual(output.stderr.count, 8 * 1024 * 1024)
        XCTAssertTrue(output.stderrText.hasSuffix("final failure detail"))
        XCTAssertTrue(output.stdout.isEmpty)
    }

    func testProcessArgumentsPreserveUnicodeAndShellMetacharacters() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let input = folder.appendingPathComponent("файл с пробелом;$(touch injected)\n.wav")
        let bytes = Data("original content".utf8)
        try bytes.write(to: input)
        let output = try await ProcessRunner().run(executable: URL(fileURLWithPath: "/usr/bin/python3"), arguments: ["-c", "import sys; from pathlib import Path; sys.stdout.buffer.write(Path(sys.argv[1]).read_bytes())", input.path])
        XCTAssertEqual(output.exitCode, 0)
        XCTAssertEqual(output.stdout, bytes)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), [input.lastPathComponent])
    }

    func testDrainsBothPipesWithoutDeadlock() async throws {
        let output = try await ProcessRunner().run(executable: URL(fileURLWithPath: "/usr/bin/python3"), arguments: ["-c", "import os; os.write(1,b'a'*2000000); os.write(2,b'b'*2000000)"])
        XCTAssertEqual(output.exitCode, 0)
        XCTAssertEqual(output.stdout.count, 2000000)
        XCTAssertEqual(output.stderr.count, 2000000)
    }
    func testCancellationBeforeLaunch() async {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await ProcessRunner().run(executable: URL(fileURLWithPath: "/does/not/exist"), arguments: [])
        }
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch is CancellationError {}
        catch { XCTFail("Wrong error: \(error)") }
    }
    func testCancellationEscalatesIgnoredTerminate() async throws {
        let launched = expectation(description: "Child ready")
        let task = Task {
            try await ProcessRunner().run(executable: URL(fileURLWithPath: "/usr/bin/python3"), arguments: ["-c", "import os,signal; signal.signal(signal.SIGTERM,signal.SIG_IGN); os.write(1,b'ready'); signal.pause()"], stdoutChunk: { _ in launched.fulfill() })
        }
        await fulfillment(of: [launched], timeout: 5)
        let start = Date()
        task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch is CancellationError {}
        catch { XCTFail("Wrong error: \(error)") }
        XCTAssertLessThan(Date().timeIntervalSince(start), 5)
    }
    func testInvalidProcessDeadlineDoesNotLaunchChild() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let marker = folder.appendingPathComponent("launched")
        for timeout in [Double.nan, .infinity, -.infinity, -1, 0, 31_536_001] {
            do {
                _ = try await ProcessRunner().run(executable: URL(fileURLWithPath: "/usr/bin/touch"), arguments: [marker.path], timeout: timeout)
                XCTFail("Expected invalid deadline")
            } catch MediaForgeError.invalidSettings {}
            XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
        }
        let remote = try XCTUnwrap(URL(string: "https://example.invalid/tool"))
        do {
            _ = try await ProcessRunner().run(executable: remote, arguments: [])
            XCTFail("Expected nonlocal executable rejection")
        } catch MediaForgeError.fileOperation {}
        let result = try await ProcessRunner().run(executable: URL(fileURLWithPath: "/usr/bin/touch"), arguments: [marker.path], timeout: nil)
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: marker.path))
    }

    func testProcessDeadline() async throws {
        do {
            _ = try await ProcessRunner().run(executable: URL(fileURLWithPath: "/usr/bin/python3"), arguments: ["-c", "import signal; signal.pause()"], timeout: 0.2)
            XCTFail("Expected timeout")
        } catch let error as MediaForgeError {
            XCTAssertTrue(error.localizedDescription.contains("time limit"))
        }
    }
    func testRealProbeAndConversions() async throws {
        let tools = try toolchain()
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let input = folder.appendingPathComponent("input with spaces;$(echo no).mp4")
        try await fixture(input, tools: tools)
        let metadata = try await MediaProbe(toolchain: tools).inspect(input)
        XCTAssertTrue(metadata.hasVideo)
        XCTAssertTrue(metadata.hasAudio)
        XCTAssertEqual(metadata.streams.first(where: { $0.codecType == "video" })?.width, 160)
        XCTAssertEqual(metadata.duration ?? 0, 2, accuracy: 0.1)
        let capabilities = try await tools.capabilities()
        XCTAssertTrue(capabilities.encoders.contains("mpeg4"))
        let engine = ConversionEngine(toolchain: tools)
        let unsupported = OutputProfile.allCases.filter { !capabilities.supports($0) }.map(\.rawValue)
        print("Unavailable integration profiles: " + (unsupported.isEmpty ? "none" : unsupported.joined(separator: ", ")))
        for profile in OutputProfile.allCases where capabilities.supports(profile) {
            print("Converting integration profile: " + profile.rawValue)
            let destination = folder.appendingPathComponent("converted." + profile.fileExtension)
            let recorder = ProgressRecorder()
            let conversion = try await engine.convert(.init(inputURL: input, outputURL: destination, profile: profile, settings: .init(trimStart: 0.2, trimEnd: 1.2, width: profile.isAudio ? nil : 80)), progress: { recorder.append($0) })
            XCTAssertGreaterThan(conversion.metadata.size, 0)
            XCTAssertEqual(conversion.metadata.url, destination)
            XCTAssertEqual(recorder.values.last?.fraction, 1)
            if !profile.isAudio { XCTAssertEqual(conversion.metadata.streams.first(where: { $0.codecType == "video" })?.width, 80) }
            if !profile.isImage { XCTAssertEqual(conversion.metadata.duration ?? 0, 1, accuracy: 0.2) }
        }
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: folder.path).contains(where: { $0.hasPrefix(".mediaforge-") }))
    }
    func testExistingOutputRemainsUntouched() async throws {
        let tools = try toolchain()
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let output = folder.appendingPathComponent("existing.mp4")
        let sentinel = Data("do not replace".utf8)
        try sentinel.write(to: output)
        do {
            _ = try await ConversionEngine(toolchain: tools).convert(.init(inputURL: folder.appendingPathComponent("missing.mp4"), outputURL: output, profile: .mp4))
            XCTFail("Expected conflict")
        } catch MediaForgeError.outputExists {}
        XCTAssertEqual(try Data(contentsOf: output), sentinel)
    }
    func testRejectsEmptyAndInvalidMedia() async throws {
        let tools = try toolchain()
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        for (name, bytes) in [("empty", Data()), ("invalid", Data("not media".utf8))] {
            let file = folder.appendingPathComponent(name)
            try bytes.write(to: file)
            do { _ = try await MediaProbe(toolchain: tools).inspect(file); XCTFail("Expected rejection") }
            catch { XCTAssertFalse(error is CancellationError) }
        }
    }
    func testCommandArgumentsAreSeparateAndSettingsApplied() throws {
        let tools = FFmpegToolchain(ffmpegURL: URL(fileURLWithPath: "/ffmpeg"), ffprobeURL: URL(fileURLWithPath: "/ffprobe"))
        let input = URL(fileURLWithPath: "/tmp/a ; $(touch should-not-exist).mp4")
        let request = ConversionRequest(inputURL: input, outputURL: URL(fileURLWithPath: "/tmp/final.mp4"), profile: .mp4, settings: .init(trimStart: 2, trimEnd: 5, width: 320, videoBitrateKbps: 800, removeAudio: true))
        let arguments = try ConversionEngine(toolchain: tools).makeArguments(request: request, temporary: URL(fileURLWithPath: "/tmp/job.mp4"), capabilities: .init(version: "test", encoders: ["mpeg4", "aac"], muxers: ["mp4"]))
        XCTAssertTrue(arguments.contains(input.path))
        XCTAssertTrue(arguments.contains("scale=320:-2,setsar=1"))
        XCTAssertTrue(arguments.contains("800k"))
        XCTAssertTrue(arguments.contains("-an"))
        XCTAssertFalse(arguments.contains("-y"))
        XCTAssertEqual(arguments[arguments.firstIndex(of: "-t")! + 1], "3.0")
    }
    func testConcurrentOutputCollisionIsExclusive() async throws {
        let tools = try toolchain()
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let input = folder.appendingPathComponent("input.mp4")
        try await fixture(input, tools: tools)
        let output = folder.appendingPathComponent("one.mp4")
        let request = ConversionRequest(inputURL: input, outputURL: output, profile: .mp4)
        let engine = ConversionEngine(toolchain: tools)
        let first = Task { try await engine.convert(request) }
        let second = Task { try await engine.convert(request) }
        var successes = 0, conflicts = 0
        for task in [first, second] {
            do { _ = try await task.value; successes += 1 }
            catch MediaForgeError.outputExists { conflicts += 1 }
        }
        XCTAssertEqual(successes, 1)
        XCTAssertEqual(conflicts, 1)
        let committedMetadata = try await MediaProbe(toolchain: tools).inspect(output)
        XCTAssertTrue(committedMetadata.hasVideo)
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: folder.path).contains(where: { $0.hasPrefix(".mediaforge-") }))
    }
    func testDecoderFailureDoesNotPublishAndCleansWorkspace() async throws {
        let tools = try toolchain()
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let input = folder.appendingPathComponent("original.mp4")
        try await fixture(input, tools: tools)
        let original = try Data(contentsOf: input)
        let marker = folder.appendingPathComponent("decoder-launched")
        let wrapper = folder.appendingPathComponent("ffmpeg-wrapper")
        let encoder = JSONEncoder()
        encoder.outputFormatting = .withoutEscapingSlashes
        let executableLiteral = String(decoding: try encoder.encode(tools.ffmpegURL.path), as: UTF8.self)
        let markerLiteral = String(decoding: try encoder.encode(marker.path), as: UTF8.self)
        let script = "#!/usr/bin/python3\nimport os, sys\nfrom pathlib import Path\nif '-xerror' in sys.argv:\n    Path(" + markerLiteral + ").write_text('ready')\n    sys.stderr.write('injected decoder failure\\n')\n    sys.exit(7)\nos.execv(" + executableLiteral + ", [" + executableLiteral + "] + sys.argv[1:])\n"
        try script.write(to: wrapper, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: wrapper.path)
        let wrapped = FFmpegToolchain(ffmpegURL: wrapper, ffprobeURL: tools.ffprobeURL)
        let destination = folder.appendingPathComponent("not-published.mp4")
        do {
            _ = try await ConversionEngine(toolchain: wrapped).convert(.init(inputURL: input, outputURL: destination, profile: .mp4, settings: .init(videoEncoderPreference: .software)))
            XCTFail("Expected decoder-stage failure")
        } catch MediaForgeError.processFailed(let code, let diagnostics) {
            XCTAssertEqual(code, 7, diagnostics)
            XCTAssertTrue(diagnostics.contains("injected decoder failure"), diagnostics)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: marker.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertEqual(try Data(contentsOf: input), original)
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: folder.path).contains { $0.hasPrefix(".mediaforge-") })
    }

    func testConversionCancellationRemovesTemporaryOutput() async throws {
        let tools = try toolchain()
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let input = folder.appendingPathComponent("long.mp4")
        let fixtureOutput = try await ProcessRunner().run(executable: tools.ffmpegURL, arguments: ["-hide_banner", "-loglevel", "error", "-f", "lavfi", "-i", "testsrc2=size=640x480:rate=30", "-t", "30", "-c:v", "mpeg4", "-q:v", "5", input.path])
        XCTAssertEqual(fixtureOutput.exitCode, 0)
        let original = try Data(contentsOf: input)
        let output = folder.appendingPathComponent("cancelled.mp4")
        let began = expectation(description: "Conversion emitted progress")
        began.assertForOverFulfill = false
        let task = Task {
            try await ConversionEngine(toolchain: tools).convert(.init(inputURL: input, outputURL: output, profile: .mp4, settings: .init(width: 1920, height: 1440)), progress: { _ in began.fulfill() })
        }
        await fulfillment(of: [began], timeout: 10)
        task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch is CancellationError {}
        catch { XCTFail("Wrong error: \(error)") }
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        XCTAssertEqual(try Data(contentsOf: input), original)
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: folder.path).contains(where: { $0.hasPrefix(".mediaforge-") }))
    }
    private func toolchain() throws -> FFmpegToolchain {
        let environment = ProcessInfo.processInfo.environment
        if let ffmpeg = environment["MEDIAFORGE_FFMPEG"], let ffprobe = environment["MEDIAFORGE_FFPROBE"] {
            return .init(ffmpegURL: URL(fileURLWithPath: ffmpeg), ffprobeURL: URL(fileURLWithPath: ffprobe))
        }
        do { return try .discover(allowExternalTools: true) }
        catch {
            if environment["REQUIRE_MEDIA_INTEGRATION"] == "1" { throw error }
            throw XCTSkip("Real-media tests need FFmpeg and FFprobe: \(error.localizedDescription)")
        }
    }
    private func makeFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("MediaForge-tests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
    private func fixture(_ url: URL, tools: FFmpegToolchain) async throws {
        let output = try await ProcessRunner().run(executable: tools.ffmpegURL, arguments: ["-hide_banner", "-loglevel", "error", "-f", "lavfi", "-i", "testsrc=size=160x120:rate=15", "-f", "lavfi", "-i", "sine=frequency=440:sample_rate=44100", "-t", "2", "-c:v", "mpeg4", "-pix_fmt", "yuv420p", "-c:a", "aac", url.path])
        guard output.exitCode == 0 else { throw MediaForgeError.processFailed(output.exitCode, output.stderrText) }
    }
}
private final class ProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [ConversionProgress] = []
    func append(_ value: ConversionProgress) { lock.lock(); storage.append(value); lock.unlock() }
    var values: [ConversionProgress] { lock.lock(); defer { lock.unlock() }; return storage }
}
