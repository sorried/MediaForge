import Foundation
import XCTest
import MediaForgeCore
@testable import MediaForge

final class QueueModelTests: XCTestCase {
    @MainActor
    func testShutdownCancelsActiveCapabilityProcess() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("MediaForge-engine-shutdown-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
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
        let script = "#!/usr/bin/python3\nimport sys,signal\nsignal.signal(signal.SIGTERM,signal.SIG_IGN)\nwith open(" + callsLiteral + ",'a') as f: f.write(' '.join(sys.argv[1:])+'\\n')\nwith open(" + fifoLiteral + ",'w') as f: f.write('ready')\nsignal.pause()\n"
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let tools = FFmpegToolchain(ffmpegURL: executable, ffprobeURL: executable)
        let store = StateStore(url: folder.appendingPathComponent("state.json"))
        let model = ForgeModel(store: store, toolchain: tools)
        let reader = Task {
            try await ProcessRunner().run(executable: URL(fileURLWithPath: "/usr/bin/python3"), arguments: ["-c", "import sys; sys.stdout.write(open(sys.argv[1]).read())", fifo.path], timeout: 5)
        }
        let preparation = Task { @MainActor in await model.prepare() }
        let signal = await reader.result
        await model.cancelAndWait()
        await preparation.value
        let ready = try signal.get()
        XCTAssertEqual(ready.exitCode, 0, ready.stderrText)
        XCTAssertEqual(String(decoding: ready.stdout, as: UTF8.self), "ready")
        XCTAssertTrue(model.isTerminating)
        XCTAssertFalse(model.engineReady)
        XCTAssertNil(model.capabilities)
        XCTAssertTrue(model.diagnostics.isEmpty)
        XCTAssertEqual(try String(contentsOf: calls, encoding: .utf8), "-version\n")
        XCTAssertEqual(try store.load().queue.count, 0)
    }

