import Foundation

public actor HistoryStore {
    private struct Document: Codable {
        var version: Int
        var entries: [HistoryEntry]
    }
    public let url: URL
    public let limit: Int
    public init(url: URL, limit: Int = 200) throws {
        guard url.isFileURL else { throw MediaForgeError.fileOperation("History storage must use a local file URL.") }
        guard (1...10000).contains(limit) else { throw MediaForgeError.invalidSettings("History limit must be one to 10000.") }
        self.url = url
        self.limit = limit
    }
    public func load() throws -> [HistoryEntry] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              (attributes[.size] as? NSNumber)?.intValue ?? 0 <= 32 * 1024 * 1024 else {
            throw MediaForgeError.fileOperation("History must be a regular file no larger than 32 MiB.")
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let bytes = try handle.read(upToCount: 32 * 1024 * 1024 + 1) ?? Data()
        guard bytes.count <= 32 * 1024 * 1024 else {
            throw MediaForgeError.fileOperation("History file exceeds the 32 MiB limit.")
        }
        let document = try JSONDecoder().decode(Document.self, from: bytes)
        guard document.version == 1 else { throw MediaForgeError.fileOperation("History was saved by an unsupported schema version.") }
        return Array(document.entries.suffix(limit))
    }
    public func append(_ entry: HistoryEntry) throws {
        var entries = try load()
        entries.removeAll { $0.id == entry.id }
        entries.append(entry)
        try save(entries)
    }
    public func save(_ entries: [HistoryEntry]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let bytes = try encoder.encode(Document(version: 1, entries: Array(entries.suffix(limit))))
        guard bytes.count <= 32 * 1024 * 1024 else { throw MediaForgeError.fileOperation("History exceeds the 32 MiB limit.") }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try bytes.write(to: url, options: .atomic)
    }
}
