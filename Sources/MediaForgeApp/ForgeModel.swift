import AppKit
import Foundation
import MediaForgeCore
import Observation

@Observable
@MainActor
final class QueueEntry: Identifiable {
    let id: UUID
    let source: URL
    var profile: OutputProfile
    var conversionSettings: ConversionSettings
    var outputDirectory: URL?
    var imageOptions: NativeImageOptions?
    var imageInspection: ImageInspection?
    var status = QueueStatus.pending
    var metadata: MediaMetadata?
    var progress: Double?
    var progressDetail = ""
    var startedAt: Date?
    var sizeDeviation: Double?
    var output: URL?
    var error: String?
    var cancelling = false
    init(id: UUID = UUID(), source: URL, profile: OutputProfile, settings: ConversionSettings, imageOptions: NativeImageOptions? = nil, outputDirectory: URL? = nil) {
        self.id = id
        self.source = source
        self.profile = profile
        conversionSettings = settings
        self.imageOptions = imageOptions
        self.outputDirectory = outputDirectory
    }
}

extension QueueEntry {
    convenience init(saved: SavedQueueEntry) {
        self.init(id: saved.id, source: saved.source, profile: saved.profile, settings: saved.conversionSettings,
            imageOptions: saved.imageOptions, outputDirectory: saved.outputDirectory)
        status = saved.status
        error = saved.error
        output = saved.output
        if status == .completed { progress = 1 }
    }
    var saved: SavedQueueEntry {
        SavedQueueEntry(id: id, source: source, profile: profile, conversionSettings: conversionSettings,
            imageOptions: imageOptions, outputDirectory: outputDirectory, status: status, error: error, output: output)
    }
}

@Observable
@MainActor
final class ForgeModel {
    var settings = ForgeSettings()
    var history: [HistoryRecord] = []
    var presets: [SavedPreset] = []
    var queue: [QueueEntry] = []
    var selection: UUID?
    var profile = OutputProfile.mp4
    var draft = SettingsDraft()
    var imageOptions = NativeImageOptions()
    var alertMessage: String?
    var diagnostics: [String] = []
    var capabilitiesText = L("Проверка движка…")
    var engineReady = false
    var capabilities: FFmpegCapabilities?
    var importing = false
    var queueStarted = false
    var isTerminating = false
    private var persistenceEnabled = true
    private var prepared = false
    private var toolchain: FFmpegToolchain?
    private var tasks: [UUID: Task<Void, Never>] = [:]
    private var importTask: Task<Void, Never>?
    private var scanTask: Task<[URL], Error>?
    private var capabilityTask: Task<FFmpegCapabilities, Error>?
    private let store: StateStore
    private let suppliedToolchain: FFmpegToolchain?

    init(store: StateStore = StateStore(), toolchain: FFmpegToolchain? = nil) {
        self.store = store
        suppliedToolchain = toolchain
        do {
            let state = try store.load()
            settings = state.settings
            settings.simultaneousJobs = min(4, max(1, settings.simultaneousJobs))
            history = state.history
            presets = state.presets
            queue = state.queue.map { QueueEntry(saved: $0.recoveringInterruptedWork()) }
            selection = queue.first?.id
            if state.queue.contains(where: { $0.status == .running || $0.status == .probing }) { persist() }
        } catch {
            do {
                let backup = try store.quarantine()
                alertMessage = L("Не удалось прочитать сохранённые настройки. Исходный файл сохранён:") + "\n" + backup.path
            } catch {
                persistenceEnabled = false
                alertMessage = L("Не удалось прочитать настройки. Сохранение отключено, чтобы не потерять историю.") + "\n" + store.url.path
            }
        }
    }

    var selectedEntry: QueueEntry? { queue.first { $0.id == selection } }
    var activeCount: Int { tasks.count }

