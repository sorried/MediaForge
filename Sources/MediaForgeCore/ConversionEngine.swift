import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

public struct ConversionEngine: Sendable {
    public let toolchain: FFmpegToolchain
    public init(toolchain: FFmpegToolchain) { self.toolchain = toolchain }
    public func convert(_ request: ConversionRequest, progress: @escaping @Sendable (ConversionProgress) -> Void = { _ in }) async throws -> ConversionResult {
        let startedAt = Date()
        try Task.checkCancellation()
        guard request.inputURL.isFileURL, request.outputURL.isFileURL else { throw MediaForgeError.invalidMedia("Only local files are supported.") }
        guard request.inputURL.standardizedFileURL != request.outputURL.standardizedFileURL else { throw MediaForgeError.invalidSettings("Input and output must be different files.") }
        guard !FileManager.default.fileExists(atPath: request.outputURL.path) else { throw MediaForgeError.outputExists(request.outputURL) }
        let probe = MediaProbe(toolchain: toolchain)
        let input = try await probe.inspect(request.inputURL)
        try request.settings.validate(duration: input.duration, requiresEvenDimensions: !request.profile.isImage)
        let capabilities = try await toolchain.capabilities()
        guard capabilities.supports(request.profile) else { throw MediaForgeError.unsupported(capabilities.detail(for: request.profile)) }
        guard request.profile.isAudio ? input.hasAudio : input.hasVideo else { throw MediaForgeError.unsupported("Input does not contain the required media stream.") }
        if request.profile.isAudio && request.settings.removeAudio { throw MediaForgeError.invalidSettings("An audio output cannot have its audio removed.") }
        let directory = request.outputURL.deletingLastPathComponent()
        let workspace = directory.appendingPathComponent(".mediaforge-" + request.id.uuidString + "-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer {
            do { try FileManager.default.removeItem(at: workspace) }
            catch { NSLog("MediaForge could not remove job directory %@: %@", workspace.path, error.localizedDescription) }
        }
        let temporary = workspace.appendingPathComponent("output." + request.profile.fileExtension)
        let duration = request.settings.trimEnd.map { $0 - (request.settings.trimStart ?? 0) } ?? input.duration.map { $0 - (request.settings.trimStart ?? 0) }
        var effectiveRequest = request
        var targetBudget: TargetSizeBudget?
        if let targetSize = request.settings.targetSizeMB {
            guard [.mp4, .mov].contains(request.profile), let duration else { throw MediaForgeError.invalidSettings("Target size is available for video with a known duration only.") }
            guard request.settings.videoBitrateKbps == nil else { throw MediaForgeError.invalidSettings("Choose either target size or a fixed video bitrate.") }
            let budget = try TargetSizeBudget(targetSizeMB: targetSize, duration: duration, audioBitrateKbps: request.settings.audioBitrateKbps ?? 128, hasAudio: input.hasAudio && !request.settings.removeAudio)
            targetBudget = budget
            effectiveRequest.settings.videoBitrateKbps = budget.videoBitrateKbps
            effectiveRequest.settings.audioBitrateKbps = budget.audioBitrateKbps > 0 ? budget.audioBitrateKbps : nil
        }
        let parser = FFmpegProgressParser(duration: duration, callback: progress)
        let arguments = try makeArguments(request: effectiveRequest, temporary: temporary, capabilities: capabilities)
        let output = try await ProcessRunner().run(executable: toolchain.ffmpegURL, arguments: arguments, timeout: nil, captureStdout: false, stdoutChunk: { parser.consume($0) })
        guard output.exitCode == 0 else { throw MediaForgeError.processFailed(output.exitCode, output.stderrText) }
        try Task.checkCancellation()
        var metadata = try await probe.inspect(temporary)
        guard request.profile.isAudio ? metadata.hasAudio : metadata.hasVideo else { throw MediaForgeError.invalidMedia("Converted file is missing the required media stream.") }
        try validateOutput(metadata, request: request, expectedDuration: duration, expectsAudio: input.hasAudio && !request.settings.removeAudio && !request.profile.isImage, capabilities: capabilities)
        try Task.checkCancellation()
        try await verifyDecoding(temporary)
        try Task.checkCancellation()
        try OutputManager.commit(temporary: temporary, destination: request.outputURL)
        metadata.url = request.outputURL
        progress(.init(fraction: 1, processedSeconds: duration ?? 0, speed: nil, frame: nil))
        return ConversionResult(outputURL: request.outputURL, metadata: metadata, elapsedSeconds: Date().timeIntervalSince(startedAt), requestedTargetSizeBytes: targetBudget?.targetBytes, targetSizeDeviationFraction: targetBudget.map { Double(metadata.size) / Double($0.targetBytes) - 1 })
    }