    @MainActor
    func testFailedEnginePreparationCanRefreshWithoutStartingQueue() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("MediaForge-engine-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let executable = folder.appendingPathComponent("failing-engine")
        let script = "#!/bin/sh\nprintf 'capability failure\\n' >&2\nexit 17\n"
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let tools = FFmpegToolchain(ffmpegURL: executable, ffprobeURL: executable)
        let model = ForgeModel(store: StateStore(url: folder.appendingPathComponent("state.json")), toolchain: tools)
        let cancelled = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            await model.prepare()
        }
        await cancelled.value
        XCTAssertFalse(model.engineReady)
        XCTAssertTrue(model.diagnostics.isEmpty)
        await model.prepare()
        XCTAssertFalse(model.engineReady)
        XCTAssertNil(model.capabilities)
        XCTAssertTrue(model.diagnostics.contains { $0.contains("capability failure") })
        let count = model.diagnostics.count
        await model.prepare()
        XCTAssertEqual(model.diagnostics.count, count)
        await model.refreshEngine()
        XCTAssertGreaterThan(model.diagnostics.count, count)
        XCTAssertFalse(model.engineReady)
        XCTAssertFalse(model.queueStarted)
        await model.cancelAndWait()
        let diagnostics = model.diagnostics
        await model.refreshEngine()
        XCTAssertEqual(model.diagnostics, diagnostics)
    }

    @MainActor
    func testRealSerialBatchPublishesAndPersistsHistory() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let ffmpeg = environment["MEDIAFORGE_FFMPEG"], let ffprobe = environment["MEDIAFORGE_FFPROBE"] else {
            if environment["REQUIRE_MEDIA_INTEGRATION"] == "1" {
                XCTFail("Required app integration tool paths are missing")
                return
            }
            throw XCTSkip("App integration requires explicit engine paths")
        }
        let tools = FFmpegToolchain(ffmpegURL: URL(fileURLWithPath: ffmpeg), ffprobeURL: URL(fileURLWithPath: ffprobe))
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("MediaForge-batch-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let input = folder.appendingPathComponent("source.wav")
        let fixture = try await ProcessRunner().run(executable: tools.ffmpegURL, arguments: ["-v", "error", "-f", "lavfi", "-i", "sine=frequency=440:sample_rate=44100", "-t", "0.3", input.path])
        XCTAssertEqual(fixture.exitCode, 0, fixture.stderrText)
        let original = try Data(contentsOf: input)
        let store = StateStore(url: folder.appendingPathComponent("state.json"))
        let model = ForgeModel(store: store, toolchain: tools)
        await model.prepare()
        XCTAssertTrue(model.engineReady)
        model.settings.simultaneousJobs = 1
        model.settings.outputDirectory = folder
        model.queue = (0..<3).map { _ in QueueEntry(source: input, profile: .flac, settings: .init()) }
        model.startQueue()
        XCTAssertEqual(model.activeCount, 1)
        XCTAssertEqual(model.queue.filter { $0.status == .pending }.count, 2)
        await model.waitForQueue()
        XCTAssertEqual(model.activeCount, 0)
        XCTAssertFalse(model.queueStarted)
        XCTAssertTrue(model.queue.allSatisfy { $0.status == .completed }, model.diagnostics.joined(separator: "\n"))
        let outputs = model.queue.compactMap { $0.output }
        XCTAssertEqual(Set(outputs).count, 3)
        for output in outputs {
            let metadata = try await MediaProbe(toolchain: tools).inspect(output)
            XCTAssertEqual(metadata.streams.first { $0.codecType == "audio" }?.codecName, "flac")
        }
        XCTAssertEqual(try store.load().history.count, 3)
        XCTAssertTrue(try store.load().queue.allSatisfy { $0.status == .completed })
        let missing = QueueEntry(source: folder.appendingPathComponent("removed.wav"), profile: .flac, settings: .init())
        let following = QueueEntry(source: input, profile: .flac, settings: .init())
        model.queue = [missing, following]
        model.startQueue()
        await model.waitForQueue()
        XCTAssertEqual(missing.status, .failed)
        XCTAssertNotNil(missing.error)
        XCTAssertNil(missing.output)
        XCTAssertEqual(following.status, .completed, model.diagnostics.joined(separator: "\n"))
        let recoveredOutput = try XCTUnwrap(following.output)
        XCTAssertFalse(outputs.contains(recoveredOutput))
        let persisted = try store.load()
        XCTAssertEqual(persisted.history.count, 5)
        XCTAssertEqual(persisted.queue.map { $0.status }, [.failed, .completed])
        XCTAssertEqual(model.activeCount, 0)
        XCTAssertFalse(model.queueStarted)
        XCTAssertEqual(try Data(contentsOf: input), original)
    }

    @MainActor
    func testRestorePendingAndInterruptedQueueNeverStartsAutomatically() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("MediaForge-restore-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = StateStore(url: folder.appendingPathComponent("state.json"))
        let pending = SavedQueueEntry(id: UUID(), source: folder.appendingPathComponent("pending.mp4"), profile: .mp4, conversionSettings: .init(width: 320), outputDirectory: folder)
        let interrupted = SavedQueueEntry(id: UUID(), source: folder.appendingPathComponent("running.mp4"), profile: .mp4, conversionSettings: .init(), status: .running, output: folder.appendingPathComponent("possible-result.mp4"))
        try store.save(PersistedState(queue: [pending, interrupted]))
        let model = ForgeModel(store: store)
        XCTAssertFalse(model.queueStarted)
        XCTAssertEqual(model.activeCount, 0)
        XCTAssertEqual(model.queue.map { $0.id }, [pending.id, interrupted.id])
        XCTAssertEqual(model.queue[0].status, .pending)
        model.startQueue()
        XCTAssertFalse(model.queueStarted)
        XCTAssertEqual(model.activeCount, 0)
        XCTAssertEqual(model.queue[0].status, .pending)
        XCTAssertEqual(model.queue[1].status, .failed)
        XCTAssertEqual(model.queue[1].output, interrupted.output)
        XCTAssertNotNil(model.queue[1].error)
        XCTAssertEqual(try store.load().queue[1].status, .failed)
        model.retry(model.queue[1])
        XCTAssertFalse(model.queueStarted)
        XCTAssertEqual(try store.load().queue[1].status, .pending)
        model.remove(model.queue[0])
        XCTAssertEqual(try store.load().queue.count, 1)
    }

    @MainActor
    func testPendingCancellationAndRetryPreserveSettings() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("MediaForge-model-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = StateStore(url: folder.appendingPathComponent("state.json"))
        let model = ForgeModel(store: store)
        let settings = ConversionSettings(width: 320, removeAudio: true)
        let entry = QueueEntry(source: folder.appendingPathComponent("input.mp4"), profile: .mp4, settings: settings)
        model.queue.append(entry)
        model.cancel(entry)
        XCTAssertEqual(entry.status, .cancelled)
        XCTAssertEqual(model.history.first?.conversionSettings, settings)
        XCTAssertEqual(try store.load().history.first?.status, .cancelled)
        entry.startedAt = Date()
        entry.sizeDeviation = 0.2
        entry.progressDetail = "old progress"
        entry.cancelling = true
        model.retry(entry)
        XCTAssertNil(entry.startedAt)
        XCTAssertNil(entry.sizeDeviation)
        XCTAssertEqual(entry.progressDetail, "")
        XCTAssertFalse(entry.cancelling)
        XCTAssertEqual(entry.status, .pending)
        XCTAssertEqual(entry.conversionSettings, settings)
        XCTAssertFalse(model.queueStarted)
        XCTAssertNil(entry.error)
    }

    @MainActor
    func testCompletedJobCannotBeRetriedOrReplaced() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("MediaForge-model-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = ForgeModel(store: StateStore(url: folder.appendingPathComponent("state.json")))
        let entry = QueueEntry(source: folder.appendingPathComponent("input.mp4"), profile: .mp4, settings: .init())
        entry.status = .completed
        let output = folder.appendingPathComponent("result.mp4")
        entry.output = output
        model.queue.append(entry)
        model.retry(entry)
        XCTAssertEqual(entry.status, .completed)
        XCTAssertEqual(entry.output, output)
        model.cleanCompleted()
        XCTAssertTrue(model.queue.isEmpty)
    }

    @MainActor
    func testHistoryRepeatUsesSnapshotNotCurrentProfile() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("MediaForge-model-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = ForgeModel(store: StateStore(url: folder.appendingPathComponent("state.json")))
        let settings = ConversionSettings(sampleRate: 48000, channels: 1)
        let source = folder.appendingPathComponent("input.mov")
        let record = HistoryRecord(id: UUID(), source: source, output: nil, outputDirectory: folder, profile: .wav, conversionSettings: settings, status: .failed, finishedAt: Date(), message: "fixture")
        model.profile = .jpeg
        model.repeatConversion(record)
        XCTAssertEqual(model.queue.first?.profile, .wav)
        XCTAssertEqual(model.queue.first?.conversionSettings, settings)
        XCTAssertEqual(model.queue.first?.source, source)
        XCTAssertEqual(model.queue.first?.outputDirectory, folder)
    }

    @MainActor
    func testChangedHistoryLimitTrimsAndPersists() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("MediaForge-history-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = StateStore(url: folder.appendingPathComponent("state.json"))
        let model = ForgeModel(store: store)
        model.history = (0..<3).map { index in
            HistoryRecord(id: UUID(), source: folder.appendingPathComponent("source-" + String(index) + ".mp4"), output: nil, profile: .mp4, conversionSettings: .init(), status: .failed, finishedAt: Date(), message: nil)
        }
        let newest = model.history[0].id
        model.settings.historyLimit = 1
        model.persist()
        XCTAssertEqual(model.history.map { $0.id }, [newest])
        XCTAssertEqual(try store.load().settings.historyLimit, 1)
        XCTAssertEqual(try store.load().history.map { $0.id }, [newest])
    }

    @MainActor
    func testPresetDuplicateCreatesIndependentIdentifier() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("MediaForge-model-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = ForgeModel(store: StateStore(url: folder.appendingPathComponent("state.json")))
        let original = SavedPreset(name: "Профиль", profile: .flac, settings: .init(channels: 2))
        model.presets = [original]
        model.duplicatePreset(original)
        XCTAssertEqual(model.presets.count, 2)
        XCTAssertNotEqual(model.presets[0].id, model.presets[1].id)
        XCTAssertEqual(model.presets[0].settings, model.presets[1].settings)
    }

    @MainActor
    func testInvalidPresetEditLeavesOriginalAndStoredStateUntouched() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("MediaForge-preset-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = StateStore(url: folder.appendingPathComponent("state.json"))
        let preset = SavedPreset(name: "Original", profile: .mp4, settings: .init(width: 320))
        try store.save(PersistedState(presets: [preset]))
        let originalBytes = try Data(contentsOf: store.url)
        let model = ForgeModel(store: store)
        model.profile = .mov
        model.draft.width = "invalid"
        model.updatePreset(preset.id, name: "Changed")
        XCTAssertEqual(model.presets[0].name, "Original")
        XCTAssertEqual(model.presets[0].profile, .mp4)
        XCTAssertEqual(model.presets[0].settings, preset.settings)
        XCTAssertEqual(try Data(contentsOf: store.url), originalBytes)
        XCTAssertNotNil(model.alertMessage)
    }

    @MainActor
    func testShutdownCancelsImportWithoutPublishingNewQueueEntries() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("MediaForge-import-shutdown-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("source.wav")
        try Data("fixture".utf8).write(to: source)
        let store = StateStore(url: folder.appendingPathComponent("state.json"))
        let model = ForgeModel(store: store)
        model.profile = .flac
        model.importURLs([source])
        XCTAssertTrue(model.importing)
        await model.cancelAndWait()
        XCTAssertFalse(model.importing)
        XCTAssertTrue(model.isTerminating)
        XCTAssertTrue(model.queue.isEmpty)
        XCTAssertTrue(try store.load().queue.isEmpty)
    }

    @MainActor
    func testImportSnapshotsSettingsAndDuplicateImportDoesNotPause() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("MediaForge-import-model-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("source.wav")
        try Data("fixture".utf8).write(to: source)
        let store = StateStore(url: folder.appendingPathComponent("state.json"))
        let model = ForgeModel(store: store)
        model.profile = .flac
        model.draft.channels = "1"
        model.settings.outputDirectory = folder
        model.queueStarted = true
        model.importURLs([source, source])
        model.profile = .wav
        model.draft.channels = "2"
        await model.waitForImport()
        XCTAssertFalse(model.importing)
        XCTAssertFalse(model.queueStarted)
        XCTAssertNotNil(model.alertMessage)
        XCTAssertEqual(model.queue.count, 1)
        XCTAssertEqual(model.queue.first?.profile, .flac)
        XCTAssertEqual(model.queue.first?.conversionSettings.channels, 1)
        XCTAssertEqual(try store.load().queue.first?.outputDirectory, folder)
        model.alertMessage = nil
        model.queueStarted = true
        model.importURLs([source])
        await model.waitForImport()
        XCTAssertTrue(model.queueStarted)
        XCTAssertNil(model.alertMessage)
        XCTAssertEqual(model.queue.count, 1)
    }

    @MainActor
    func testRetryAndReplayAnnounceBatchPause() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("MediaForge-pause-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = ForgeModel(store: StateStore(url: folder.appendingPathComponent("state.json")))
        let entry = QueueEntry(source: folder.appendingPathComponent("input.mp4"), profile: .mp4, settings: .init())
        entry.status = .failed
        model.queue = [entry]
        model.queueStarted = true
        model.retry(entry)
        XCTAssertFalse(model.queueStarted)
        XCTAssertNotNil(model.alertMessage)
        XCTAssertEqual(entry.status, .pending)
        model.alertMessage = nil
        model.queueStarted = true
        let record = HistoryRecord(id: UUID(), source: entry.source, output: nil, profile: .mp4, conversionSettings: .init(), status: .failed, finishedAt: Date(), message: nil)
        model.repeatConversion(record)
        XCTAssertFalse(model.queueStarted)
        XCTAssertNotNil(model.alertMessage)
        XCTAssertEqual(model.queue.count, 2)
    }

    @MainActor
    func testTerminationBlocksNewImportsAndRestarts() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("MediaForge-model-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = ForgeModel(store: StateStore(url: folder.appendingPathComponent("state.json")))
        let entry = QueueEntry(source: folder.appendingPathComponent("failed.mp4"), profile: .mp4, settings: .init())
        entry.status = .failed
        model.queue = [entry]
        let record = HistoryRecord(id: UUID(), source: entry.source, output: nil, profile: .mp4, conversionSettings: .init(), status: .failed, finishedAt: Date(), message: nil)
        await model.cancelAndWait()
        let snapshot = try Data(contentsOf: folder.appendingPathComponent("state.json"))
        model.retry(entry)
        model.repeatConversion(record)
        XCTAssertEqual(entry.status, .failed)
        XCTAssertEqual(model.queue.count, 1)
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("state.json")), snapshot)
        let diagnostics = model.diagnostics
        await model.prepare()
        await model.refreshEngine()
        XCTAssertEqual(model.diagnostics, diagnostics)
        XCTAssertFalse(model.engineReady)
        model.importURLs([folder.appendingPathComponent("input.mp4")])
        model.startQueue()
        XCTAssertTrue(model.isTerminating)
        XCTAssertFalse(model.importing)
        XCTAssertEqual(model.activeCount, 0)
        XCTAssertFalse(model.queueStarted)
    }
}
