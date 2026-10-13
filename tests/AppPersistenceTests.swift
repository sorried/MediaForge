import Foundation
import XCTest
import MediaForgeCore

final class AppPersistenceTests: XCTestCase {
    func testBuiltInPresetsValidateAndRequireActualCodecs() throws {
        let catalog = BuiltInPreset.all
        XCTAssertEqual(catalog.count, 12)
        XCTAssertEqual(Set(catalog.map { $0.id }).count, catalog.count)
        let empty = FFmpegCapabilities(version: "test", encoders: [], muxers: [])
        for template in catalog {
            try template.preset.settings.validate(requiresEvenDimensions: !template.preset.profile.isImage)
            XCTAssertNotNil(template.unavailableReason(capabilities: nil))
            XCTAssertNotNil(template.unavailableReason(capabilities: empty))
        }
        let software = FFmpegCapabilities(version: "test", encoders: ["mpeg4", "aac"], muxers: ["mp4"])
        let universal = try XCTUnwrap(catalog.first { $0.id == "universal" })
        XCTAssertNotNil(universal.unavailableReason(capabilities: software))
        let compact = try XCTUnwrap(catalog.first { $0.id == "small" })
        XCTAssertNil(compact.unavailableReason(capabilities: software))
        let mp3 = try XCTUnwrap(catalog.first { $0.id == "mp3" })
        XCTAssertNotNil(mp3.unavailableReason(capabilities: software))
    }

