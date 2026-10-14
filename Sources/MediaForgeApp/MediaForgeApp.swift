import AppKit
import SwiftUI

@main
@MainActor
struct MediaForgeApp: App {
    @State private var model = ForgeModel()
    @NSApplicationDelegateAdaptor(ForgeAppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup {
            ForgeWindow(model: model)
                .preferredColorScheme(model.settings.theme.colorScheme)
                .frame(minWidth: 760, minHeight: 560)
                .task { delegate.model = model; await model.prepare() }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(L("Добавить файлы…")) { model.chooseInput() }
                    .keyboardShortcut("o")
            }
        }
        Settings {
            ForgeSettingsView(model: model)
                .preferredColorScheme(model.settings.theme.colorScheme)
        }
    }
}