    func verifyDecoding(_ url: URL) async throws {
        let output = try await ProcessRunner().run(executable: toolchain.ffmpegURL, arguments: [
            "-hide_banner", "-nostdin", "-loglevel", "error", "-xerror", "-abort_on", "empty_output_stream", "-err_detect", "explode",
            "-protocol_whitelist", "file,pipe", "-i", url.path,
            "-map", "0:v:0?", "-map", "0:a:0?", "-f", "null", "-"
        ], timeout: nil, captureStdout: false)
        guard output.exitCode == 0 else { throw MediaForgeError.processFailed(output.exitCode, output.stderrText) }
    }

    func validateOutput(_ metadata: MediaMetadata, request: ConversionRequest, expectedDuration: Double?, expectsAudio: Bool, capabilities: FFmpegCapabilities) throws {
        let video = metadata.streams.first { $0.codecType == "video" }
        let audio = metadata.streams.first { $0.codecType == "audio" }
        if expectsAudio && audio == nil { throw MediaForgeError.invalidMedia("Converted file is missing the original audio stream.") }
        if !request.profile.isAudio {
            if let width = request.settings.width, video?.width != width { throw MediaForgeError.invalidMedia("Output width does not match the requested size.") }
            if let height = request.settings.height, video?.height != height { throw MediaForgeError.invalidMedia("Output height does not match the requested size.") }
        }
        if !request.profile.isAudio, !request.profile.isImage, let requested = request.settings.frameRate {
            guard let actual = video?.frameRate, actual.isFinite, abs(actual - requested) <= max(0.01, requested * 0.001) else {
                throw MediaForgeError.invalidMedia("Output frame rate does not match the requested rate.")
            }
        }
        if !request.profile.isImage, let expectedDuration {
            guard let actual = metadata.duration, actual.isFinite, actual > 0,
                  abs(actual - expectedDuration) <= max(0.5, expectedDuration * 0.05) else {
                throw MediaForgeError.invalidMedia("Output duration is unavailable or does not match the requested trim.")
            }
        }
        let composition = try capabilities.composition(for: request.profile, preference: request.settings.videoEncoderPreference)
        guard (request.profile.isAudio ? audio?.codecName : video?.codecName) == (request.profile.isAudio ? composition.audioCodec : composition.videoCodec) else {
            throw MediaForgeError.invalidMedia("Output codec does not match the selected profile.")
        }
        if !request.profile.isImage, !request.profile.isAudio, !request.settings.removeAudio, let audio, audio.codecName != composition.audioCodec {
            throw MediaForgeError.invalidMedia("Output audio codec does not match the selected container.")
        }
        if let audio {
            if let rate = request.settings.sampleRate, audio.sampleRate != rate { throw MediaForgeError.invalidMedia("Output sample rate does not match the requested rate.") }
            if let channels = request.settings.channels, audio.channels != channels { throw MediaForgeError.invalidMedia("Output channels do not match the requested layout.") }
        }
        if request.settings.removeAudio && metadata.hasAudio { throw MediaForgeError.invalidMedia("Output unexpectedly contains audio.") }
    }

