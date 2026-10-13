import Foundation

@main
struct ImportScannerChecks {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("mediaforge-import-tests-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("nested"), withIntermediateDirectories: true)
        defer {
            do { try FileManager.default.removeItem(at: root) }
            catch { print("Cleanup failed: \(error)") }
        }
        let visible = root.appendingPathComponent("visible.mp4")
        let hidden = root.appendingPathComponent(".hidden.mp4")
        let nested = root.appendingPathComponent("nested/audio.wav")
        for file in [visible, hidden, nested] { try Data([1]).write(to: file) }
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("alias.mp4"), withDestinationURL: visible)
        let flat = try scanImports([root], recursive: false)
        guard Set(flat) == Set([visible]) else { throw CheckFailure.failed("Nonrecursive import included hidden, nested or symbolic files") }
        let recursive = try scanImports([root], recursive: true)
        guard Set(recursive) == Set([visible, nested]) else { throw CheckFailure.failed("Recursive import missed ordinary files or included hidden/symbolic files") }
        let direct = try scanImports([visible], recursive: false)
        guard direct == [visible] else { throw CheckFailure.failed("Direct file import failed") }
        guard let remoteURL = URL(string: "https://example.com/movie.mp4") else { throw CheckFailure.failed("Invalid test URL") }
        let remote = try scanImports([remoteURL], recursive: true)
        guard remote.isEmpty else { throw CheckFailure.failed("Remote URL was accepted") }
        guard isImageSource(root.appendingPathComponent("animated.GIF")) else { throw CheckFailure.failed("Image loss detection must be case insensitive") }
        print("PASS: shallow folders, recursive folders, hidden files, symlinks, direct files, remote URLs and image classification")
    }
}

enum CheckFailure: Error { case failed(String) }
