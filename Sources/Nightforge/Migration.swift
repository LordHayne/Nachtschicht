import Foundation

/// Nightforge used to be called Nachtschicht. On the first start under the new name its settings,
/// its Windows environment (Steam and the games, often tens of GB – moved, not copied) and its
/// caches come over, so nothing has to be set up or downloaded again.
enum LegacyMigration {
    private static let oldName = "Nachtschicht"
    private static let oldDefaultsDomain = "local.thomas.nachtschicht"
    private static let doneKey = "migratedFromNachtschicht"

    static func run() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: doneKey) else { return }
        let fm = FileManager.default

        if let old = defaults.persistentDomain(forName: oldDefaultsDomain) {
            for (key, value) in old where defaults.object(forKey: key) == nil {
                defaults.set(value, forKey: key)
            }
        }

        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let oldSupport = support.appendingPathComponent(oldName, isDirectory: true)
        if fm.fileExists(atPath: oldSupport.path) && !fm.fileExists(atPath: Engine.supportDir.path) {
            stopSession(in: oldSupport)
            // Same volume, so this is a rename. If it fails, try again on the next start.
            guard (try? fm.moveItem(at: oldSupport, to: Engine.supportDir)) != nil else { return }
        }

        let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let oldCaches = caches.appendingPathComponent(oldName, isDirectory: true)
        let newCaches = caches.appendingPathComponent("Nightforge", isDirectory: true)
        if fm.fileExists(atPath: oldCaches.path) && !fm.fileExists(atPath: newCaches.path) {
            try? fm.moveItem(at: oldCaches, to: newCaches)
        }
        defaults.set(true, forKey: doneKey)
    }

    /// Steam and Wine still running from the old folder would keep using paths that are about to
    /// disappear, so the old session ends first (its quit script included).
    private static func stopSession(in folder: URL) {
        let fm = FileManager.default
        let engines = folder.appendingPathComponent("Components/wine", isDirectory: true)
        for version in (try? fm.contentsOfDirectory(at: engines, includingPropertiesForKeys: nil)) ?? [] {
            guard let wine = Engine.wineBinary(in: version) else { continue }
            let server = Process()
            server.executableURL = wine.deletingLastPathComponent().appendingPathComponent("wineserver")
            server.arguments = ["-k"]
            server.environment = ["WINEPREFIX": folder.appendingPathComponent("Prefix").path]
            if (try? server.run()) != nil { server.waitUntilExit() }
        }
        let quitScript = Process()
        quitScript.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        quitScript.arguments = ["-f", folder.appendingPathComponent("steam-shutdown.sh").path]
        if (try? quitScript.run()) != nil { quitScript.waitUntilExit() }
        for process in Engine.ownProcesses(under: folder) { kill(process.pid, SIGKILL) }
    }
}
