import Foundation

func isImageSource(_ url: URL) -> Bool {
    ["png", "jpg", "jpeg", "gif", "webp", "tif", "tiff", "heic", "heif", "avif", "bmp", "apng"].contains(url.pathExtension.lowercased())
}

func scanImports(_ urls: [URL], recursive: Bool, limit: Int = 10000, excluding: Set<URL> = []) throws -> [URL] {
    guard limit >= 0 else { throw NSError(domain: "MediaForge.Import", code: 2, userInfo: [NSLocalizedDescriptionKey: "Import limit must be nonnegative."]) }
    var candidates: [URL] = []
    var seen = Set(excluding.map { $0.standardizedFileURL })
    func append(_ url: URL) throws {
        let normalized = url.standardizedFileURL
        guard seen.insert(normalized).inserted else { return }
        guard candidates.count < limit else {
            throw NSError(domain: "MediaForge.Import", code: 1, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("Очередь ограничена 10000 задачами. Удалите ненужные задачи перед импортом.", comment: "")])
        }
        candidates.append(normalized)
    }
    for url in urls where url.isFileURL {
        try Task.checkCancellation()
        let flags = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey])
        guard flags.isSymbolicLink != true else { continue }
        if flags.isDirectory == true {
            let options: FileManager.DirectoryEnumerationOptions = recursive
                ? [.skipsHiddenFiles, .skipsPackageDescendants]
                : [.skipsHiddenFiles, .skipsPackageDescendants, .skipsSubdirectoryDescendants]
            var enumerationError: Error?
            guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey], options: options, errorHandler: { _, error in enumerationError = error; return false }) else {
                throw CocoaError(.fileReadNoPermission)
            }
            for case let file as URL in enumerator {
                try Task.checkCancellation()
                let flags = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                if flags.isRegularFile == true && flags.isSymbolicLink != true { try append(file) }
            }
            if let enumerationError { throw enumerationError }
        } else if flags.isRegularFile == true { try append(url) }
    }
    return candidates
}
