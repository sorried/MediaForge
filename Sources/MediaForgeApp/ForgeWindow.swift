import AppKit
import SwiftUI

@MainActor
struct ForgeWindow: View {
    @Bindable var model: ForgeModel
    @State private var page: String? = "convert"
    @State private var presetName = ""
    @State private var dropTargeted = false

    var body: some View {
        NavigationSplitView {
            List(selection: $page) {
                Label(L("Конвертация"), systemImage: "arrow.triangle.2.circlepath").tag("convert")
                Label(L("Очередь"), systemImage: "list.bullet.rectangle").tag("queue")
                Label(L("Пресеты"), systemImage: "slider.horizontal.3").tag("presets")
                Label(L("Настройки"), systemImage: "gearshape").tag("settings")
                Label(L("История"), systemImage: "clock").tag("history")
                Label(L("Диагностика"), systemImage: "wrench.and.screwdriver").tag("diagnostics")
            }
            .navigationSplitViewColumnWidth(min: 150, ideal: 170, max: 220)
        } detail: {
            Group {
                switch page {
                case "convert": conversionView
                case "presets": PresetsView(model: model)
                case "settings": ForgeSettingsView(model: model)
                case "history": historyView
                case "diagnostics": diagnosticsView
                default: queueView
                }
            }
            .navigationTitle("Media Forge")
            .toolbar {
                ToolbarItemGroup {
                    Button { model.chooseInput() } label: { Label(L("Добавить"), systemImage: "plus") }
                    Button { model.startQueue() } label: { Label(L("Начать"), systemImage: "play.fill") }
                        .disabled(!model.engineReady || model.queueStarted || model.importing || !model.queue.contains { $0.status == .pending })
                }
            }
        }
        .alert(L("Media Forge"), isPresented: Binding(get: { model.alertMessage != nil }, set: { if !$0 { model.alertMessage = nil } })) {
            Button(L("OK"), role: .cancel) { model.alertMessage = nil }
        } message: { Text(model.alertMessage ?? "") }
    }

