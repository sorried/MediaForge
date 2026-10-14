import Foundation
import MediaForgeCore

struct BuiltInPreset: Identifiable {
    let id: String
    let preset: SavedPreset
    var requiresH264 = false

    func unavailableReason(capabilities: FFmpegCapabilities?) -> String? {
        guard let capabilities else { return L("Движок ещё не проверен") }
        guard capabilities.supports(preset.profile) else { return L("Нужный кодек или контейнер отсутствует") }
        if requiresH264 && !capabilities.encoders.contains("h264_videotoolbox") {
            return L("Для универсального MP4 нужен H.264; доступен только MPEG-4 Part 2")
        }
        return nil
    }

    static var all: [BuiltInPreset] {
        var presets = [
            BuiltInPreset(id: "universal", preset: SavedPreset(name: L("Универсальный MP4"), profile: .mp4, settings: .init(videoBitrateKbps: 4000, audioBitrateKbps: 192, videoEncoderPreference: .hardware)), requiresH264: true),
            BuiltInPreset(id: "small", preset: SavedPreset(name: L("Компактное видео"), profile: .mp4, settings: .init(width: 854, height: 480, videoBitrateKbps: 1000, audioBitrateKbps: 96))),
            BuiltInPreset(id: "quality", preset: SavedPreset(name: L("Высокое качество"), profile: .mp4, settings: .init(videoBitrateKbps: 10000, audioBitrateKbps: 256))),
            BuiltInPreset(id: "extract", preset: SavedPreset(name: L("Извлечь аудио"), profile: .m4a, settings: .init(audioBitrateKbps: 192))),
            BuiltInPreset(id: "mp3", preset: SavedPreset(name: L("Аудио MP3"), profile: .mp3, settings: .init(audioBitrateKbps: 192))),
            BuiltInPreset(id: "m4a", preset: SavedPreset(name: L("Аудио M4A"), profile: .m4a, settings: .init(audioBitrateKbps: 192))),
            BuiltInPreset(id: "lossless", preset: SavedPreset(name: L("Аудио без потерь — FLAC"), profile: .flac, settings: .init())),
            BuiltInPreset(id: "image", preset: SavedPreset(name: L("Изображение — вписать в 1920 px"), profile: .png, settings: .init(width: 1920, height: 1920))),
            BuiltInPreset(id: "jpeg", preset: SavedPreset(name: L("Изображение JPEG"), profile: .jpeg, settings: .init(), imageOptions: NativeImageOptions())),
            BuiltInPreset(id: "png", preset: SavedPreset(name: L("Изображение PNG"), profile: .png, settings: .init())),
            BuiltInPreset(id: "gif-video", preset: SavedPreset(name: L("GIF → MP4"), profile: .mp4, settings: .init(removeAudio: true)))
        ]
        if let webp = OutputProfile(rawValue: "webp") {
            presets.insert(BuiltInPreset(id: "webp", preset: SavedPreset(name: L("Изображение WebP"), profile: webp, settings: .init())), at: 8)
        }
        return presets
    }
}
