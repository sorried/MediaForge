import Foundation
import MediaForgeCore

struct SettingsDraft {
    var trimStart = ""
    var trimEnd = ""
    var width = ""
    var height = ""
    var videoBitrate = ""
    var audioBitrate = ""
    var frameRate = ""
    var removeAudio = false
    var preserveAspectRatio = true
    var sampleRate = ""
    var channels = ""
    var targetSize = ""
    var videoEncoder = VideoEncoderPreference.automatic

    init() {}
    init(settings: ConversionSettings) {
        trimStart = settings.trimStart.map { String($0) } ?? ""
        trimEnd = settings.trimEnd.map { String($0) } ?? ""
        width = settings.width.map { String($0) } ?? ""
        height = settings.height.map { String($0) } ?? ""
        videoBitrate = settings.videoBitrateKbps.map { String($0) } ?? ""
        audioBitrate = settings.audioBitrateKbps.map { String($0) } ?? ""
        frameRate = settings.frameRate.map { String($0) } ?? ""
        removeAudio = settings.removeAudio
        preserveAspectRatio = settings.preserveAspectRatio
        sampleRate = settings.sampleRate.map { String($0) } ?? ""
        channels = settings.channels.map { String($0) } ?? ""
        targetSize = settings.targetSizeMB.map { String($0) } ?? ""
        videoEncoder = settings.videoEncoderPreference
    }

    func settings(for profile: OutputProfile) throws -> ConversionSettings {
        let video = !profile.isAudio && !profile.isImage
        let lossyAudio = [.mp3, .m4a, .aac, .ogg, .opus].contains(profile) || (video && profile != .avi)
        let settings = ConversionSettings(
            trimStart: profile.isImage ? nil : try number(trimStart, label: L("Начало")),
            trimEnd: profile.isImage ? nil : try number(trimEnd, label: L("Конец")),
            width: profile.isAudio ? nil : try integer(width, label: L("Ширина")),
            height: profile.isAudio ? nil : try integer(height, label: L("Высота")),
            videoBitrateKbps: video ? try integer(videoBitrate, label: L("Битрейт видео")) : nil,
            audioBitrateKbps: lossyAudio && !(video && removeAudio) ? try integer(audioBitrate, label: L("Битрейт аудио")) : nil,
            frameRate: video ? try number(frameRate, label: L("Частота кадров")) : nil,
            removeAudio: video && removeAudio,
            sampleRate: !profile.isImage && !(video && removeAudio) ? try integer(sampleRate, label: L("Частота дискретизации")) : nil,
            channels: !profile.isImage && !(video && removeAudio) ? try integer(channels, label: L("Каналы")) : nil,
            targetSizeMB: profile == .mp4 || profile == .mov ? try number(targetSize, label: L("Целевой размер")) : nil,
            videoEncoderPreference: video ? videoEncoder : .automatic,
            preserveAspectRatio: video ? preserveAspectRatio : true)
        if settings.targetSizeMB != nil && settings.videoBitrateKbps != nil { throw DraftError.invalid(L("Укажите целевой размер или битрейт видео, но не оба сразу.")) }
        do { try settings.validate(requiresEvenDimensions: !profile.isImage) }
        catch { throw DraftError.invalid(userError(error)) }
        return settings
    }

    private func number(_ text: String, label: String) throws -> Double? {
        let text = text.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        guard let value = Double(text.replacingOccurrences(of: ",", with: ".")), value.isFinite else {
            throw DraftError.invalid(label + ": " + L("введите число или оставьте поле пустым."))
        }
        return value
    }
    private func integer(_ text: String, label: String) throws -> Int? {
        let text = text.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        guard let value = Int(text) else { throw DraftError.invalid(label + ": " + L("введите целое число.")) }
        return value
    }
}

enum DraftError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { switch self { case .invalid(let message): message } }
}
