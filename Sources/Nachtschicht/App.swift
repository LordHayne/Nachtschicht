import AppKit
import SwiftUI

@main
struct NachtschichtApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = LibraryModel()
    /// Views read strings through L10n, so the window content is rebuilt when this changes.
    @AppStorage(AppLanguage.storageKey) private var language = AppLanguage.system.rawValue

    var body: some Scene {
        Window("Nachtschicht", id: "main") {
            LibraryView()
                .id(language)
                .environmentObject(model)
                .frame(minWidth: 980, minHeight: 640)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1440, height: 880)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(L10n.t("Rescan Library")) { model.reload() }
                    .keyboardShortcut("r")
            }
        }

        Settings {
            SettingsView()
                .id(language)
                .environmentObject(model)
                .preferredColorScheme(.dark)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