    private var conversionView: some View {
        Form {
            Section(L("Исходные файлы")) {
                Button(L("Добавить файлы или папки…")) { model.chooseInput() }.disabled(model.importing)
                Toggle(L("Включать вложенные папки"), isOn: $model.settings.recursiveImport)
                    .onChange(of: model.settings.recursiveImport) { _, _ in model.persist() }
                Text(L("Параметры применяются при добавлении файлов в очередь."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            ProfileEditor(profile: $model.profile, draft: $model.draft, capabilities: model.capabilities)
                NativeImageOptionsView(profile: model.profile, options: $model.imageOptions)
            Section(L("Результат")) {
                Text(model.settings.outputDirectory.path).textSelection(.enabled)
                Button(L("Выбрать папку…")) { model.chooseOutput() }
                Button(L("Начать конвертацию")) { model.startQueue(); page = "queue" }
                    .disabled(!model.engineReady || model.queueStarted || model.importing || !model.queue.contains { $0.status == .pending })
            }
        }.formStyle(.grouped).padding()
    }

    private var queueView: some View {
        HSplitView {
            VStack(spacing: 0) {
                HStack {
                    Text(L("Очередь") + " · " + String(model.queue.count)).font(.headline)
                    Spacer()
                    Button(L("Очистить готовые")) { model.cleanCompleted() }
                        .disabled(!model.queue.contains { $0.status == .completed })
                }.padding()
                if model.queue.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "square.and.arrow.down").font(.largeTitle).foregroundStyle(.secondary)
                        Text(L("Перетащите файлы или папки сюда")).font(.headline)
                        Button(L("Выбрать файлы…")) { model.chooseInput() }
                        Text(L("Оригиналы не изменяются")).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(model.queue, selection: $model.selection) { entry in
                        QueueRow(entry: entry).tag(entry.id)
                            .contextMenu { entryActions(entry) }
                    }
                }
                Divider()
                HStack {
                    VStack(alignment: .leading) {
                        Text(L("Активных:") + " " + String(model.activeCount))
                        if !model.queueStarted && model.queue.contains(where: { $0.status == .pending }) {
                            Text(L("Ожидающие задачи приостановлены. Нажмите «Начать»."))
                        }
                        if model.importing { Text(L("Импорт файлов…")) }
                    }
                    Spacer()
                    Text(model.engineReady ? L("Движок готов") : L("Движок недоступен"))
                        .foregroundStyle(model.engineReady ? Color.secondary : Color.red)
                }.font(.caption).padding(12)
            }
            .frame(minWidth: 280)
            .background(dropTargeted ? Color.accentColor.opacity(0.12) : Color.clear)
            .dropDestination(for: URL.self) { urls, _ in
                guard urls.contains(where: { $0.isFileURL }) else { return false }
                model.importURLs(urls)
                return true
            } isTargeted: { dropTargeted = $0 }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Form {
                        ProfileEditor(profile: $model.profile, draft: $model.draft, capabilities: model.capabilities)
                NativeImageOptionsView(profile: model.profile, options: $model.imageOptions)
                        Section(L("Назначение")) {
                            Text(model.settings.outputDirectory.path).font(.caption).textSelection(.enabled)
                            Button(L("Выбрать папку…")) { model.chooseOutput() }
                            Toggle(L("Включать вложенные папки"), isOn: $model.settings.recursiveImport)
                                .onChange(of: model.settings.recursiveImport) { _, _ in model.persist() }
                        }
                        Section(L("Пресеты")) {
                            ForEach(model.presets) { preset in
                                HStack {
                                    Button(preset.name) { model.applyPreset(preset) }
                                    Spacer()
                                    Button { model.presets.removeAll { $0.id == preset.id }; model.persist() } label: {
                                        Image(systemName: "trash")
                                    }.accessibilityLabel(L("Удалить пресет") + " " + preset.name)
                                }
                            }
                            TextField(L("Название пресета"), text: $presetName)
                            Button(L("Сохранить пресет")) { model.savePreset(name: presetName) }
                                .disabled(presetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }.formStyle(.grouped)
                    Text(L("Параметры выше применяются к новым файлам. Для выбранного файла используйте кнопку ниже."))
                        .font(.caption).foregroundStyle(.secondary)
                    if let entry = model.selectedEntry {
                        Text(entry.source.lastPathComponent).font(.headline)
                        Text(entry.source.path).font(.caption).textSelection(.enabled)
                        Text(L("Формат:") + " " + entry.profile.title)
                        Text(L("Папка этой задачи:") + " " + (entry.outputDirectory ?? model.settings.outputDirectory).path)
                            .font(.caption).textSelection(.enabled)
                        Button(L("Изменить папку этой задачи…")) { model.chooseOutput(for: entry) }
                            .disabled(entry.status != .pending)
                        Button(L("Применить параметры к выбранному")) { model.applyDraft(to: entry) }
                            .disabled(entry.status != .pending || model.queueStarted)
                        entryActions(entry)
                        if let image = entry.imageInspection {
                            Text(L("Изображение:") + " " + String(image.width) + " × " + String(image.height))
                            Text(L("Кадров:") + " " + String(image.frameCount))
                            Text(image.hasAlpha ? L("Есть альфа-канал") : L("Без альфа-канала"))
                        }
                        if let metadata = entry.metadata { MetadataView(metadata: metadata) }
                        else {
                            Button(L("Анализировать файл")) { model.probe(entry) }
                                .disabled(!model.engineReady || entry.status != .pending || model.queueStarted)
                        }
                        if let deviation = entry.sizeDeviation {
                            Text(L("Отклонение от целевого размера:") + " " + String(format: "%+.1f%%", deviation * 100)).font(.caption)
                        }
                        if let error = entry.error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
                    }
                }.padding()
            }.frame(minWidth: 260, idealWidth: 330, maxWidth: 450)
        }
    }

    @ViewBuilder private func entryActions(_ entry: QueueEntry) -> some View {
        if entry.status == .running || entry.status == .probing || entry.status == .pending {
            Button(entry.cancelling ? L("Отмена…") : L("Отменить")) { model.cancel(entry) }.disabled(entry.cancelling)
        }
        if entry.status == .failed || entry.status == .cancelled {
            Button(L("Повторить")) { model.retry(entry) }
        }
        if entry.status != .running && entry.status != .probing {
            Button(L("Удалить из очереди")) { model.remove(entry) }
        }
        if let output = entry.output { OutputActions(url: output) }
        Button(L("Показать оригинал в Finder")) { NSWorkspace.shared.activateFileViewerSelecting([entry.source]) }
    }

    private var historyView: some View {
        VStack {
            HStack {
                Text(L("Лимит истории:") + " " + String(model.settings.historyLimit)).foregroundStyle(.secondary)
                Spacer()
                Button(L("Очистить историю")) { model.history.removeAll(); model.persist() }.disabled(model.history.isEmpty)
            }.padding()
            List(model.history) { record in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(record.source.lastPathComponent).font(.headline)
                        Spacer()
                        Text(record.status.title)
                    }
                    Text(record.finishedAt.formatted() + " · " + record.profile.title).font(.caption).foregroundStyle(.secondary)
                    if let message = record.message { Text(message).foregroundStyle(.red).textSelection(.enabled) }
                    HStack {
                        Button(L("Повторить конвертацию")) { model.repeatConversion(record); page = "queue" }
                        if let output = record.output { OutputActions(url: output) }
                    }
                }.padding(.vertical, 4)
            }
        }
    }

    private var diagnosticsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L("Движок и журнал")).font(.title2)
                Spacer()
                Button(L("Проверить снова")) { Task { await model.refreshEngine() } }.disabled(model.activeCount > 0)
                Button(L("Экспортировать журнал…")) { model.exportDiagnostics() }
            }
            ScrollView {
                Text(model.capabilitiesText + "\n\n" + model.diagnostics.joined(separator: "\n"))
                    .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text(L("Приложение использует FFmpeg по LGPLv2.1 или более поздней версии. Соответствующие исходники и лицензия включены в приложение."))
                .font(.caption).textSelection(.enabled)
            HStack {
                if let website = URL(string: "https://ffmpeg.org/") {
                    Link("FFmpeg", destination: website)
                }
                if let resources = Bundle.main.resourceURL {
                    Button(L("Исходники и лицензии движка")) {
                        NSWorkspace.shared.open(resources.appendingPathComponent("Licenses/FFmpeg", isDirectory: true))
                    }
                }
            }
            Text(L("Журнал содержит имена и пути файлов. Проверьте его перед отправкой."))
                .font(.caption).foregroundStyle(.secondary)
        }.padding()
    }
}

