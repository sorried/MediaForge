import SwiftUI
import MediaForgeCore

@MainActor
struct PresetsView: View {
    @Bindable var model: ForgeModel
    @State private var editingID: UUID?
    @State private var name = ""

    var body: some View {
        HSplitView {
            List {
                Section(L("Встроенные")) {
                    ForEach(BuiltInPreset.all) { template in
                        VStack(alignment: .leading) {
                            Button(template.preset.name) {
                                editingID = nil; name = template.preset.name; model.applyPreset(template.preset)
                            }.disabled(template.unavailableReason(capabilities: model.capabilities) != nil)
                            if let reason = template.unavailableReason(capabilities: model.capabilities) {
                                Text(reason).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    Button(L("Свой пресет…")) { editingID = nil; name = ""; model.draft = SettingsDraft() }
                }
                Section(L("Пользовательские")) {
                    ForEach(model.presets) { preset in
                        HStack {
                            Button(preset.name) { editingID = preset.id; name = preset.name; model.applyPreset(preset) }
                            Spacer()
                            Menu {
                                Button(L("Дублировать")) { model.duplicatePreset(preset) }
                                Button(L("Удалить"), role: .destructive) {
                                    model.presets.removeAll { $0.id == preset.id }; model.persist()
                                    if editingID == preset.id { editingID = nil }
                                }
                            } label: { Image(systemName: "ellipsis") }
                            .accessibilityLabel(L("Действия с пресетом") + " " + preset.name)
                        }
                    }
                }
            }.frame(minWidth: 240)
            Form {
                Section(L("Редактор пресета")) {
                    TextField(L("Название"), text: $name)
                    Button(L("Новый пресет")) { editingID = nil; name = ""; model.draft = SettingsDraft() }
                }
                ProfileEditor(profile: $model.profile, draft: $model.draft, capabilities: model.capabilities)
                NativeImageOptionsView(profile: model.profile, options: $model.imageOptions)
                Section {
                    if let editingID {
                        Button(L("Сохранить изменения")) { model.updatePreset(editingID, name: name) }
                    }
                    Button(L("Сохранить как новый")) { model.savePreset(name: name) }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Text(L("Выбранный пресет применяется к новым файлам."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.formStyle(.grouped).frame(minWidth: 280)
        }
    }
}
