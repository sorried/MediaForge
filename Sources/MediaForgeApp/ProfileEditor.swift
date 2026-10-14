import SwiftUI
import MediaForgeCore

@MainActor
struct ProfileEditor: View {
    @Binding var profile: OutputProfile
    @Binding var draft: SettingsDraft
    var capabilities: FFmpegCapabilities?

    private var validationMessage: String? {
        do {
            let settings = try draft.settings(for: profile)
            if let capabilities { _ = try capabilities.composition(for: profile, preference: settings.videoEncoderPreference) }
            return nil
        }
        catch { return userError(error) }
    }

    var body: some View {
        Section(L("Формат и параметры")) {
            Picker(L("Формат"), selection: $profile) {
                ForEach(OutputProfile.allCases) { profile in
                    Text(profile.title + (capabilities?.supports(profile) == true ? "" : " · " + L("Недоступен"))).tag(profile)
                        .disabled(capabilities?.supports(profile) != true)
                }
            }
            if let composition = try? capabilities?.composition(for: profile, preference: draft.videoEncoder) {
                Text([composition.videoCodec, composition.audioCodec].compactMap { $0 }.joined(separator: " / ") + " · " + composition.muxer)
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text(L("Пустые поля используют настройки движка. Видео и аудио перекодируются."))
                .font(.caption).foregroundStyle(.secondary)
            if !profile.isImage {
                TextField(L("Начало, с"), text: $draft.trimStart)
                TextField(L("Конец, с"), text: $draft.trimEnd)
            }
            if !profile.isAudio {
                TextField(L("Ширина, px"), text: $draft.width)
                TextField(L("Высота, px"), text: $draft.height)
            }
            if !profile.isAudio && !profile.isImage {
                Toggle(L("Сохранять пропорции (поля при необходимости)"), isOn: $draft.preserveAspectRatio)
                TextField(L("Частота кадров, кадр/с"), text: $draft.frameRate)
                TextField(L("Битрейт видео, кбит/с"), text: $draft.videoBitrate)
                Toggle(L("Удалить аудио"), isOn: $draft.removeAudio)
                if profile == .mp4 || profile == .mov {
                    TextField(L("Целевой размер, МБ"), text: $draft.targetSize)
                    Text(L("Размер приблизительный: один проход, 1 МБ = 1 000 000 байт. Итоговое отклонение отображается после конвертации."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Picker(L("Видеокодировщик"), selection: $draft.videoEncoder) {
                    Text(L("Автоматически")).tag(VideoEncoderPreference.automatic)
                    Text(L("Программный")).tag(VideoEncoderPreference.software)
                        .disabled((try? capabilities?.composition(for: profile, preference: .software)) == nil)
                    Text(L("Аппаратный VideoToolbox")).tag(VideoEncoderPreference.hardware)
                        .disabled((try? capabilities?.composition(for: profile, preference: .hardware)) == nil)
                }
            }
            if ([.mp3, .m4a, .aac, .ogg, .opus].contains(profile) || (!profile.isAudio && !profile.isImage && profile != .avi)) && !(!profile.isAudio && !profile.isImage && draft.removeAudio) {
                TextField(L("Битрейт аудио, кбит/с"), text: $draft.audioBitrate)
            }
            if !profile.isImage && !(!profile.isAudio && draft.removeAudio) {
                TextField(L("Частота дискретизации, Гц"), text: $draft.sampleRate)
                TextField(L("Каналы: 1 — моно, 2 — стерео"), text: $draft.channels)
            }
            if profile.isImage {
                Label(L("Один кадр; метаданные и анимация могут быть потеряны. JPEG удаляет прозрачность."), systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }
            if let validationMessage {
                Label(validationMessage, systemImage: "exclamationmark.circle")
                    .foregroundStyle(.red).font(.caption)
            }
        }
    }
}