@MainActor
private struct QueueRow: View {
    @Bindable var entry: QueueEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(entry.source.lastPathComponent).lineLimit(1)
                Spacer()
                Text(entry.profile.title).font(.caption).foregroundStyle(.secondary)
            }
            Text(entry.cancelling ? L("Отмена…") : entry.status.title)
                .font(.caption).foregroundStyle(entry.status == .failed ? Color.red : Color.secondary)
            if entry.status == .running {
                if let progress = entry.progress { ProgressView(value: min(1, max(0, progress))) }
                else { ProgressView() }
                Text(entry.progressDetail).font(.caption).monospacedDigit()
                if let startedAt = entry.startedAt {
                    TimelineView(.periodic(from: startedAt, by: 1)) { context in
                        let elapsed = max(0, context.date.timeIntervalSince(startedAt))
                        HStack {
                            Text(L("Прошло:") + " " + String(Int(elapsed)) + " " + L("с"))
                            if let fraction = entry.progress, fraction > 0.02, fraction < 1 {
                                Text(L("Осталось примерно:") + " " + String(Int(elapsed * (1 - fraction) / fraction)) + " " + L("с"))
                            }
                        }.font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
            }
        }.padding(.vertical, 5)
    }
}

@MainActor
struct OutputActions: View {
    let url: URL
    var body: some View {
        Button(L("Открыть")) { NSWorkspace.shared.open(url) }
            .disabled(!FileManager.default.fileExists(atPath: url.path))
        Button(L("Показать в Finder")) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            .disabled(!FileManager.default.fileExists(atPath: url.path))
    }
}
