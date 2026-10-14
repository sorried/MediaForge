import SwiftUI
import MediaForgeCore

@MainActor
struct NativeImageOptionsView: View {
    let profile: OutputProfile
    @Binding var options: NativeImageOptions
    var body: some View {
        if profile == .png || profile == .jpeg {
            Section(L("Изображения — ImageIO")) {
                Text(L("Для исходных изображений используется ImageIO: размеры задают вписывание с сохранением пропорций. Для видео экспортируется кадр через FFmpeg."))
                    .font(.caption).foregroundStyle(.secondary)
                if profile == .jpeg {
                    Text(L("Качество и фон ниже применяются только к исходным изображениям через ImageIO. При экспорте кадра из видео эти параметры не используются."))
                        .font(.caption).foregroundStyle(.secondary)
                    Slider(value: $options.quality, in: 0.1...1) {
                        Text(L("Качество JPEG"))
                    }
                    Text(L("Качество:") + " " + String(Int(options.quality * 100)) + "%")
                        .font(.caption).monospacedDigit()
                    Toggle(L("Чёрный фон прозрачных областей"), isOn: $options.blackBackground)
                    Text(L("Если выключено, прозрачные области JPEG заполняются белым."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}