    func prepare() async {
        guard !isTerminating, !prepared else { return }
        prepared = true
        do {
            let found = try suppliedToolchain ?? FFmpegToolchain.discover()
            toolchain = found
            let worker = Task { try await found.capabilities() }
            capabilityTask = worker
            defer { capabilityTask = nil }
            let capabilities = try await withTaskCancellationHandler {
                try await worker.value
            } onCancel: { worker.cancel() }
            try Task.checkCancellation()
            guard !isTerminating else { return }
            self.capabilities = capabilities
            capabilitiesText = capabilities.version + "\n" + OutputProfile.allCases.map {
                $0.title + ": " + (capabilities.supports($0) ? capabilities.detail(for: $0) : L("Кодек недоступен"))
            }.joined(separator: "\n")
            engineReady = true
            log(L("Движок готов"))
        } catch is CancellationError {
            prepared = false
            engineReady = false
            capabilities = nil
        } catch {
            guard !isTerminating else { return }
            capabilitiesText = L("Движок недоступен") + "\n" + userError(error)
            log(error.localizedDescription)
            log(capabilitiesText)
        }
    }

    func persist() {
        if history.count > settings.historyLimit { history.removeLast(history.count - settings.historyLimit) }
        guard persistenceEnabled else { return }
        do { try store.save(PersistedState(settings: settings, history: history, presets: presets, queue: queue.map { $0.saved })) }
        catch { alertMessage = L("Не удалось сохранить настройки.") + "\n" + error.localizedDescription; log(error.localizedDescription) }
    }

    func log(_ message: String) {
        diagnostics.append(Date().formatted(date: .omitted, time: .standard) + "  " + message)
        if diagnostics.count > 1000 { diagnostics.removeFirst(diagnostics.count - 1000) }
    }

    func refreshEngine() async {
        guard !isTerminating, activeCount == 0, capabilityTask == nil else { return }
        prepared = false
        engineReady = false
        capabilities = nil
        await prepare()
    }

    func applyDraft(to entry: QueueEntry) {
        guard entry.status == .pending, !queueStarted else { return }
        do {
            guard capabilities?.supports(profile) == true else { throw DraftError.invalid(L("Кодек для выбранного формата недоступен.")) }
            let parameters = try draft.settings(for: profile)
            _ = try capabilities?.composition(for: profile, preference: parameters.videoEncoderPreference)
            entry.conversionSettings = parameters
            entry.profile = profile
            entry.imageOptions = profile.isImage ? imageOptions : nil
            persist()
        } catch { alertMessage = userError(error) }
    }

    func probe(_ entry: QueueEntry) {
        guard !isTerminating, tasks.count < settings.simultaneousJobs, let toolchain, entry.status == .pending, tasks[entry.id] == nil else { return }
        entry.status = .probing
        persist()
        tasks[entry.id] = Task { [weak self] in
            guard let self else { return }
            defer {
                self.tasks[entry.id] = nil
                self.schedule()
            }
            do {
                if isImageSource(entry.source) {
                    let source = entry.source
                    let worker = Task.detached {
                        try Task.checkCancellation()
                        let inspection = try ImageConverter().inspect(source)
                        try Task.checkCancellation()
                        return inspection
                    }
                    entry.imageInspection = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
                    try Task.checkCancellation()
                } else {
                    entry.metadata = try await MediaProbe(toolchain: toolchain).inspect(entry.source)
                }
                entry.status = .pending
            } catch is CancellationError { entry.status = .cancelled }
            catch { entry.status = .failed; entry.error = userError(error); self.log(error.localizedDescription) }
            entry.cancelling = false
            self.persist()
        }
    }

