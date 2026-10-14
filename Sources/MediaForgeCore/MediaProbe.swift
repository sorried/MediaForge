import Foundation

public struct FFmpegToolchain: Codable, Sendable {
    public var ffmpegURL: URL
    public var ffprobeURL: URL
    public init(ffmpegURL: URL, ffprobeURL: URL) {
        self.ffmpegURL = ffmpegURL
        self.ffprobeURL = ffprobeURL
    }
    public static func discover(allowExternalTools: Bool = false) throws -> FFmpegToolchain {
        var directories: [URL] = []
        if let resources = Bundle.main.resourceURL { directories.append(resources.appendingPathComponent("Tools")) }
        if allowExternalTools {
            directories += (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map { URL(fileURLWithPath: String($0)) }
            directories += [URL(fileURLWithPath: "/opt/homebrew/bin"), URL(fileURLWithPath: "/usr/local/bin"), URL(fileURLWithPath: "/usr/bin")]
        }
        for directory in directories {
            let ffmpeg = directory.appendingPathComponent("ffmpeg")
            let ffprobe = directory.appendingPathComponent("ffprobe")
            if FileManager.default.isExecutableFile(atPath: ffmpeg.path) && FileManager.default.isExecutableFile(atPath: ffprobe.path) {
                return .init(ffmpegURL: ffmpeg, ffprobeURL: ffprobe)
            }
        }
        throw MediaForgeError.missingTool("bundled FFmpeg / FFprobe")
    }
    public func capabilities() async throws -> FFmpegCapabilities {
        let runner = ProcessRunner()
        let version = try await runner.run(executable: ffmpegURL, arguments: ["-version"])
        guard version.exitCode == 0 else { throw MediaForgeError.processFailed(version.exitCode, version.stderrText) }
        let encoders = try await runner.run(executable: ffmpegURL, arguments: ["-hide_banner", "-encoders"])
        guard encoders.exitCode == 0 else { throw MediaForgeError.processFailed(encoders.exitCode, encoders.stderrText) }
        let muxerOutput = try await runner.run(executable: ffmpegURL, arguments: ["-hide_banner", "-muxers"])
        guard muxerOutput.exitCode == 0 else { throw MediaForgeError.processFailed(muxerOutput.exitCode, muxerOutput.stderrText) }
        let names = Set(String(decoding: encoders.stdout, as: UTF8.self).split(separator: "\n").compactMap { line -> String? in
            let columns = line.split(whereSeparator: { $0.isWhitespace })
            guard columns.count >= 2, columns[0].count == 6, columns[0].first == "V" || columns[0].first == "A" || columns[0].first == "S" else { return nil }
            guard columns[0].dropFirst().allSatisfy({ "ABCDEFGHIJKLMNOPQRSTUVWXYZ.".contains($0) }) else { return nil }
            return String(columns[1])
        })
        let muxers = Set(String(decoding: muxerOutput.stdout, as: UTF8.self).split(separator: "\n").flatMap { line -> [String] in
            let columns = line.split(whereSeparator: { $0.isWhitespace })
            guard columns.count >= 2, columns[0] == "E" else { return [] }
            return columns[1].split(separator: ",").map(String.init)
        })
        return FFmpegCapabilities(version: String(decoding: version.stdout, as: UTF8.self), encoders: names, muxers: muxers)
    }
}

public struct FFmpegComposition: Sendable {
    public var muxer: String
    public var videoEncoder: String? = nil
    public var audioEncoder: String? = nil
    public var videoCodec: String? = nil
    public var audioCodec: String? = nil
    public var fastStart: Bool = false
}

public struct FFmpegCapabilities: Codable, Sendable {
    public var version: String
    public var encoders: Set<String>
    public var muxers: Set<String>
    public init(version: String, encoders: Set<String>, muxers: Set<String> = []) {
        self.version = version
        self.encoders = encoders
        self.muxers = muxers
    }
    public var videoEncoder: String? {
        #if os(macOS)
        if encoders.contains("h264_videotoolbox") { return "h264_videotoolbox" }
        #endif
        return encoders.contains("mpeg4") ? "mpeg4" : nil
    }
    public func videoEncoder(preference: VideoEncoderPreference) throws -> String {
        switch preference {
        case .automatic:
            if let videoEncoder { return videoEncoder }
        case .software:
            if encoders.contains("mpeg4") { return "mpeg4" }
        case .hardware:
            #if os(macOS)
            if encoders.contains("h264_videotoolbox") { return "h264_videotoolbox" }
            #endif
        }
        throw MediaForgeError.unsupported("Selected video encoder is unavailable on this platform or in this FFmpeg build.")
    }
    public var mp3Encoder: String? { ["libmp3lame", "libshine", "mp3"].first { encoders.contains($0) } }
    public func composition(for profile: OutputProfile, preference: VideoEncoderPreference = .automatic) throws -> FFmpegComposition {
        func choose(_ candidates: [String]) throws -> String {
            guard let encoder = candidates.first(where: { encoders.contains($0) }) else { throw MediaForgeError.unsupported("Required encoder is unavailable for " + profile.title + ".") }
            return encoder
        }
        let composition: FFmpegComposition
        switch profile {
        case .mp4, .mov, .mkv, .m4v:
            let video = try videoEncoder(preference: preference)
            let muxer = profile == .mkv ? "matroska" : (profile == .m4v ? "mp4" : profile.rawValue)
            composition = .init(muxer: muxer, videoEncoder: video, audioEncoder: try choose(["aac"]), videoCodec: video == "h264_videotoolbox" ? "h264" : "mpeg4", audioCodec: "aac", fastStart: muxer == "mp4" || muxer == "mov")
        case .avi:
            guard preference != .hardware else { throw MediaForgeError.unsupported("AVI uses the software MPEG-4 encoder.") }
            composition = .init(muxer: "avi", videoEncoder: try choose(["mpeg4"]), audioEncoder: try choose(["pcm_s16le"]), videoCodec: "mpeg4", audioCodec: "pcm_s16le")
        case .ts:
            let hardware: String?
            #if os(macOS)
            hardware = preference != .software && encoders.contains("h264_videotoolbox") ? "h264_videotoolbox" : nil
            #else
            hardware = nil
            #endif
            if preference == .hardware && hardware == nil { throw MediaForgeError.unsupported("Hardware H.264 is unavailable.") }
            let video = try hardware ?? choose(["mpeg2video"])
            composition = .init(muxer: "mpegts", videoEncoder: video, audioEncoder: try choose(["aac"]), videoCodec: hardware == nil ? "mpeg2video" : "h264", audioCodec: "aac")
        case .webm:
            guard preference != .hardware else { throw MediaForgeError.unsupported("WebM requires a compatible software encoder.") }
            let video = try choose(["libvpx-vp9", "libvpx"])
            let audio = try choose(["libopus", "libvorbis"])
            composition = .init(muxer: "webm", videoEncoder: video, audioEncoder: audio, videoCodec: video == "libvpx-vp9" ? "vp9" : "vp8", audioCodec: audio == "libopus" ? "opus" : "vorbis")
        case .mp3:
            composition = .init(muxer: "mp3", audioEncoder: try choose(["libmp3lame", "libshine", "mp3"]), audioCodec: "mp3")
        case .m4a, .aac:
            composition = .init(muxer: profile == .aac ? "adts" : "ipod", audioEncoder: try choose(["aac"]), audioCodec: "aac")
        case .aiff:
            composition = .init(muxer: "aiff", audioEncoder: try choose(["pcm_s16be"]), audioCodec: "pcm_s16be")
        case .ogg:
            composition = .init(muxer: "ogg", audioEncoder: try choose(["libvorbis"]), audioCodec: "vorbis")
        case .opus:
            composition = .init(muxer: "opus", audioEncoder: try choose(["libopus"]), audioCodec: "opus")
        case .flac:
            composition = .init(muxer: "flac", audioEncoder: try choose(["flac"]), audioCodec: "flac")
        case .wav:
            composition = .init(muxer: "wav", audioEncoder: try choose(["pcm_s16le"]), audioCodec: "pcm_s16le")
        case .png, .jpeg, .webp:
            let encoder = try choose(profile == .png ? ["png"] : (profile == .jpeg ? ["mjpeg"] : ["libwebp", "libwebp_anim"]))
            composition = .init(muxer: "image2", videoEncoder: encoder, videoCodec: profile == .webp ? "webp" : encoder)
        }
        guard muxers.contains(composition.muxer) else { throw MediaForgeError.unsupported("Required output container is unavailable for " + profile.title + ".") }
        return composition
    }
    public func supports(_ profile: OutputProfile) -> Bool { (try? composition(for: profile)) != nil }
    public func detail(for profile: OutputProfile) -> String {
        guard let composition = try? composition(for: profile) else { return "Required encoder or output container is not available in this FFmpeg build." }
        let codecs = [composition.videoCodec, composition.audioCodec].compactMap { $0 }.joined(separator: " / ")
        return codecs + (composition.videoCodec == "mpeg4" ? " · MPEG-4 Part 2 (not H.264)" : "")
    }
}

public struct MediaProbe: Sendable {
    public let toolchain: FFmpegToolchain
    public init(toolchain: FFmpegToolchain) { self.toolchain = toolchain }
    public func inspect(_ url: URL) async throws -> MediaMetadata {
        try Task.checkCancellation()
        guard url.isFileURL else { throw MediaForgeError.invalidMedia("Only local media files are supported.") }
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular else {
            throw MediaForgeError.invalidMedia("Input must be a regular local file.")
        }
        let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        guard size > 0 else { throw MediaForgeError.invalidMedia("Media file is empty.") }
        let output = try await ProcessRunner().run(executable: toolchain.ffprobeURL, arguments: ["-v", "error", "-protocol_whitelist", "file,pipe", "-show_format", "-show_streams", "-of", "json", url.path])
        guard output.exitCode == 0 else { throw MediaForgeError.processFailed(output.exitCode, output.stderrText) }
        let probe = try JSONDecoder().decode(ProbeDocument.self, from: output.stdout)
        let streams = (probe.streams ?? []).map { stream in
            let rate = Self.frameRate(stream.avg_frame_rate)
            return MediaStream(index: stream.index, codecType: stream.codec_type ?? "unknown", codecName: stream.codec_name, width: stream.width, height: stream.height, sampleRate: stream.sample_rate.flatMap(Int.init), channels: stream.channels, frameRate: rate)
        }
        guard !streams.isEmpty else { throw MediaForgeError.invalidMedia("No media streams were found.") }
        let duration = probe.format?.duration.flatMap(Double.init).flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        return MediaMetadata(url: url, formatName: probe.format?.format_name ?? "unknown", duration: duration, size: size, bitrate: probe.format?.bit_rate.flatMap(Int64.init), streams: streams)
    }
    static func frameRate(_ value: String?) -> Double? {
        guard let value else { return nil }
        let parts = value.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, let numerator = Double(parts[0]), let denominator = Double(parts[1]),
              numerator.isFinite, denominator.isFinite, numerator > 0, denominator > 0 else { return nil }
        let rate = numerator / denominator
        return rate.isFinite && rate > 0 ? rate : nil
    }
}
private struct ProbeDocument: Decodable {
    var streams: [ProbeStream]?
    var format: ProbeFormat?
}
private struct ProbeFormat: Decodable {
    var format_name: String?
    var duration: String?
    var bit_rate: String?
}
private struct ProbeStream: Decodable {
    var index: Int
    var codec_type: String?
    var codec_name: String?
    var width: Int?
    var height: Int?
    var sample_rate: String?
    var channels: Int?
    var avg_frame_rate: String?
}
