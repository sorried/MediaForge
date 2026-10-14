import Foundation

public enum OutputProfile: String, Codable, CaseIterable, Identifiable, Sendable {
    case mp4, mov, mkv, webm, avi, m4v, ts
    case mp3, m4a, aac, aiff, ogg, opus, flac, wav
    case png, jpeg, webp
    public var id: String { rawValue }
    public var fileExtension: String { rawValue == "jpeg" ? "jpg" : rawValue }
    public var title: String { rawValue.uppercased() }
    public var isImage: Bool { [.png, .jpeg, .webp].contains(self) }
    public var isAudio: Bool { [.mp3, .m4a, .aac, .aiff, .ogg, .opus, .flac, .wav].contains(self) }
}

public enum VideoEncoderPreference: String, Codable, CaseIterable, Sendable { case automatic, software, hardware }

public struct ConversionSettings: Codable, Equatable, Sendable {
    public var trimStart: Double?
    public var trimEnd: Double?
    public var width: Int?
    public var height: Int?
    public var videoBitrateKbps: Int?
    public var audioBitrateKbps: Int?
    public var frameRate: Double?
    public var removeAudio: Bool
    public var sampleRate: Int?
    public var channels: Int?
    public var targetSizeMB: Double?
    public var videoEncoderPreference: VideoEncoderPreference
    public var preserveAspectRatio: Bool
    public init(trimStart: Double? = nil, trimEnd: Double? = nil, width: Int? = nil, height: Int? = nil, videoBitrateKbps: Int? = nil, audioBitrateKbps: Int? = nil, frameRate: Double? = nil, removeAudio: Bool = false, sampleRate: Int? = nil, channels: Int? = nil, targetSizeMB: Double? = nil, videoEncoderPreference: VideoEncoderPreference = .automatic, preserveAspectRatio: Bool = true) {
        self.trimStart = trimStart
        self.trimEnd = trimEnd
        self.width = width
        self.height = height
        self.videoBitrateKbps = videoBitrateKbps
        self.audioBitrateKbps = audioBitrateKbps
        self.frameRate = frameRate
        self.removeAudio = removeAudio
        self.sampleRate = sampleRate
        self.channels = channels
        self.targetSizeMB = targetSizeMB
        self.videoEncoderPreference = videoEncoderPreference
        self.preserveAspectRatio = preserveAspectRatio
    }
    private enum CodingKeys: String, CodingKey {
        case trimStart, trimEnd, width, height, videoBitrateKbps, audioBitrateKbps, frameRate, removeAudio
        case sampleRate, channels, targetSizeMB, videoEncoderPreference, preserveAspectRatio
    }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        trimStart = try values.decodeIfPresent(Double.self, forKey: .trimStart)
        trimEnd = try values.decodeIfPresent(Double.self, forKey: .trimEnd)
        width = try values.decodeIfPresent(Int.self, forKey: .width)
        height = try values.decodeIfPresent(Int.self, forKey: .height)
        videoBitrateKbps = try values.decodeIfPresent(Int.self, forKey: .videoBitrateKbps)
        audioBitrateKbps = try values.decodeIfPresent(Int.self, forKey: .audioBitrateKbps)
        frameRate = try values.decodeIfPresent(Double.self, forKey: .frameRate)
        removeAudio = try values.decodeIfPresent(Bool.self, forKey: .removeAudio) ?? false
        sampleRate = try values.decodeIfPresent(Int.self, forKey: .sampleRate)
        channels = try values.decodeIfPresent(Int.self, forKey: .channels)
        targetSizeMB = try values.decodeIfPresent(Double.self, forKey: .targetSizeMB)
        videoEncoderPreference = try values.decodeIfPresent(VideoEncoderPreference.self, forKey: .videoEncoderPreference) ?? .automatic
        preserveAspectRatio = try values.decodeIfPresent(Bool.self, forKey: .preserveAspectRatio) ?? true
    }
    public func validate(duration: Double? = nil, requiresEvenDimensions: Bool = true) throws {
        if let start = trimStart, !start.isFinite || start < 0 { throw MediaForgeError.invalidSettings("Trim start must be finite and nonnegative.") }
        if let end = trimEnd, !end.isFinite || end <= (trimStart ?? 0) { throw MediaForgeError.invalidSettings("Trim end must be after trim start.") }
        if let duration, let start = trimStart, start >= duration { throw MediaForgeError.invalidSettings("Trim start exceeds media duration.") }
        if let duration, let end = trimEnd, end > duration + 0.1 { throw MediaForgeError.invalidSettings("Trim end exceeds media duration.") }
        let minimumDimension = requiresEvenDimensions ? 2 : 1
        for dimension in [width, height].compactMap({ $0 }) where !(minimumDimension...16384).contains(dimension) || (requiresEvenDimensions && dimension % 2 != 0) {
            throw MediaForgeError.invalidSettings(requiresEvenDimensions ? "Dimensions must be even numbers from 2 to 16384." : "Dimensions must be numbers from 1 to 16384.")
        }
        if let rate = videoBitrateKbps, !(16...200000).contains(rate) { throw MediaForgeError.invalidSettings("Video bitrate must be 16–200000 kbps.") }
        if let rate = audioBitrateKbps, !(8...1536).contains(rate) { throw MediaForgeError.invalidSettings("Audio bitrate must be 8–1536 kbps.") }
        if let rate = sampleRate, ![8000, 11025, 16000, 22050, 24000, 32000, 44100, 48000, 88200, 96000, 192000].contains(rate) { throw MediaForgeError.invalidSettings("Unsupported sample rate.") }
        if let channels, !(1...2).contains(channels) { throw MediaForgeError.invalidSettings("Choose mono or stereo audio.") }
        if let size = targetSizeMB, !size.isFinite || size <= 0 || size > 100000 { throw MediaForgeError.invalidSettings("Target size must be a positive finite value up to 100000 MB.") }
        if let rate = frameRate, !rate.isFinite || !(1...240).contains(rate) { throw MediaForgeError.invalidSettings("Frame rate must be 1–240 fps.") }
    }
}