    func chooseInput() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.message = L("Выберите файлы или папки. Оригиналы не изменяются.")
        if panel.runModal() == .OK { importURLs(panel.urls) }
    }

    func chooseOutput() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.directoryURL = settings.outputDirectory
        if panel.runModal() == .OK, let chosen = panel.url {
            settings.outputDirectory = chosen
            persist()
        }
    }

    func chooseOutput(for entry: QueueEntry) {
        guard !isTerminating, entry.status == .pending else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.directoryURL = entry.outputDirectory ?? settings.outputDirectory
        if panel.runModal() == .OK, let directory = panel.url { entry.outputDirectory = directory; persist() }
    }

    func importURLs(_ urls: [URL]) {
        guard !isTerminating else { return }
        guard !importing else { alertMessage = L("Дождитесь завершения импорта."); return }
        do {
            let snapshot = try draft.settings(for: profile)
            if let capabilities { _ = try capabilities.composition(for: profile, preference: snapshot.videoEncoderPreference) }
            let chosenProfile = profile
            let chosenImageOptions = imageOptions
            let chosenDirectory = settings.outputDirectory
            let recursive = settings.recursiveImport
            let excludedSources = Set(queue.map { $0.source.standardizedFileURL })
            let importLimit = max(0, 10000 - queue.count)
            importing = true
            importTask = Task {
                defer { importing = false; importTask = nil; scanTask = nil }
                do {
                    try Task.checkCancellation()
                    let scanner = Task.detached(priority: .userInitiated) {
                        try scanImports(urls, recursive: recursive, limit: importLimit, excluding: excludedSources)
                    }
                    scanTask = scanner
                    let candidates = try await withTaskCancellationHandler {
                        try await scanner.value
                    } onCancel: { scanner.cancel() }
                    try Task.checkCancellation()
                    let existing = Set(queue.map { $0.source.standardizedFileURL })
                    let unique = Set(candidates).subtracting(existing).sorted { $0.path < $1.path }
                    guard queue.count + unique.count <= 10000 else { throw DraftError.invalid(L("Очередь ограничена 10000 задачами. Удалите ненужные задачи перед импортом.")) }
                    if !unique.isEmpty { pauseForQueueChanges() }
                    queue.append(contentsOf: unique.map { QueueEntry(source: $0, profile: chosenProfile, settings: snapshot, imageOptions: chosenProfile.isImage ? chosenImageOptions : nil, outputDirectory: chosenDirectory) })
                    if selection == nil { selection = queue.first?.id }
                    log(L("Добавлено файлов:") + " " + String(unique.count))
                    persist()
                } catch is CancellationError { log(L("Импорт отменён")) }
                catch { alertMessage = userError(error); log(error.localizedDescription) }
            }
        } catch { alertMessage = userError(error) }
    }

    func waitForImport() async {
        await importTask?.value
    }

    func startQueue() {
        guard !isTerminating else { return }
        guard engineReady else { alertMessage = L("Встроенный движок недоступен. Переустановите приложение или проверьте журнал."); return }
        let pending = queue.filter { $0.status == .pending }
        guard !pending.isEmpty else { return }
        guard pending.allSatisfy({ capabilities?.supports($0.profile) == true }) else { alertMessage = L("В очереди есть формат с недоступным кодеком."); return }
        if pending.contains(where: { $0.profile.isImage }) {
            let warning = NSAlert()
            warning.messageText = L("Проверьте потери при экспорте изображения")
            warning.informativeText = L("Экспорт создаёт один статичный кадр: анимация и дополнительные страницы теряются. ImageIO удаляет метаданные камеры и геолокации, преобразует цвет в 8-битный sRGB: HDR и широкий цветовой охват могут измениться. JPEG сжимает с потерями и заменяет прозрачность выбранным фоном. Оригиналы останутся без изменений.")
            warning.addButton(withTitle: L("Продолжить"))
            warning.addButton(withTitle: L("Отмена"))
            guard warning.runModal() == .alertFirstButtonReturn else { return }
        }
        if pending.contains(where: { !$0.profile.isImage && !$0.profile.isAudio && isImageSource($0.source) }) {
            let warning = NSAlert()
            warning.messageText = L("Экспорт изображения в видео")
            warning.informativeText = L("Видеокодек не сохраняет прозрачность. Метаданные могут быть потеряны. Анимированный источник может сохранять движение; неподвижное изображение останется одним кадром. Оригиналы не изменяются.")
            warning.addButton(withTitle: L("Продолжить"))
            warning.addButton(withTitle: L("Отмена"))
            guard warning.runModal() == .alertFirstButtonReturn else { return }
        }
        queueStarted = true
        schedule()
    }

    func waitForQueue() async {
        while let task = tasks.values.first {
            await task.value
        }
    }

    private func schedule() {
        guard !isTerminating, queueStarted, let toolchain else { return }
        let limit = min(4, max(1, settings.simultaneousJobs))
        for entry in queue where entry.status == .pending && tasks.count < limit {
            entry.status = .probing
            persist()
            let directory = entry.outputDirectory ?? settings.outputDirectory
            tasks[entry.id] = Task { [weak self] in
                guard let self else { return }
                await self.execute(entry, directory: directory, toolchain: toolchain)
            }
        }
    }

    private func execute(_ entry: QueueEntry, directory: URL, toolchain: FFmpegToolchain) async {
        defer {
            tasks[entry.id] = nil
            schedule()
            if tasks.isEmpty && !queue.contains(where: { $0.status == .pending }) { queueStarted = false }
        }
        do {
            if (entry.profile == .png || entry.profile == .jpeg) && isImageSource(entry.source) {
                try await executeNativeImage(entry, directory: directory)
            } else {
                let metadata = try await MediaProbe(toolchain: toolchain).inspect(entry.source)
                try Task.checkCancellation()
                entry.metadata = metadata
                try entry.conversionSettings.validate(duration: metadata.duration, requiresEvenDimensions: !entry.profile.isImage)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let output = OutputManager.suggestedURL(input: entry.source, directory: directory, profile: entry.profile, reserved: Set(queue.compactMap { $0.output }))
                entry.output = output
                guard output.standardizedFileURL != entry.source.standardizedFileURL else { throw CocoaError(.fileWriteFileExists) }
                entry.status = .running
                entry.startedAt = Date()
                persist()
                let request = ConversionRequest(id: entry.id, inputURL: entry.source, outputURL: output, profile: entry.profile, settings: entry.conversionSettings)
                let entryID = entry.id
                let converted = try await ConversionEngine(toolchain: toolchain).convert(request, progress: { [weak self] update in
                    Task { @MainActor [weak self] in
                        guard let current = self?.queue.first(where: { $0.id == entryID }), current.status == .running else { return }
                        current.progress = update.fraction
                        current.progressDetail = String(format: "%.1f", update.processedSeconds) + " " + L("с") + (update.speed.map { " · " + $0 } ?? "")
                    }
                })
                entry.output = converted.outputURL
                entry.sizeDeviation = converted.targetSizeDeviationFraction
                entry.progress = 1
                entry.status = .completed
                log(L("Готово:") + " " + converted.outputURL.path)
            }
        } catch is CancellationError {
            entry.status = .cancelled
            log(L("Отменено:") + " " + entry.source.lastPathComponent)
        } catch {
            entry.status = .failed
            entry.error = userError(error)
            log(entry.source.lastPathComponent + ": " + error.localizedDescription)
        }
        entry.cancelling = false
        if entry.status != .completed { entry.output = nil }
        history.insert(HistoryRecord(id: UUID(), source: entry.source, output: entry.output, outputDirectory: entry.outputDirectory, profile: entry.profile, conversionSettings: entry.conversionSettings, imageOptions: entry.imageOptions, status: entry.status, finishedAt: Date(), message: entry.error), at: 0)
        if history.count > settings.historyLimit { history.removeLast(history.count - settings.historyLimit) }
        persist()
    }

    private func executeNativeImage(_ entry: QueueEntry, directory: URL) async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let output = OutputManager.suggestedURL(input: entry.source, directory: directory, profile: entry.profile, reserved: Set(queue.compactMap { $0.output }))
        entry.output = output
        let options = entry.imageOptions ?? NativeImageOptions()
        let request = ImageConversionRequest(inputURL: entry.source, outputURL: output, format: entry.profile == .png ? .png : .jpeg,
            maxWidth: entry.conversionSettings.width, maxHeight: entry.conversionSettings.height,
            quality: options.quality, allowDropAnimation: true,
            flattenColor: entry.profile == .jpeg ? (options.blackBackground ? .black : .white) : nil)
        entry.status = .running
        entry.startedAt = Date()
        persist()
        let worker = Task.detached(priority: .userInitiated) { try ImageConverter().convert(request) }
        let converted = try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: { worker.cancel() }
        entry.output = converted.outputURL
        entry.imageInspection = converted.inspection
        entry.status = .completed
        entry.progress = 1
        log(L("Готово:") + " " + converted.outputURL.path)
    }

    func cancel(_ entry: QueueEntry) {
        if let task = tasks[entry.id] { entry.cancelling = true; task.cancel() }
        else if entry.status == .pending {
            entry.status = .cancelled
            history.insert(HistoryRecord(id: UUID(), source: entry.source, output: nil, outputDirectory: entry.outputDirectory, profile: entry.profile, conversionSettings: entry.conversionSettings, imageOptions: entry.imageOptions, status: .cancelled, finishedAt: Date(), message: nil), at: 0)
            persist()
        }
    }
    private func pauseForQueueChanges() {
        if queueStarted {
            let message = L("Очередь приостановлена после добавления или повтора задач. Запущенные задачи продолжат работу. Нажмите «Начать», чтобы проверить параметры и продолжить ожидающие задачи.")
            alertMessage = message
            log(message)
        }
        queueStarted = false
    }

    func retry(_ entry: QueueEntry) {
        guard !isTerminating else { return }
        guard entry.status == .failed || entry.status == .cancelled, tasks[entry.id] == nil else { return }
        pauseForQueueChanges()
        entry.status = .pending; entry.error = nil; entry.progress = nil; entry.output = nil
        entry.progressDetail = ""
        entry.startedAt = nil
        entry.sizeDeviation = nil
        entry.metadata = nil
        entry.imageInspection = nil
        entry.cancelling = false
        persist()
    }
    func remove(_ entry: QueueEntry) {
        guard tasks[entry.id] == nil else { return }
        queue.removeAll { $0.id == entry.id }
        persist()
    }
    func cleanCompleted() { queue.removeAll { $0.status == .completed }; persist() }
    func repeatConversion(_ record: HistoryRecord) {
        guard !isTerminating else { return }
        guard queue.count < 10000 else { alertMessage = L("Очередь ограничена 10000 задачами."); return }
        pauseForQueueChanges()
        queue.append(QueueEntry(source: record.source, profile: record.profile, settings: record.conversionSettings, imageOptions: record.imageOptions, outputDirectory: record.outputDirectory ?? record.output?.deletingLastPathComponent() ?? settings.outputDirectory))
        persist()
    }
    func savePreset(name: String) {
        do {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw DraftError.invalid(L("Введите название пресета.")) }
            presets.append(SavedPreset(name: trimmed, profile: profile, settings: try draft.settings(for: profile), imageOptions: profile.isImage ? imageOptions : nil))
            persist()
        } catch { alertMessage = error.localizedDescription }
    }
    func updatePreset(_ id: UUID, name: String) {
        do {
            guard let index = presets.firstIndex(where: { $0.id == id }) else { return }
            let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { throw DraftError.invalid(L("Введите название пресета.")) }
            let parameters = try draft.settings(for: profile)
            presets[index].name = name
            presets[index].profile = profile
            presets[index].settings = parameters
            presets[index].imageOptions = profile.isImage ? imageOptions : nil
            persist()
        } catch { alertMessage = userError(error) }
    }

    func duplicatePreset(_ preset: SavedPreset) {
        presets.append(SavedPreset(name: preset.name + " · " + L("Копия"), profile: preset.profile, settings: preset.settings, imageOptions: preset.imageOptions))
        persist()
    }

    func applyPreset(_ preset: SavedPreset) { profile = preset.profile; draft = SettingsDraft(settings: preset.settings); imageOptions = preset.imageOptions ?? NativeImageOptions() }
    func cancelAndWait() async {
        isTerminating = true
        queueStarted = false
        let checking = capabilityTask
        checking?.cancel()
        let scanning = scanTask
        let importing = importTask
        let running = Array(tasks.values)
        scanning?.cancel()
        importing?.cancel()
        for task in running { task.cancel() }
        if let importing { await importing.value }
        for task in running { await task.value }
        if let checking { _ = await checking.result }
        engineReady = false
        persist()
    }

    func exportDiagnostics() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "MediaForge-diagnostics.txt"
        if panel.runModal() == .OK, let url = panel.url {
            do { try (capabilitiesText + "\n\n" + diagnostics.joined(separator: "\n")).write(to: url, atomically: true, encoding: .utf8) }
            catch { alertMessage = error.localizedDescription }
        }
    }
}