    func testRemoteStoreURLCannotAccessLocalPath() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MediaForge-remote-state-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let local = root.appendingPathComponent("state.json")
        let original = Data("do not read or overwrite".utf8)
        try original.write(to: local)
        var components = URLComponents()
        components.scheme = "https"
        components.host = "example.invalid"
        components.path = local.path
        let store = StateStore(url: try XCTUnwrap(components.url))
        XCTAssertThrowsError(try store.load())
        XCTAssertThrowsError(try store.save(PersistedState()))
        XCTAssertThrowsError(try store.quarantine())
        XCTAssertEqual(try Data(contentsOf: local), original)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["state.json"])
    }

    func testSymlinkStateDirectoryDoesNotModifyTarget() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MediaForge-parent-link-" + UUID().uuidString)
        let target = root.appendingPathComponent("target")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: target.path)
        let original = Data("existing private state".utf8)
        let stateURL = target.appendingPathComponent("state.json")
        try original.write(to: stateURL)
        let alias = root.appendingPathComponent("alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: target)
        let store = StateStore(url: alias.appendingPathComponent("state.json"))
        XCTAssertThrowsError(try store.save(PersistedState()))
        XCTAssertEqual(try Data(contentsOf: stateURL), original)
        let permissions = try FileManager.default.attributesOfItem(atPath: target.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o755)
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: alias.path), target.path)
    }

    func testExistingStateDirectoryBecomesPrivate() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("MediaForge-private-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path)
        let store = StateStore(url: folder.appendingPathComponent("state.json"))
        try store.save(PersistedState())
        let permissions = try FileManager.default.attributesOfItem(atPath: folder.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o700)
        XCTAssertEqual(try store.load().queue.count, 0)
    }

    func testSettingsPresetsAndHistoryRoundTrip() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("MediaForge-state-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = StateStore(url: folder.appendingPathComponent("state.json"))
        var settings = ForgeSettings()
        settings.simultaneousJobs = 3
        settings.historyLimit = 100
        settings.recursiveImport = true
        settings.theme = .dark
        let source = folder.appendingPathComponent("исходник.mp4")
        let conversion = ConversionSettings(width: 320, sampleRate: 48000, channels: 1)
        let history = HistoryRecord(id: UUID(), source: source, output: nil, outputDirectory: folder, profile: .mp4, conversionSettings: conversion, status: .cancelled, finishedAt: Date(), message: "Отменено")
        var imageOptions = NativeImageOptions()
        imageOptions.quality = 0.75
        imageOptions.blackBackground = true
        let preset = SavedPreset(name: "Мой профиль", profile: .mp4, settings: conversion, imageOptions: imageOptions)
        try store.save(PersistedState(settings: settings, history: [history], presets: [preset]))
        let permissions = try FileManager.default.attributesOfItem(atPath: store.url.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)
        let directoryPermissions = try FileManager.default.attributesOfItem(atPath: folder.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(directoryPermissions?.intValue, 0o700)
        let loaded = try store.load()
        XCTAssertEqual(loaded.settings.simultaneousJobs, 3)
        XCTAssertEqual(loaded.settings.historyLimit, 100)
        XCTAssertEqual(loaded.settings.theme, .dark)
        XCTAssertTrue(loaded.settings.recursiveImport)
        XCTAssertEqual(loaded.history.first?.source, source)
        XCTAssertEqual(loaded.history.first?.outputDirectory, folder)
        XCTAssertEqual(loaded.history.first?.conversionSettings, conversion)
        XCTAssertEqual(loaded.presets.first?.name, preset.name)
        XCTAssertEqual(loaded.presets.first?.settings, conversion)
        XCTAssertEqual(loaded.presets.first?.imageOptions?.quality, 0.75)
        XCTAssertEqual(loaded.presets.first?.imageOptions?.blackBackground, true)
    }

    func testQueueSnapshotRoundTripAndInterruptedRecovery() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("MediaForge-queue-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = StateStore(url: folder.appendingPathComponent("state.json"))
        let output = folder.appendingPathComponent("published.mp4")
        let running = SavedQueueEntry(id: UUID(), source: folder.appendingPathComponent("input.gif"), profile: .mp4,
            conversionSettings: .init(width: 640, removeAudio: true), imageOptions: NativeImageOptions(),
            outputDirectory: folder, status: .running, output: output)
        let pending = SavedQueueEntry(id: UUID(), source: folder.appendingPathComponent("audio.wav"), profile: .flac, conversionSettings: .init(channels: 2))
        try store.save(PersistedState(queue: [running, pending]))
        let restored = try store.load().queue
        XCTAssertEqual(restored.count, 2)
        XCTAssertEqual(restored[0].id, running.id)
        XCTAssertEqual(restored[0].outputDirectory, folder)
        XCTAssertEqual(restored[0].conversionSettings, running.conversionSettings)
        let recovered = restored[0].recoveringInterruptedWork()
        XCTAssertEqual(recovered.status, .failed)
        XCTAssertEqual(recovered.output, output)
        XCTAssertNotNil(recovered.error)
        XCTAssertEqual(restored[1].recoveringInterruptedWork().status, .pending)
        var probing = running
        probing.status = .probing
        XCTAssertEqual(probing.recoveringInterruptedWork().status, .failed)
        var completed = running
        completed.status = .completed
        XCTAssertEqual(completed.recoveringInterruptedWork().status, .completed)
        XCTAssertEqual(completed.recoveringInterruptedWork().output, output)
    }

    func testQueueRejectsDuplicateIDsAndExcessiveCount() throws {
        let entry = SavedQueueEntry(id: UUID(), source: URL(fileURLWithPath: "/input.mp4"), profile: .mp4, conversionSettings: .init())
        let duplicate = try JSONEncoder().encode(PersistedState(queue: [entry, entry]))
        XCTAssertThrowsError(try JSONDecoder().decode(PersistedState.self, from: duplicate))
        let oversized = PersistedState(queue: (0...10000).map { _ in
            SavedQueueEntry(id: UUID(), source: entry.source, profile: .mp4, conversionSettings: .init())
        })
        XCTAssertThrowsError(try oversized.validateQueue())
        XCTAssertThrowsError(try JSONDecoder().decode(PersistedState.self, from: JSONEncoder().encode(oversized)))
    }

    func testPersistedQueueRejectsNonlocalPaths() throws {
        let remote = try XCTUnwrap(URL(string: "https://example.invalid/media.mp4"))
        let source = URL(fileURLWithPath: "/input.mp4")
        let valid = SavedQueueEntry(id: UUID(), source: source, profile: .mp4, conversionSettings: .init())
        for field in 0..<4 {
            var entry = valid
            var settings = ForgeSettings()
            switch field {
            case 0: entry.source = remote
            case 1: entry.outputDirectory = remote
            case 2: entry.output = remote
            default: settings.outputDirectory = remote
            }
            let state = PersistedState(settings: settings, queue: [entry])
            XCTAssertThrowsError(try state.validateQueue())
            XCTAssertThrowsError(try JSONDecoder().decode(PersistedState.self, from: JSONEncoder().encode(state)))
        }
        XCTAssertNoThrow(try PersistedState(queue: [valid]).validateQueue())
    }

    func testHistoryRejectsNonlocalPaths() throws {
        let remote = try XCTUnwrap(URL(string: "https://example.invalid/media.mp4"))
        let valid = HistoryRecord(id: UUID(), source: URL(fileURLWithPath: "/input.mp4"), output: nil, profile: .mp4, conversionSettings: .init(), status: .failed, finishedAt: Date(), message: "failure")
        for field in 0..<3 {
            var record = valid
            switch field {
            case 0: record.source = remote
            case 1: record.outputDirectory = remote
            default: record.output = remote
            }
            let state = PersistedState(history: [record])
            XCTAssertThrowsError(try state.validateQueue())
            XCTAssertThrowsError(try JSONDecoder().decode(PersistedState.self, from: JSONEncoder().encode(state)))
        }
        XCTAssertNoThrow(try PersistedState(history: [valid]).validateQueue())
    }

    func testDuplicateHistoryAndPresetIdentitiesAreRejected() throws {
        let source = URL(fileURLWithPath: "/input.mp4")
        let history = HistoryRecord(id: UUID(), source: source, output: nil, profile: .mp4, conversionSettings: .init(), status: .failed, finishedAt: Date(), message: "failure")
        let preset = SavedPreset(name: "Custom", profile: .mp4, settings: .init())
        for state in [PersistedState(history: [history, history]), PersistedState(presets: [preset, preset])] {
            XCTAssertThrowsError(try state.validateQueue())
            XCTAssertThrowsError(try JSONDecoder().decode(PersistedState.self, from: JSONEncoder().encode(state)))
        }
        var distinct = preset
        distinct.id = UUID()
        XCTAssertNoThrow(try PersistedState(presets: [preset, distinct]).validateQueue())
    }

    func testMissingKeysUseSafeDefaults() throws {
        let loaded = try JSONDecoder().decode(PersistedState.self, from: Data("{\"settings\":{}}".utf8))
        XCTAssertEqual(loaded.settings.simultaneousJobs, 1)
        XCTAssertEqual(loaded.settings.theme, .system)
        XCTAssertEqual(loaded.history.count, 0)
        XCTAssertEqual(loaded.presets.count, 0)
        XCTAssertTrue(loaded.queue.isEmpty)
        let legacy = try JSONDecoder().decode(ConversionSettings.self, from: Data("{\"width\":320}".utf8))
        XCTAssertEqual(legacy.width, 320)
        XCTAssertEqual(legacy.videoEncoderPreference, .automatic)
        XCTAssertFalse(legacy.removeAudio)
    }

    func testQuarantineRejectsDirectoryAndSymlinkWithoutCopies() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MediaForge-quarantine-types-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("target.json")
        let original = Data("preserved".utf8)
        try original.write(to: target)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: target.path)
        let alias = root.appendingPathComponent("alias.json")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: target)
        let directory = root.appendingPathComponent("state.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        for url in [alias, directory] {
            XCTAssertThrowsError(try StateStore(url: url).quarantine())
        }
        XCTAssertEqual(try Data(contentsOf: target), original)
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: target.path)[.posixPermissions] as? NSNumber, NSNumber(value: 0o644))
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: root.path)), ["target.json", "alias.json", "state.json"])
    }

    func testCorruptStateCanBeQuarantinedWithoutLosingBytes() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("MediaForge-state-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = StateStore(url: folder.appendingPathComponent("state.json"))
        let corrupt = Data("invalid JSON with recoverable history".utf8)
        try corrupt.write(to: store.url)
        XCTAssertThrowsError(try store.load())
        let backup = try store.quarantine()
        let permissions = try FileManager.default.attributesOfItem(atPath: backup.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)
        XCTAssertEqual(try Data(contentsOf: backup), corrupt)
        XCTAssertEqual(try Data(contentsOf: store.url), corrupt)
        try store.save(PersistedState())
        XCTAssertEqual(try Data(contentsOf: backup), corrupt)
        XCTAssertEqual(try store.load().schemaVersion, 1)
    }

    func testOversizedAndSymlinkStateAreRejectedWithoutModification() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("MediaForge-state-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("source.json")
        try Data("{}".utf8).write(to: source)
        let alias = folder.appendingPathComponent("alias.json")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: source)
        XCTAssertThrowsError(try StateStore(url: alias).load())
        XCTAssertEqual(try Data(contentsOf: source), Data("{}".utf8))
        let oversized = folder.appendingPathComponent("oversized.json")
        XCTAssertTrue(FileManager.default.createFile(atPath: oversized.path, contents: nil))
        let handle = try FileHandle(forWritingTo: oversized)
        try handle.truncate(atOffset: 32 * 1024 * 1024 + 1)
        try handle.close()
        XCTAssertThrowsError(try StateStore(url: oversized).load())
        let size = try FileManager.default.attributesOfItem(atPath: oversized.path)[.size] as? NSNumber
        XCTAssertEqual(size?.int64Value, 32 * 1024 * 1024 + 1)
    }

    func testImageOptionsRejectInvalidPersistedQuality() throws {
        let defaults = try JSONDecoder().decode(NativeImageOptions.self, from: Data("{}".utf8))
        XCTAssertEqual(defaults.quality, 0.9)
        XCTAssertFalse(defaults.blackBackground)
        for quality in [-1.0, 0, 0.09, 1.01, 1e100] {
            let bytes = Data(("{\"quality\":" + String(quality) + "}").utf8)
            XCTAssertThrowsError(try JSONDecoder().decode(NativeImageOptions.self, from: bytes))
        }
        for quality in [0.1, 0.9, 1.0] {
            let bytes = Data(("{\"quality\":" + String(quality) + "}").utf8)
            XCTAssertEqual(try JSONDecoder().decode(NativeImageOptions.self, from: bytes).quality, quality)
        }
    }

    func testFutureSchemaFailsRatherThanPretendingEmptySuccess() {
        XCTAssertThrowsError(try JSONDecoder().decode(PersistedState.self, from: Data("{\"schemaVersion\":999}".utf8)))
    }

    func testDraftRejectsMalformedAndConflictingValues() throws {
        var draft = SettingsDraft()
        draft.frameRate = "not a number"
        XCTAssertThrowsError(try draft.settings(for: .mp4))
        draft.frameRate = "29,97"
        XCTAssertEqual(try draft.settings(for: .mp4).frameRate, 29.97)
        draft.targetSize = "10"
        draft.videoBitrate = "500"
        XCTAssertThrowsError(try draft.settings(for: .mp4))
        draft.removeAudio = true
        draft.audioBitrate = "192"
        let audio = try draft.settings(for: .mp3)
        XCTAssertFalse(audio.removeAudio)
        XCTAssertEqual(audio.audioBitrateKbps, 192)
        XCTAssertNil(audio.targetSizeMB)
        draft.width = "7"
        draft.height = "5"
        let image = try draft.settings(for: .png)
        XCTAssertEqual(image.width, 7)
        XCTAssertEqual(image.height, 5)
        XCTAssertThrowsError(try draft.settings(for: .mp4))
    }
}

