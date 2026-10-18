import AppKit
import OrbitKit
import SwiftUI
import UniformTypeIdentifiers

/// Sections inserted into the New File module's detail screen.
struct NewFileSettingsView: View {
    @State private var model = NewFileSettingsModel()

    var body: some View {
        Section {
            ForEach(FileTemplate.builtIn) { template in
                Toggle(isOn: isEnabled(template)) {
                    HStack(spacing: 10) {
                        FileTypeIcon(fileExtension: template.fileExtension)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(template.name)
                            Text(verbatim: ".\(template.fileExtension)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        } header: {
            Text("File Types")
        } footer: {
            if model.settings.enabledTemplates.isEmpty {
                Text("Turn on at least one file type to see New File in Finder.")
                    .foregroundStyle(.secondary)
            }
        }

        Section {
            Picker("Finder Menu", selection: $model.settings.menuStyle) {
                Text("Submenu").tag(NewFileSettings.MenuStyle.submenu)
                Text("Separate Items").tag(NewFileSettings.MenuStyle.inline)
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } header: {
            Text("Finder Menu")
        } footer: {
            Group {
                switch model.settings.menuStyle {
                case .submenu: Text("File types are grouped in the “New File” submenu.")
                case .inline: Text("Each file type is a separate item, such as “New Text File”.")
                }
            }
            .foregroundStyle(.secondary)
        }

        Section {
            TextField("File Name", text: $model.settings.baseName, prompt: Text(verbatim: NewFileSettings.defaultBaseName))
        } footer: {
            Text("New files are named “\(model.settings.resolvedBaseName).txt”, “\(model.settings.resolvedBaseName) 2.txt” and so on.")
                .foregroundStyle(.secondary)
        }
    }

    private func isEnabled(_ template: FileTemplate) -> Binding<Bool> {
        Binding(
            get: { model.settings.isEnabled(template) },
            set: { model.settings.setEnabled($0, for: template) }
        )
    }
}

@MainActor @Observable
private final class NewFileSettingsModel {
    var settings: NewFileSettings {
        didSet {
            if settings != oldValue { store.newFile = settings }
        }
    }

    @ObservationIgnored private let store: SettingsStore

    init(store: SettingsStore = .shared) {
        self.store = store
        settings = store.newFile
    }
}

/// The icon Finder shows for files of this type.
private struct FileTypeIcon: View {
    let fileExtension: String

    var body: some View {
        Image(nsImage: NSWorkspace.shared.icon(for: UTType(filenameExtension: fileExtension) ?? .data))
            .resizable()
            .frame(width: 28, height: 28)
            .accessibilityHidden(true)
    }
}
