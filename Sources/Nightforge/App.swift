import AppKit
import SwiftUI
import UserNotifications

@main
struct NightforgeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = LibraryModel()
    /// Views read strings through L10n, so the window content is rebuilt when this changes.
    @AppStorage(AppLanguage.storageKey) private var language = AppLanguage.system.rawValue

    init() {
        LegacyMigration.run()  // before anything reads settings or the data folder
    }

    var body: some Scene {
        Window("Nightforge", id: "main") {
            LibraryView()
                .id(language)
                .environmentObject(model)
                .modifier(ReduceMotionFromSettings())
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

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        GameDisplay.follow()
        MacIntegration.setUp(delegate: self)
    }

    /// Right-click on the Dock icon: the last games played, one click to play.
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        MacIntegration.dockMenu(target: self, action: #selector(playFromDock(_:)))
    }

    @MainActor @objc private func playFromDock(_ item: NSMenuItem) {
        MacIntegration.open(id: item.representedObject as? String, play: true)
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        MacIntegration.handle(response)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        Engine.scheduleSteamShutdown()
        GameDisplay.quitting()
    }
}