@main
struct AppPersistenceTestRunner {
    static func main() {
        #if os(macOS)
        let suite = XCTestSuite(forTestCaseClass: AppPersistenceTests.self)
        suite.run()
        guard let run = suite.testRun, run.executionCount == 17, run.totalFailureCount == 0 else { exit(1) }
        #else
        XCTMain([testCase([
            ("testBuiltInPresetsValidateAndRequireActualCodecs", AppPersistenceTests.testBuiltInPresetsValidateAndRequireActualCodecs),
            ("testRemoteStoreURLCannotAccessLocalPath", AppPersistenceTests.testRemoteStoreURLCannotAccessLocalPath),
            ("testSymlinkStateDirectoryDoesNotModifyTarget", AppPersistenceTests.testSymlinkStateDirectoryDoesNotModifyTarget),
            ("testExistingStateDirectoryBecomesPrivate", AppPersistenceTests.testExistingStateDirectoryBecomesPrivate),
            ("testSettingsPresetsAndHistoryRoundTrip", AppPersistenceTests.testSettingsPresetsAndHistoryRoundTrip),
            ("testQueueSnapshotRoundTripAndInterruptedRecovery", AppPersistenceTests.testQueueSnapshotRoundTripAndInterruptedRecovery),
            ("testQueueRejectsDuplicateIDsAndExcessiveCount", AppPersistenceTests.testQueueRejectsDuplicateIDsAndExcessiveCount),
            ("testPersistedQueueRejectsNonlocalPaths", AppPersistenceTests.testPersistedQueueRejectsNonlocalPaths),
            ("testHistoryRejectsNonlocalPaths", AppPersistenceTests.testHistoryRejectsNonlocalPaths),
            ("testDuplicateHistoryAndPresetIdentitiesAreRejected", AppPersistenceTests.testDuplicateHistoryAndPresetIdentitiesAreRejected),
            ("testMissingKeysUseSafeDefaults", AppPersistenceTests.testMissingKeysUseSafeDefaults),
            ("testQuarantineRejectsDirectoryAndSymlinkWithoutCopies", AppPersistenceTests.testQuarantineRejectsDirectoryAndSymlinkWithoutCopies),
            ("testCorruptStateCanBeQuarantinedWithoutLosingBytes", AppPersistenceTests.testCorruptStateCanBeQuarantinedWithoutLosingBytes),
            ("testOversizedAndSymlinkStateAreRejectedWithoutModification", AppPersistenceTests.testOversizedAndSymlinkStateAreRejectedWithoutModification),
            ("testImageOptionsRejectInvalidPersistedQuality", AppPersistenceTests.testImageOptionsRejectInvalidPersistedQuality),
            ("testFutureSchemaFailsRatherThanPretendingEmptySuccess", AppPersistenceTests.testFutureSchemaFailsRatherThanPretendingEmptySuccess),
            ("testDraftRejectsMalformedAndConflictingValues", AppPersistenceTests.testDraftRejectsMalformedAndConflictingValues)
        ])])
        #endif
    }
}
