import Foundation

/// Controllers for older Mac versions. Games from before Apple's GameController framework read
/// gamepads straight from HID and only know the ones they have a profile for – usually the Xbox
/// 360 pad. A DualSense or Xbox Series pad stays dead in them: macOS switches these into their
/// extended report mode, whose values such a game can't read. macOS 27 has the cure built in: an
/// app whose "GCSyntheticDevice" preference is true sees every controller as an Xbox 360 pad
/// (AppleSyntheticGameController.plugin, inside the game's own process). Games that use the
/// GameController framework (or a modern SDL, which builds on it) see controllers already, and
/// would see them twice with it – they are left alone.
enum ControllerCompatibility {
    static let key = "GCSyntheticDevice"

    /// Before a Mac version starts: switches the synthetic pad on for every app in its install
    /// folder that reads controllers the old way. A value the player set stays.
    static func prepare(installDir: URL) {
        for app in apps(in: installDir) {
            guard let info = Bundle(url: app)?.infoDictionary,
                  let bundleID = info["CFBundleIdentifier"] as? String,
                  CFPreferencesCopyAppValue(key as CFString, bundleID as CFString) == nil,
                  needsSyntheticPad(app) else { continue }
            CFPreferencesSetAppValue(key as CFString, kCFBooleanTrue, bundleID as CFString)
            CFPreferencesAppSynchronize(bundleID as CFString)
        }
    }

    /// The apps a Steam game folder holds: at its top or one folder down.
    static func apps(in folder: URL) -> [URL] {
        let fm = FileManager.default
        let top = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        return top.flatMap { item -> [URL] in
            if item.pathExtension == "app" { return [item] }
            guard (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return [] }
            return ((try? fm.contentsOfDirectory(at: item, includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.pathExtension == "app" }
        }
    }

    /// True when neither the app's program nor a library it ships links the GameController framework.
    static func needsSyntheticPad(_ app: URL) -> Bool {
        guard let program = Bundle(url: app)?.executableURL else { return false }
        return !([program] + bundledLibraries(app)).contains { links($0, "GameController.framework") }
    }

    private static func bundledLibraries(_ app: URL) -> [URL] {
        let frameworks = app.appendingPathComponent("Contents/Frameworks", isDirectory: true)
        let items = (try? FileManager.default.contentsOfDirectory(at: frameworks, includingPropertiesForKeys: nil)) ?? []
        return items.compactMap { item in
            switch item.pathExtension {
            case "dylib": return item
            case "framework": return item.appendingPathComponent(item.deletingPathExtension().lastPathComponent)
            default: return nil
            }
        }
    }

    /// Whether a Mach-O file's load commands (any slice of a universal file) name `library`.
    static func links(_ file: URL, _ library: String) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return false }
        defer { try? handle.close() }
        func read(_ offset: UInt64, _ count: Int) -> Data? {
            guard (try? handle.seek(toOffset: offset)) != nil, let data = try? handle.read(upToCount: count),
                  data.count == count else { return nil }
            return data
        }
        func word(_ data: Data, _ at: Int, bigEndian: Bool) -> UInt32 {
            let value = data.subdata(in: at..<at + 4).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
            return bigEndian ? UInt32(bigEndian: value) : UInt32(littleEndian: value)
        }
        guard let head = read(0, 8) else { return false }
        var slices: [UInt64] = [0]
        switch word(head, 0, bigEndian: true) {
        case 0xCAFEBABE, 0xCAFEBABF:  // universal: fat_arch is 20 bytes, fat_arch_64 32
            let wide = word(head, 0, bigEndian: true) == 0xCAFEBABF
            let count = Int(min(word(head, 4, bigEndian: true), 16))
            let size = wide ? 32 : 20
            guard let table = read(8, count * size) else { return false }
            slices = (0..<count).map { i in
                wide ? UInt64(word(table, i * size + 8, bigEndian: true)) << 32 | UInt64(word(table, i * size + 12, bigEndian: true))
                     : UInt64(word(table, i * size + 8, bigEndian: true))
            }
        default: break
        }
        let needle = Data(library.utf8)
        return slices.contains { offset in
            guard let header = read(offset, 28) else { return false }
            let magic = word(header, 0, bigEndian: false)
            guard magic == 0xFEEDFACF || magic == 0xFEEDFACE else { return false }
            let commandsSize = Int(min(word(header, 20, bigEndian: false), 4 << 20))
            let start = offset + (magic == 0xFEEDFACF ? 32 : 28)
            return read(start, commandsSize)?.range(of: needle) != nil
        }
    }
}
