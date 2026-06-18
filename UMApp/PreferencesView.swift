import SwiftUI
import AppKit

struct PreferencesView: View {
    @AppStorage("projectsDirectory") private var storedPath: String = ""

    private var displayPath: String {
        let raw = storedPath.isEmpty
            ? AppController.defaultProjectsDirectory.path
            : storedPath
        return (raw as NSString).abbreviatingWithTildeInPath
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Projects folder") {
                    HStack(spacing: 8) {
                        Text(displayPath)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                            .font(.system(size: 12, design: .monospaced))
                            .frame(maxWidth: 260, alignment: .leading)
                        Button("Choose…") { chooseDirectory() }
                        if !storedPath.isEmpty {
                            Button("Reset") { storedPath = "" }
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } footer: {
                Text("New documents open their save panel in this folder. Existing documents always save to their own file location.")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 11))
            }
        }
        .formStyle(.grouped)
        .frame(width: 500, height: 130)
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.title = "Choose Projects Folder"
        panel.message = "Select the default folder for new UM projects"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        if !storedPath.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: storedPath, isDirectory: true)
        }
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in storedPath = url.path }
        }
    }
}
