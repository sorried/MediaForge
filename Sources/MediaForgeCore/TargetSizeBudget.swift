import Foundation

public struct TargetSizeBudget: Sendable {
    public let targetBytes: Int64
    public let videoBitrateKbps: Int
    public let audioBitrateKbps: Int
    public init(targetSizeMB: Double, duration: Double, audioBitrateKbps: Int, hasAudio: Bool) throws {
        guard targetSizeMB.isFinite, targetSizeMB > 0, targetSizeMB <= 100000, duration.isFinite, duration > 0 else {
            throw MediaForgeError.invalidSettings("Target-size encoding requires a positive size and known duration.")
        }
        guard (8...1536).contains(audioBitrateKbps) else { throw MediaForgeError.invalidSettings("Audio bitrate must be 8–1536 kbps.") }
        let bytes = targetSizeMB * 1_000_000
        guard bytes >= 1 else { throw MediaForgeError.invalidSettings("Target size must be at least one byte.") }
        let totalKbps = bytes * 8 * 0.96 / duration / 1000
        let audio = hasAudio ? audioBitrateKbps : 0
        let video = totalKbps - Double(audio)
        guard video >= 16, video <= 200000 else { throw MediaForgeError.invalidSettings("Target size cannot accommodate the selected duration and audio bitrate.") }
        self.targetBytes = Int64(bytes)
        self.videoBitrateKbps = Int(video)
        self.audioBitrateKbps = audio
    }
}