public struct ConversionPreset: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var profile: OutputProfile
    public var settings: ConversionSettings
    public init(id: UUID = UUID(), name: String, profile: OutputProfile, settings: ConversionSettings = .init()) {
        self.id = id
        self.name = name
        self.profile = profile
        self.settings = settings
    }
}

public struct AppSettings: Codable, Sendable {
    public var outputDirectory: URL?
    public var maxConcurrentJobs: Int
    public var presets: [ConversionPreset]
    public init(outputDirectory: URL? = nil, maxConcurrentJobs: Int = 1, presets: [ConversionPreset] = []) {
        self.outputDirectory = outputDirectory
        self.maxConcurrentJobs = maxConcurrentJobs
        self.presets = presets
    }
    public func validate() throws {
        guard (1...4).contains(maxConcurrentJobs) else { throw MediaForgeError.invalidSettings("Run between one and four jobs at once.") }
        for preset in presets { try preset.settings.validate(requiresEvenDimensions: !preset.profile.isImage) }
    }
}

public struct MediaStream: Codable, Equatable, Sendable {
    public var index: Int
    public var codecType: String
    public var codecName: String?
    public var width: Int?
    public var height: Int?
    public var sampleRate: Int?
    public var channels: Int?
    public var frameRate: Double?
}

public struct MediaMetadata: Codable, Equatable, Sendable {
    public var url: URL
    public var formatName: String
    public var duration: Double?
    public var size: Int64
    public var bitrate: Int64?
    public var streams: [MediaStream]
    public var hasVideo: Bool { streams.contains { $0.codecType == "video" } }
    public var hasAudio: Bool { streams.contains { $0.codecType == "audio" } }
}

public struct ConversionRequest: Codable, Sendable {
    public var id: UUID
    public var inputURL: URL
    public var outputURL: URL
    public var profile: OutputProfile
    public var settings: ConversionSettings
    public init(id: UUID = UUID(), inputURL: URL, outputURL: URL, profile: OutputProfile, settings: ConversionSettings = .init()) {
        self.id = id
        self.inputURL = inputURL
        self.outputURL = outputURL
        self.profile = profile
        self.settings = settings
    }
}

public struct ConversionProgress: Sendable {
    public var fraction: Double?
    public var processedSeconds: Double
    public var speed: String?
    public var frame: Int?
}

public struct ConversionResult: Codable, Sendable {
    public var outputURL: URL
    public var metadata: MediaMetadata
    public var elapsedSeconds: Double
    public var requestedTargetSizeBytes: Int64? = nil
    public var targetSizeDeviationFraction: Double? = nil
}

public enum JobStatus: String, Codable, Sendable { case waiting, running, completed, failed, cancelled }
public struct ConversionJob: Codable, Identifiable, Sendable {
    public var id: UUID { request.id }
    public var request: ConversionRequest
    public var status: JobStatus
    public var errorMessage: String?
    public init(request: ConversionRequest, status: JobStatus = .waiting, errorMessage: String? = nil) {
        self.request = request
        self.status = status
        self.errorMessage = errorMessage
    }
}
public struct HistoryEntry: Codable, Identifiable, Sendable {
    public var id: UUID
    public var request: ConversionRequest
    public var result: ConversionResult?
    public var status: JobStatus
    public var finishedAt: Date
    public var errorMessage: String?
    public init(id: UUID = UUID(), request: ConversionRequest, result: ConversionResult? = nil, status: JobStatus, finishedAt: Date = Date(), errorMessage: String? = nil) {
        self.id = id
        self.request = request
        self.result = result
        self.status = status
        self.finishedAt = finishedAt
        self.errorMessage = errorMessage
    }
}

public enum MediaForgeError: Error, LocalizedError, Sendable {
    case missingTool(String), invalidSettings(String), unsupported(String), processFailed(Int32, String), invalidMedia(String), outputExists(URL), fileOperation(String)
    public var errorDescription: String? {
        switch self {
        case .missingTool(let name): return "Could not find executable \(name). Install FFmpeg or select its location."
        case .invalidSettings(let text), .unsupported(let text), .invalidMedia(let text), .fileOperation(let text): return text
        case .processFailed(let code, let text): return "Media process exited with status \(code): \(text)"
        case .outputExists(let url): return "Output already exists: \(url.lastPathComponent). Choose another filename."
        }
    }
}
