import Foundation
import XCTest

final class ImportScannerTests: XCTestCase {
    func testNonrecursiveAndRecursiveFolderSelection() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("MediaForge-import-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("nested"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let top = folder.appendingPathComponent("верхний файл.mp4")
        let child = folder.appendingPathComponent("nested/audio.wav")
        try Data("fixture".utf8).write(to: top)
        try Data("fixture".utf8).write(to: child)
        try Data("hidden".utf8).write(to: folder.appendingPathComponent(".hidden"))
        XCTAssertEqual(Set(try scanImports([folder], recursive: false)), [top])
        XCTAssertEqual(Set(try scanImports([folder], recursive: true)), [top, child])
    }

    func testSymlinksAreNotFollowed() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("MediaForge-import-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("input.mp4")
        let alias = folder.appendingPathComponent("alias.mp4")
        try Data("fixture".utf8).write(to: source)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: source)
        XCTAssertEqual(try scanImports([alias], recursive: true), [])
        XCTAssertEqual(Set(try scanImports([folder], recursive: true)), [source])
    }

    func testDirectorySymlinksAndCyclesAreNotTraversed() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MediaForge-links-" + UUID().uuidString)
        let selected = root.appendingPathComponent("selected")
        let outside = root.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: selected, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = selected.appendingPathComponent("source.mp4")
        try Data("inside".utf8).write(to: source)
        try Data("outside".utf8).write(to: outside.appendingPathComponent("private.mp4"))
        let alias = selected.appendingPathComponent("external-directory")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: outside)
        try FileManager.default.createSymbolicLink(at: selected.appendingPathComponent("cycle"), withDestinationURL: selected)
        XCTAssertEqual(try scanImports([alias], recursive: true), [])
        XCTAssertEqual(Set(try scanImports([selected], recursive: true, limit: 1)), [source])
    }

    func testMissingInputFailsAndRemoteInputIsIgnored() throws {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        XCTAssertThrowsError(try scanImports([missing], recursive: false))
        let remote = try XCTUnwrap(URL(string: "https://example.invalid/media.mp4"))
        XCTAssertEqual(try scanImports([remote], recursive: true), [])
    }

    func testScanLimitDeduplicatesAndExcludesExistingFiles() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("MediaForge-import-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let first = folder.appendingPathComponent("first.mp4")
        let second = folder.appendingPathComponent("second.mp4")
        try Data("fixture".utf8).write(to: first)
        try Data("fixture".utf8).write(to: second)
        XCTAssertEqual(try scanImports([first, first], recursive: false, limit: 1), [first])
        XCTAssertEqual(try scanImports([folder], recursive: true, limit: 1, excluding: [first]), [second])
        XCTAssertThrowsError(try scanImports([folder], recursive: true, limit: 1))
        XCTAssertEqual(try scanImports([first], recursive: false, limit: 0, excluding: [first]), [])
        XCTAssertThrowsError(try scanImports([first], recursive: false, limit: 0))
    }

    func testImageRecognitionIsCaseInsensitive() {
        XCTAssertTrue(isImageSource(URL(fileURLWithPath: "/fixture/IMAGE.HEIC")))
        XCTAssertTrue(isImageSource(URL(fileURLWithPath: "/fixture/animation.gif")))
        XCTAssertFalse(isImageSource(URL(fileURLWithPath: "/fixture/video.mp4")))
    }
}

@main
struct ImportScannerTestRunner {
    static func main() {
        #if os(macOS)
        let suite = XCTestSuite(forTestCaseClass: ImportScannerTests.self)
        suite.run()
        guard let run = suite.testRun, run.executionCount == 6, run.totalFailureCount == 0 else { exit(1) }
        #else
        XCTMain([testCase([
            ("testNonrecursiveAndRecursiveFolderSelection", ImportScannerTests.testNonrecursiveAndRecursiveFolderSelection),
            ("testSymlinksAreNotFollowed", ImportScannerTests.testSymlinksAreNotFollowed),
            ("testDirectorySymlinksAndCyclesAreNotTraversed", ImportScannerTests.testDirectorySymlinksAndCyclesAreNotTraversed),
            ("testMissingInputFailsAndRemoteInputIsIgnored", ImportScannerTests.testMissingInputFailsAndRemoteInputIsIgnored),
            ("testScanLimitDeduplicatesAndExcludesExistingFiles", ImportScannerTests.testScanLimitDeduplicatesAndExcludesExistingFiles),
            ("testImageRecognitionIsCaseInsensitive", ImportScannerTests.testImageRecognitionIsCaseInsensitive)
        ])])
        #endif
    }
}
