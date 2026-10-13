import XCTest
import Foundation
@testable import MediaForgeCore

#if canImport(ImageIO) && canImport(CoreGraphics) && canImport(Darwin)
import ImageIO
import CoreGraphics

final class ImageConverterTests: XCTestCase {
    func testCancelledImageConversionDoesNotReadMissingSourceOrCreateOutput() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("missing.png")
        let output = folder.appendingPathComponent("output.png")
        let request = ImageConversionRequest(inputURL: source, outputURL: output, format: .png)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try ImageConverter().convert(request)
        }
        do {
            _ = try await task.value
            XCTFail("Expected image cancellation")
        } catch is CancellationError {
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), [])
        }
    }

    func testJPEGRequiresExplicitFlattenColor() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let input = folder.appendingPathComponent("alpha.png")
        try fixture(input)
        let converter = ImageConverter()
        let output = folder.appendingPathComponent("flattened.jpg")
        var request = ImageConversionRequest(inputURL: input, outputURL: output, format: .jpeg)
        let plan = try converter.preflight(request)
        XCTAssertTrue(plan.requiredConsents.contains(.flattenTransparency))
        XCTAssertThrowsError(try converter.convert(request)) { error in
            guard case ImageConversionError.flattenColorRequired = error else { return XCTFail("Wrong error: \(error)") }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        request.flattenColor = .white
        let converted = try converter.convert(request)
        XCTAssertFalse(converted.inspection.hasAlpha)
        XCTAssertEqual(converted.inspection.width, 80)
        XCTAssertEqual(converted.inspection.height, 40)
    }

    func testAspectFitPreservesPNGTransparencyAndOriginal() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let input = folder.appendingPathComponent("source.png")
        try fixture(input)
        let original = try Data(contentsOf: input)
        let output = folder.appendingPathComponent("small.png")
        let converted = try ImageConverter().convert(.init(inputURL: input, outputURL: output, format: .png, maxWidth: 30, maxHeight: 10))
        XCTAssertEqual(converted.inspection.width, 20)
        XCTAssertEqual(converted.inspection.height, 10)
        XCTAssertTrue(converted.inspection.hasAlpha)
        XCTAssertEqual(try Data(contentsOf: input), original)
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(output as CFURL, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        var pixel = [UInt8](repeating: 0, count: 4)
        try pixel.withUnsafeMutableBytes { bytes in
            let context = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        XCTAssertGreaterThan(pixel[3], 100)
        XCTAssertLessThan(pixel[3], 155)
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: folder.path).contains { $0.hasPrefix(".mediaforge-image-") })
    }

    func testCorruptInputExistingDestinationAndOriginalAreProtected() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let corrupt = folder.appendingPathComponent("corrupt.png")
        try Data("not an image".utf8).write(to: corrupt)
        let output = folder.appendingPathComponent("output.png")
        XCTAssertThrowsError(try ImageConverter().convert(.init(inputURL: corrupt, outputURL: output, format: .png)))
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        let input = folder.appendingPathComponent("valid.png")
        try fixture(input)
        let existing = Data("existing output".utf8)
        try existing.write(to: output)
        XCTAssertThrowsError(try ImageConverter().convert(.init(inputURL: input, outputURL: output, format: .png))) { error in
            guard case ImageConversionError.destinationExists = error else { return XCTFail("Wrong error: \(error)") }
        }
        XCTAssertEqual(try Data(contentsOf: output), existing)
        let original = try Data(contentsOf: input)
        XCTAssertThrowsError(try ImageConverter().convert(.init(inputURL: input, outputURL: input, format: .png)))
        XCTAssertEqual(try Data(contentsOf: input), original)
    }

    func testMultipleFramesRequireConsentAndExportFirstFrameOnly() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let input = folder.appendingPathComponent("pages.tiff")
        try fixture(input, typeIdentifier: "public.tiff", frameCount: 2)
        let output = folder.appendingPathComponent("first.png")
        var request = ImageConversionRequest(inputURL: input, outputURL: output, format: .png)
        let converter = ImageConverter()
        XCTAssertEqual(try converter.inspect(input).frameCount, 2)
        XCTAssertTrue(try converter.preflight(request).requiredConsents.contains(.dropAnimation))
        XCTAssertThrowsError(try converter.convert(request)) { error in
            guard case ImageConversionError.animationConsentRequired = error else { return XCTFail("Wrong error: \(error)") }
        }
        request.allowDropAnimation = true
        XCTAssertEqual(try converter.convert(request).inspection.frameCount, 1)
    }

    func testInvalidBoundsAndQualityAreRejectedAndNeverUpscale() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let input = folder.appendingPathComponent("source.png")
        try fixture(input)
        let output = folder.appendingPathComponent("output.png")
        let converter = ImageConverter()
        for quality in [Double.nan, .infinity, -0.1, 1.1] {
            XCTAssertThrowsError(try converter.preflight(.init(inputURL: input, outputURL: output, format: .png, quality: quality)))
        }
        XCTAssertThrowsError(try converter.preflight(.init(inputURL: input, outputURL: output, format: .png, maxWidth: 0)))
        let plan = try converter.preflight(.init(inputURL: input, outputURL: output, format: .png, maxWidth: 800, maxHeight: 800))
        XCTAssertEqual(plan.outputWidth, 80)
        XCTAssertEqual(plan.outputHeight, 40)
        let available = CGImageDestinationCopyTypeIdentifiers() as! [String]
        XCTAssertEqual(converter.supportedFormats, ImageOutputFormat.allCases.filter { available.contains($0.typeIdentifier) })
    }

    func testOrientationIsAppliedBeforeAspectFit() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let input = folder.appendingPathComponent("rotated.tiff")
        try fixture(input, typeIdentifier: "public.tiff", orientation: 6)
        let converter = ImageConverter()
        XCTAssertEqual(try converter.inspect(input).orientation, 6)
        let output = folder.appendingPathComponent("upright.png")
        let request = ImageConversionRequest(inputURL: input, outputURL: output, format: .png, maxWidth: 10, maxHeight: 30)
        let plan = try converter.preflight(request)
        XCTAssertEqual(plan.outputWidth, 10)
        XCTAssertEqual(plan.outputHeight, 20)
        let converted = try converter.convert(request)
        XCTAssertEqual(converted.inspection.width, 10)
        XCTAssertEqual(converted.inspection.height, 20)
        XCTAssertEqual(converted.inspection.orientation, 1)
    }

    private func makeFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ImageConverterTests-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        return folder
    }

    private func fixture(_ url: URL, typeIdentifier: String = "public.png", frameCount: Int = 1, orientation: Int = 1) throws {
        let supported = CGImageDestinationCopyTypeIdentifiers() as! [String]
        guard supported.contains(typeIdentifier) else { throw XCTSkip("ImageIO cannot encode fixture type \(typeIdentifier) on this Mac.") }
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(data: nil, width: 80, height: 40, bitsPerComponent: 8, bytesPerRow: 320, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(red: 1, green: 0, blue: 0, alpha: 0.5)
        context.fill(CGRect(x: 0, y: 0, width: 80, height: 40))
        let bitmap = try XCTUnwrap(context.makeImage())
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, typeIdentifier as CFString, frameCount, nil))
        let properties: [CFString: Any] = [kCGImagePropertyOrientation: orientation]
        for _ in 0..<frameCount { CGImageDestinationAddImage(destination, bitmap, properties as CFDictionary) }
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }
}
#else
final class ImageConverterTests: XCTestCase {
    func testImageIOUnavailableOnThisPlatform() throws {
        throw XCTSkip("ImageIO conversion requires macOS; no image conversion was exercised on this host.")
    }
}
#endif