    func makeArguments(request: ConversionRequest, temporary: URL, capabilities: FFmpegCapabilities) throws -> [String] {
        let settings = request.settings
        let composition = try capabilities.composition(for: request.profile, preference: settings.videoEncoderPreference)
        var arguments = ["-hide_banner", "-nostdin", "-loglevel", "error", "-n", "-progress", "pipe:1", "-nostats"]
        if let start = settings.trimStart { arguments += ["-ss", String(start)] }
        arguments += ["-protocol_whitelist", "file,pipe", "-i", request.inputURL.path]
        if let end = settings.trimEnd { arguments += ["-t", String(end - (settings.trimStart ?? 0))] }
        if request.profile.isAudio {
            arguments += ["-map", "0:a:0", "-vn"]
            guard let encoder = composition.audioEncoder else { throw MediaForgeError.unsupported("Audio encoder unavailable.") }
            arguments += ["-c:a", encoder]
        } else {
            arguments += ["-map", "0:v:0"]
            if request.profile.isImage {
                guard let encoder = composition.videoEncoder else { throw MediaForgeError.unsupported("Image encoder unavailable.") }
                arguments += ["-an", "-frames:v", "1", "-c:v", encoder, "-threads", "1", "-update", "1"]
            } else {
                guard let encoder = composition.videoEncoder else { throw MediaForgeError.unsupported("Video encoder unavailable.") }
                arguments += ["-c:v", encoder, "-pix_fmt", "yuv420p"]
                if settings.removeAudio { arguments += ["-an"] }
                else if let audio = composition.audioEncoder { arguments += ["-map", "0:a:0?", "-c:a", audio] }
                if composition.fastStart { arguments += ["-movflags", "+faststart"] }
                if let rate = settings.videoBitrateKbps { arguments += ["-b:v", String(rate) + "k"] }
                else { arguments += ["-b:v", "4000k"] }
                if let rate = settings.frameRate { arguments += ["-r", String(rate)] }
            }
            if settings.width != nil || settings.height != nil {
                let imageFormat = request.profile.isImage ? "format=rgba," : ""
                let divisor = request.profile.isImage ? 1 : 2
                if settings.preserveAspectRatio, let width = settings.width, let height = settings.height {
                    let target = String(width) + ":" + String(height)
                    arguments += ["-vf", imageFormat + "scale=" + target + ":force_original_aspect_ratio=decrease:force_divisible_by=" + String(divisor) + ",pad=" + target + ":(ow-iw)/2:(oh-ih)/2,setsar=1"]
                } else {
                    arguments += ["-vf", imageFormat + "scale=" + String(settings.width ?? -divisor) + ":" + String(settings.height ?? -divisor) + ",setsar=1"]
                }
            } else if !request.profile.isImage {
                arguments += ["-vf", "scale=trunc(iw/2)*2:trunc(ih/2)*2"]
            }
        }
        if let rate = settings.audioBitrateKbps, composition.audioCodec != "pcm_s16le" && composition.audioCodec != "pcm_s16be" && composition.audioCodec != "flac", !settings.removeAudio {
            arguments += ["-b:a", String(rate) + "k"]
        }
        if !request.profile.isImage && !settings.removeAudio {
            if let rate = settings.sampleRate { arguments += ["-ar", String(rate)] }
            if let channels = settings.channels { arguments += ["-ac", String(channels)] }
        }
        arguments += ["-f", composition.muxer]
        arguments.append(temporary.path)
        return arguments
    }
}

// The incremental byte buffer and fields are lock-protected; callbacks run outside the lock.
final class FFmpegProgressParser: @unchecked Sendable {
    private let lock = NSLock()
    private var pending = Data()
    private var fields: [String: String] = [:]
    private let duration: Double?
    private let callback: @Sendable (ConversionProgress) -> Void
    init(duration: Double?, callback: @escaping @Sendable (ConversionProgress) -> Void) {
        self.duration = duration
        self.callback = callback
    }
    func consume(_ chunk: Data) {
        lock.lock()
        pending.append(chunk)
        var updates: [ConversionProgress] = []
        while let newline = pending.firstIndex(of: 10) {
            let line = String(decoding: pending[..<newline], as: UTF8.self)
            pending.removeSubrange(...newline)
            let pair = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard pair.count == 2, ["out_time_us", "speed", "frame", "progress"].contains(String(pair[0])) else { continue }
            fields[String(pair[0])] = String(pair[1])
            if pair[0] == "progress" {
                let rawSeconds = (Double(fields["out_time_us"] ?? "") ?? 0) / 1_000_000
                let seconds = rawSeconds.isFinite ? max(0, rawSeconds) : 0
                let fraction = duration.flatMap { $0.isFinite && $0 > 0 ? min(0.99, seconds / $0) : nil }
                updates.append(.init(fraction: fraction, processedSeconds: seconds, speed: fields["speed"], frame: fields["frame"].flatMap(Int.init)))
                fields.removeAll(keepingCapacity: true)
            }
        }
        if pending.count > 65536 { pending.removeAll() }
        lock.unlock()
        for update in updates { callback(update) }
    }
}
