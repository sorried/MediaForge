import Foundation
#if canImport(SwiftUI)
import SwiftUI
#endif
import MediaForgeCore

func L(_ key: String) -> String {
    NSLocalizedString(key, tableName: "Localizable", bundle: .main, comment: "")
}

enum AppTheme: String, Codable, CaseIterable {
    case system, light, dark
    var title: String {
        switch self {
        case .system: L("Системная")
        case .light: L("Светлая")
        case .dark: L("Тёмная")
        }
    }
    #if canImport(SwiftUI)
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
    #endif
}

struct ForgeSettings: Codable {
    var outputDirectory: URL = (FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Movies"))
        .appendingPathComponent("Media Forge", isDirectory: true)
    var recursiveImport = false
    var simultaneousJobs = 1
    var historyLimit = 500
    var theme = AppTheme.system

    private enum CodingKeys: String, CodingKey { case outputDirectory, recursiveImport, simultaneousJobs, historyLimit, theme }
    init() {}
    init(from decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        outputDirectory = try fields.decodeIfPresent(URL.self, forKey: .outputDirectory) ?? outputDirectory
        recursiveImport = try fields.decodeIfPresent(Bool.self, forKey: .recursiveImport) ?? false
        simultaneousJobs = try fields.decodeIfPresent(Int.self, forKey: .simultaneousJobs) ?? 1
        historyLimit = min(10000, max(0, try fields.decodeIfPresent(Int.self, forKey: .historyLimit) ?? 500))
        theme = try fields.decodeIfPresent(AppTheme.self, forKey: .theme) ?? .system
    }
}

enum QueueStatus: String, Codable {
    case pending, probing, running, completed, failed, cancelled
    var title: String {
        switch self {
        case .pending: L("В очереди")
        case .probing: L("Анализ файла")
        case .running: L("Конвертация")
        case .completed: L("Готово")
        case .failed: L("Ошибка")
        case .cancelled: L("Отменено")
        }
    }
    var isTerminal: Bool { self == .completed || self == .failed || self == .cancelled }
}

struct NativeImageOptions: Codable, Sendable {
    var quality = 0.9
    var blackBackground = false

    private enum CodingKeys: String, CodingKey { case quality, blackBackground }
    init() {}
    init(from decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        quality = try fields.decodeIfPresent(Double.self, forKey: .quality) ?? 0.9
        blackBackground = try fields.decodeIfPresent(Bool.self, forKey: .blackBackground) ?? false
        guard quality.isFinite, (0.1...1).contains(quality) else { throw CocoaError(.coderReadCorrupt) }
    }
}

struct HistoryRecord: Codable, Identifiable {
    var id: UUID
    var source: URL
    var output: URL?
    var outputDirectory: URL? = nil
    var profile: OutputProfile
    var conversionSettings: ConversionSettings
    var imageOptions: NativeImageOptions? = nil
    var status: QueueStatus
    var finishedAt: Date
    var message: String?
}

struct SavedQueueEntry: Codable, Identifiable {
    var id: UUID
    var source: URL
    var profile: OutputProfile
    var conversionSettings: ConversionSettings
    var imageOptions: NativeImageOptions? = nil
    var outputDirectory: URL? = nil
    var status: QueueStatus = .pending
    var error: String? = nil
    var output: URL? = nil

    func recoveringInterruptedWork() -> SavedQueueEntry {
        guard status == .running || status == .probing else { return self }
        var recovered = self
        recovered.status = .failed
        recovered.error = L("Задача была прервана при завершении приложения. Проверьте папку результатов и нажмите «Повторить» вручную. Существующие файлы не заменяются.")
        return recovered
    }
}

struct PersistedState: Codable {
    var schemaVersion = 1
    var settings = ForgeSettings()
    var history: [HistoryRecord] = []
    var presets: [SavedPreset] = []
    var queue: [SavedQueueEntry] = []

    init(settings: ForgeSettings = .init(), history: [HistoryRecord] = [], presets: [SavedPreset] = [], queue: [SavedQueueEntry] = []) {
        self.settings = settings; self.history = history; self.presets = presets; self.queue = queue
    }
    private enum CodingKeys: String, CodingKey { case schemaVersion, settings, history, presets, queue }
    init(from decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try fields.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        guard schemaVersion == 1 else { throw CocoaError(.coderReadCorrupt) }
        settings = try fields.decodeIfPresent(ForgeSettings.self, forKey: .settings) ?? ForgeSettings()
        history = try fields.decodeIfPresent([HistoryRecord].self, forKey: .history) ?? []
        presets = try fields.decodeIfPresent([SavedPreset].self, forKey: .presets) ?? []
        queue = try fields.decodeIfPresent([SavedQueueEntry].self, forKey: .queue) ?? []
        try validateQueue()
    }
}

extension PersistedState {
    func validateQueue() throws {
        guard queue.count <= 10000, Set(queue.map { $0.id }).count == queue.count,
              settings.outputDirectory.isFileURL,
              Set(history.map { $0.id }).count == history.count,
              Set(presets.map { $0.id }).count == presets.count else { throw CocoaError(.coderReadCorrupt) }
        for record in history {
            guard record.source.isFileURL, record.outputDirectory?.isFileURL != false, record.output?.isFileURL != false else {
                throw CocoaError(.coderReadCorrupt)
            }
        }
        for entry in queue {
            guard entry.source.isFileURL, entry.outputDirectory?.isFileURL != false, entry.output?.isFileURL != false else {
                throw CocoaError(.coderReadCorrupt)
            }
        }
    }
}

struct SavedPreset: Codable, Identifiable {
    var id = UUID()
    var name: String
    var profile: OutputProfile
    var settings: ConversionSettings
    var imageOptions: NativeImageOptions? = nil
}

struct StateStore {
    let url: URL
    init(url: URL? = nil) {
        self.url = url ?? (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support"))
            .appendingPathComponent("MediaForge/state.json")
    }
    func load() throws -> PersistedState {
        guard url.isFileURL else { throw CocoaError(.fileReadUnsupportedScheme) }
        guard FileManager.default.fileExists(atPath: url.path) else { return PersistedState() }
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              (attributes[.size] as? NSNumber)?.int64Value ?? 0 <= 32 * 1024 * 1024 else {
            throw CocoaError(.fileReadTooLarge)
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let bytes = try handle.read(upToCount: 32 * 1024 * 1024 + 1) ?? Data()
        guard bytes.count <= 32 * 1024 * 1024 else { throw CocoaError(.fileReadTooLarge) }
        return try JSONDecoder().decode(PersistedState.self, from: bytes)
    }
    func quarantine() throws -> URL {
        guard url.isFileURL else { throw CocoaError(.fileReadUnsupportedScheme) }
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular else { throw CocoaError(.fileReadNoPermission) }
        let backup = url.deletingLastPathComponent().appendingPathComponent("state-unreadable-" + UUID().uuidString + ".json")
        try FileManager.default.copyItem(at: url, to: backup)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backup.path)
        return backup
    }
    func save(_ state: PersistedState) throws {
        guard url.isFileURL else { throw CocoaError(.fileWriteUnsupportedScheme) }
        try state.validateQueue()
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let attributes = try FileManager.default.attributesOfItem(atPath: directory.path)
        guard attributes[.type] as? FileAttributeType == .typeDirectory else { throw CocoaError(.fileWriteNoPermission) }
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let bytes = try encoder.encode(state)
        guard bytes.count <= 32 * 1024 * 1024 else { throw CocoaError(.fileWriteOutOfSpace) }
        try bytes.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
