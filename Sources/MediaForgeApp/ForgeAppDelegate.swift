import AppKit

@MainActor
final class ForgeAppDelegate: NSObject, NSApplicationDelegate {
    weak var model: ForgeModel?
    private var terminating = false

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model else { return .terminateNow }
        guard !terminating else { return .terminateLater }
        if model.activeCount > 0 || model.importing {
            let alert = NSAlert()
            alert.messageText = L("Завершить работу?")
            alert.informativeText = L("Активные задачи будут отменены. Приложение дождётся завершения движка и удаления временных файлов.")
            alert.addButton(withTitle: L("Отменить задачи и выйти"))
            alert.addButton(withTitle: L("Остаться"))
            guard alert.runModal() == .alertFirstButtonReturn else { return .terminateCancel }
        }
        terminating = true
        Task {
            await model.cancelAndWait()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
