import SwiftUI

@main
struct UMApp: App {
    @State private var controller = AppController()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(controller)
                .navigationTitle(controller.documentTitle)
        }
        .defaultSize(width: 1200, height: 800)
        .commands {
            // Undo / Redo — replaces the do-nothing SwiftUI built-ins
            CommandGroup(replacing: .undoRedo) {
                Button("Undo") { controller.engine.undo() }
                    .keyboardShortcut("z", modifiers: .command)
                    .disabled(!controller.engine.canUndo)
                Button("Redo") { controller.engine.redo() }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                    .disabled(!controller.engine.canRedo)
            }
            // Help menu
            CommandGroup(replacing: .help) {
                HelpMenuButton()
            }
            // File operations — replaces the built-in "New Window" entry
            CommandGroup(replacing: .newItem) {
                Button("New")      { controller.newDocument() }
                    .keyboardShortcut("n", modifiers: .command)
                Button("Open…")    { controller.openDocument() }
                    .keyboardShortcut("o", modifiers: .command)
                Divider()
                Button("Save")     { controller.saveDocument() }
                    .keyboardShortcut("s", modifiers: .command)
                Button("Save As…") { controller.saveDocumentAs() }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
            }
        }

        // Help window — opened via Help menu or ⌘/
        Window("UM Help", id: "umhelp") {
            HelpView()
        }
        .defaultSize(width: 840, height: 620)

        // Preferences window — adds "Preferences…" + Cmd+, to the app menu automatically
        Settings {
            PreferencesView()
        }
    }
}
