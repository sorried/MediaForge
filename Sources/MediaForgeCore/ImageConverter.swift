#if canImport(ImageIO) && canImport(CoreGraphics) && canImport(Darwin)
import Foundation
import ImageIO
import CoreGraphics
import Darwin

public enum ImageOutputFormat: String, CaseIterable, Codable, Sendable {
    case png, jpeg, heic, tiff, bmp

    public var fileExtension: String { self == .jpeg ? "jpg" : rawValue }
    public var typeIdentifier: String {
        switch self {
        case .png: return "public.png"
        case .jpeg: return "public.jpeg"
        case .heic: return "public.heic"
        case .tiff: return "public.tiff"
        case .bmp: return "com.microsoft.bmp"
        }
    }
    public var preservesAlpha: Bool { self == .png || self == .tiff }
}

public struct ImageFlattenColor: Equatable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }
    public static let white = Self(red: 1, green: 1, blue: 1)
    public static let black = Self(red: 0, green: 0, blue: 0)
}

public struct ImageConversionRequest: Sendable {
    public var inputURL: URL
    public var outputURL: URL
    public var format: ImageOutputFormat
    public var maxWidth: Int?
    public var maxHeight: Int?
    public var quality: Double
    public var allowDropAnimation: Bool
    public var flattenColor: ImageFlattenColor?

    public init(inputURL: URL, outputURL: URL, format: ImageOutputFormat, maxWidth: Int? = nil, maxHeight: Int? = nil, quality: Double = 0.9, allowDropAnimation: Bool = false, flattenColor: ImageFlattenColor? = nil) {
        self.inputURL = inputURL
        self.outputURL = outputURL
        self.format = format
        self.maxWidth = maxWidth
        self.maxHeight = maxHeight
        self.quality = quality
        self.allowDropAnimation = allowDropAnimation
        self.flattenColor = flattenColor
    }
}

public struct ImageInspection: Sendable {
    public let width: Int
    public let height: Int
    public let frameCount: Int
    public let hasAlpha: Bool
    public let typeIdentifier: String
    public let orientation: Int
    public let bitsPerComponent: Int
    public let metadataKeys: [String]
}

public enum ImageConversionConsent: String, Sendable {
    case dropAnimation, flattenTransparency
}

public struct ImageConversionPreflight: Sendable {
    public let source: ImageInspection
    public let outputWidth: Int
    public let outputHeight: Int
    public let warnings: [String]
    public let requiredConsents: [ImageConversionConsent]
}

public struct ImageConversionResult: Sendable {
    public let outputURL: URL
    public let inspection: ImageInspection
    public let warnings: [String]
}

public enum ImageConversionError: Error, LocalizedError, Sendable {
    case invalidRequest(String)
    case invalidSource
    case unsupportedFormat(ImageOutputFormat)
    case animationConsentRequired
    case flattenColorRequired
    case destinationExists
    case encodingFailed
    case verificationFailed
    case fileOperation(String, Int32)

    public var errorDescription: String? {
        switch self {
        case .invalidRequest(let message): return message
        case .invalidSource: return "The source is not a complete, decodable image."
        case .unsupportedFormat(let format): return "ImageIO cannot encode \(format.rawValue.uppercased()) on this Mac."
        case .animationConsentRequired: return "Exporting only the first frame requires permission to discard animation or additional pages."
        case .flattenColorRequired: return "Choose a background color before discarding transparency."
        case .destinationExists: return "The destination already exists; no file was replaced."
        case .encodingFailed: return "ImageIO could not encode the image."
        case .verificationFailed: return "The encoded image did not pass decoding and dimension checks."
        case .fileOperation(let operation, let code): return "\(operation) failed (errno \(code))."
        }
    }
}

public struct ImageConverter: Sendable {
    public init() {}

    public var supportedFormats: [ImageOutputFormat] {
        let identifiers = CGImageDestinationCopyTypeIdentifiers() as! [String]
        return ImageOutputFormat.allCases.filter { identifiers.contains($0.typeIdentifier) }
    }

    public func inspect(_ inputURL: URL) throws -> ImageInspection {
        try inspection(source: openSource(inputURL))
    }

