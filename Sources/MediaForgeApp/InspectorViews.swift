import SwiftUI
import MediaForgeCore

struct MetadataView: View {
    let metadata: MediaMetadata
    var body: some View {
        GroupBox(L("Информация о файле")) {
            VStack(alignment: .leading, spacing: 8) {
                Text(L("Контейнер:") + " " + metadata.formatName)
                Text(L("Размер:") + " " + ByteCountFormatter.string(fromByteCount: metadata.size, countStyle: .file))
                if let duration = metadata.duration { Text(L("Длительность:") + " " + String(format: "%.2f", duration) + " " + L("с")) }
                if let bitrate = metadata.bitrate, bitrate > 0 {
                    Text(L("Битрейт:") + " " + String(bitrate / 1000) + " " + L("кбит/с"))
                }
                ForEach(metadata.streams, id: \.index) { stream in
                    VStack(alignment: .leading) {
                        Text((stream.codecType == "audio" ? L("Аудио") : stream.codecType == "video" ? L("Видео") : stream.codecType) + " · " + (stream.codecName ?? L("Неизвестный кодек")))
                        if let width = stream.width, let height = stream.height { Text(String(width) + " × " + String(height)) }
                        if let frameRate = stream.frameRate, frameRate.isFinite, frameRate > 0 {
                            Text(L("Частота кадров:") + " " + String(format: "%.3f", frameRate) + " " + L("кадр/с"))
                        }
                        if let rate = stream.sampleRate { Text(String(rate) + " " + L("Гц")) }
                        if let channels = stream.channels { Text(L("Каналов:") + " " + String(channels)) }
                    }
                }
            }.font(.caption).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
        }
    }
}

@MainActor
struct ForgeSettingsView: View {
    @Bindable var model: ForgeModel
    var body: some View {
        Form {
            Section(L("Общие")) {
                Picker(L("Оформление"), selection: $model.settings.theme) {
                    ForEach(AppTheme.allCases, id: \.self) { theme in Text(theme.title).tag(theme) }
                }
                Stepper(L("Одновременных задач:") + " " + String(model.settings.simultaneousJobs), value: $model.settings.simultaneousJobs, in: 1...4)
                Toggle(L("Включать вложенные папки"), isOn: $model.settings.recursiveImport)
                Stepper(L("Записей в истории:") + " " + String(model.settings.historyLimit), value: $model.settings.historyLimit, in: 0...10000, step: 100)
            }
            Section(L("Папка результатов")) {
                Text(model.settings.outputDirectory.path).textSelection(.enabled)
                Button(L("Выбрать папку…")) { model.chooseOutput() }
                Text(L("Приложение не запрашивает права администратора или полный доступ к диску."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped).padding().frame(width: 480, height: 340)
        .onChange(of: model.settings.theme) { _, _ in model.persist() }
        .onChange(of: model.settings.simultaneousJobs) { _, _ in model.persist() }
        .onChange(of: model.settings.recursiveImport) { _, _ in model.persist() }
        .onChange(of: model.settings.historyLimit) { _, _ in model.persist() }
    }
}
