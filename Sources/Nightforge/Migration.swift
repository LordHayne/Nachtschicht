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
        if fm.fileExists(atPath: oldSupport.path) {
            stopSession(in: oldSupport)
            // Same volume, so these are renames. If one fails, try again on the next start.
            guard moveContents(of: oldSupport, into: Engine.supportDir) else { return }
        }

        let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let oldCaches = caches.appendingPathComponent(oldName, isDirectory: true)
        let newCaches = caches.appendingPathComponent("Nightforge", isDirectory: true)
        if fm.fileExists(atPath: oldCaches.path) && !fm.fileExists(atPath: newCaches.path) {
            try? fm.moveItem(at: oldCaches, to: newCaches)
        }
        defaults.set(true, forKey: doneKey)
    }

    /// Moves `old` to `new`. When `new` exists already (a start whose move failed goes on to create
    /// it, e.g. for the component list), whatever it lacks still comes over – above all the prefix
    /// with Steam and the games – instead of being left behind for good. False when a move failed.
    private static func moveContents(of old: URL, into new: URL) -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: new.path) else { return (try? fm.moveItem(at: old, to: new)) != nil }
        for item in (try? fm.contentsOfDirectory(at: old, includingPropertiesForKeys: nil)) ?? [] {
            let target = new.appendingPathComponent(item.lastPathComponent)
            guard !fm.fileExists(atPath: target.path) else { continue }  // the new copy wins
            guard (try? fm.moveItem(at: item, to: target)) != nil else { return false }
        }
        return true
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