    public func preflight(_ request: ImageConversionRequest) throws -> ImageConversionPreflight {
        try validate(request)
        let source = try inspect(request.inputURL)
        let rotated = (5...8).contains(source.orientation)
        let width = rotated ? source.height : source.width
        let height = rotated ? source.width : source.height
        let scale = min(1, Double(request.maxWidth ?? width) / Double(width), Double(request.maxHeight ?? height) / Double(height))
        let outputWidth = max(1, Int(floor(Double(width) * scale)))
        let outputHeight = max(1, Int(floor(Double(height) * scale)))
        guard outputWidth <= 16384, outputHeight <= 16384, outputWidth * outputHeight <= 100_000_000 else {
            throw ImageConversionError.invalidRequest("Output is limited to 16384 pixels per side and 100 megapixels. Choose smaller bounds.")
        }
        var warnings = ["Camera, location, and other source metadata are not copied.", "Pixels are rendered as 8-bit sRGB; wide-gamut, HDR, and high-bit-depth data may change."]
        var requiredConsents: [ImageConversionConsent] = []
        if source.frameCount > 1 {
            warnings.append("Only frame 1 is exported; animation and additional pages will be discarded.")
            if !request.allowDropAnimation { requiredConsents.append(.dropAnimation) }
        }
        if source.hasAlpha && !request.format.preservesAlpha {
            warnings.append("Transparency will be flattened onto the chosen background color.")
            if request.flattenColor == nil { requiredConsents.append(.flattenTransparency) }
        }
        if request.format == .jpeg || request.format == .heic {
            warnings.append("This format uses lossy compression; quality is not a target file size.")
        }
        return ImageConversionPreflight(source: source, outputWidth: outputWidth, outputHeight: outputHeight, warnings: warnings, requiredConsents: requiredConsents)
    }

    public func convert(_ request: ImageConversionRequest) throws -> ImageConversionResult {
        try Task.checkCancellation()
        let plan = try preflight(request)
        try Task.checkCancellation()
        if plan.requiredConsents.contains(.dropAnimation) { throw ImageConversionError.animationConsentRequired }
        if plan.requiredConsents.contains(.flattenTransparency) { throw ImageConversionError.flattenColorRequired }
        let source = try openSource(request.inputURL)
        let current = try inspection(source: source)
        guard current.width == plan.source.width, current.height == plan.source.height, current.frameCount == plan.source.frameCount, current.hasAlpha == plan.source.hasAlpha, current.orientation == plan.source.orientation else {
            throw ImageConversionError.invalidRequest("The source changed after preflight. Run preflight again.")
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(plan.outputWidth, plan.outputHeight),
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw ImageConversionError.invalidSource
        }
        try Task.checkCancellation()
        let rendered = try render(thumbnail, width: plan.outputWidth, height: plan.outputHeight, preserveAlpha: request.format.preservesAlpha, background: request.flattenColor)
        try Task.checkCancellation()
        let parent = request.outputURL.deletingLastPathComponent().resolvingSymlinksInPath()
        let output = parent.appendingPathComponent(request.outputURL.lastPathComponent)
        let folder = parent.appendingPathComponent(".mediaforge-image-" + UUID().uuidString, isDirectory: true)
        let created = folder.path.withCString { Darwin.mkdir($0, mode_t(0o700)) }
        guard created == 0 else { throw ImageConversionError.fileOperation("Creating private job directory", errno) }
        defer {
            do { try FileManager.default.removeItem(at: folder) }
            catch { NSLog("MediaForge could not remove image job directory %@: %@", folder.path, error.localizedDescription) }
        }
        let staged = folder.appendingPathComponent("encoded." + request.format.fileExtension)
        guard let destination = CGImageDestinationCreateWithURL(staged as CFURL, request.format.typeIdentifier as CFString, 1, nil) else {
            throw ImageConversionError.encodingFailed
        }
        let properties: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: request.quality, kCGImagePropertyOrientation: 1]
        CGImageDestinationAddImage(destination, rendered, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw ImageConversionError.encodingFailed }
        let verified = try inspect(staged)
        let encodedSource = try openSource(staged)
        guard let decodedOutput = CGImageSourceCreateImageAtIndex(encodedSource, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary),
              decodedOutput.width == plan.outputWidth, decodedOutput.height == plan.outputHeight else {
            throw ImageConversionError.verificationFailed
        }
        guard verified.width == plan.outputWidth, verified.height == plan.outputHeight, verified.width > 0, verified.height > 0,
              verified.frameCount == 1, verified.typeIdentifier == request.format.typeIdentifier,
              !plan.source.hasAlpha || !request.format.preservesAlpha || verified.hasAlpha else {
            throw ImageConversionError.verificationFailed
        }
        try Task.checkCancellation()
        do {
            try OutputManager.commit(temporary: staged, destination: output)
        } catch MediaForgeError.outputExists {
            throw ImageConversionError.destinationExists
        }
        return ImageConversionResult(outputURL: output, inspection: verified, warnings: plan.warnings)
    }

    private func validate(_ request: ImageConversionRequest) throws {
        guard request.inputURL.isFileURL, request.outputURL.isFileURL else {
            throw ImageConversionError.invalidRequest("Input and output must be local file URLs.")
        }
        guard request.inputURL.resolvingSymlinksInPath().standardizedFileURL != request.outputURL.resolvingSymlinksInPath().standardizedFileURL else {
            throw ImageConversionError.invalidRequest("The original image cannot be the output destination.")
        }
        guard request.quality.isFinite, (0...1).contains(request.quality) else {
            throw ImageConversionError.invalidRequest("Quality must be a finite number from 0 to 1.")
        }
        for bound in [request.maxWidth, request.maxHeight].compactMap({ $0 }) {
            guard (1...16384).contains(bound) else { throw ImageConversionError.invalidRequest("Resize bounds must be from 1 to 16384 pixels.") }
        }
        if let color = request.flattenColor {
            guard [color.red, color.green, color.blue].allSatisfy({ $0.isFinite && (0...1).contains($0) }) else {
                throw ImageConversionError.invalidRequest("Background RGB components must be finite numbers from 0 to 1.")
            }
        }
        guard supportedFormats.contains(request.format) else { throw ImageConversionError.unsupportedFormat(request.format) }
        var existing = stat()
        if request.outputURL.path.withCString({ Darwin.lstat($0, &existing) }) == 0 {
            throw ImageConversionError.destinationExists
        }
    }

    private func openSource(_ url: URL) throws -> CGImageSource {
        guard url.isFileURL else { throw ImageConversionError.invalidSource }
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              (attributes[.size] as? NSNumber)?.int64Value ?? 0 > 0 else { throw ImageConversionError.invalidSource }
        guard url.isFileURL,
              let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) > 0, CGImageSourceGetStatus(source) == .statusComplete else {
            throw ImageConversionError.invalidSource
        }
        return source
    }

    private func inspection(source: CGImageSource) throws -> ImageInspection {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              let width = (properties[kCGImagePropertyPixelWidth as String] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight as String] as? NSNumber)?.intValue,
              width > 0, height > 0, width <= 100_000_000, height <= 100_000_000, width <= 100_000_000 / height,
              let type = CGImageSourceGetType(source) else { throw ImageConversionError.invalidSource }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 64, kCGImageSourceShouldCacheImmediately: true]
        guard let decoded = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw ImageConversionError.invalidSource
        }
        let alpha = (properties[kCGImagePropertyHasAlpha as String] as? NSNumber)?.boolValue == true || [.first, .last, .premultipliedFirst, .premultipliedLast, .alphaOnly].contains(decoded.alphaInfo)
        return ImageInspection(width: width, height: height, frameCount: CGImageSourceGetCount(source), hasAlpha: alpha, typeIdentifier: type as String, orientation: (properties[kCGImagePropertyOrientation as String] as? NSNumber)?.intValue ?? 1, bitsPerComponent: (properties[kCGImagePropertyDepth as String] as? NSNumber)?.intValue ?? decoded.bitsPerComponent, metadataKeys: properties.keys.sorted())
    }

    private func render(_ image: CGImage, width: Int, height: Int, preserveAlpha: Bool, background: ImageFlattenColor?) throws -> CGImage {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: space, bitmapInfo: (preserveAlpha ? CGImageAlphaInfo.premultipliedLast : CGImageAlphaInfo.noneSkipLast).rawValue) else {
            throw ImageConversionError.encodingFailed
        }
        let rectangle = CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height))
        if !preserveAlpha {
            let color = background ?? .white
            context.setFillColor(red: CGFloat(color.red), green: CGFloat(color.green), blue: CGFloat(color.blue), alpha: 1)
            context.fill(rectangle)
        }
        context.interpolationQuality = .high
        context.draw(image, in: rectangle)
        guard let rendered = context.makeImage() else { throw ImageConversionError.encodingFailed }
        return rendered
    }
}
#endif
