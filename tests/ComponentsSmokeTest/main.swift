// Offline smoke test for ComponentStore: no network, only file:// components in a temp folder.
// Run with tests/ComponentsSmokeTest/run.sh

import Foundation

func check(_ condition: Bool, _ message: String) {
    if condition {
        print("✓ \(message)")
    } else {
        print("✗ \(message)")
        exit(1)
    }
}

let fm = FileManager.default
let work = fm.temporaryDirectory.appendingPathComponent("nightforge-smoke-\(UUID().uuidString)", isDirectory: true)
let payload = work.appendingPathComponent("payload", isDirectory: true)
try fm.createDirectory(at: payload.appendingPathComponent("bin"), withIntermediateDirectories: true)
try "hello".write(to: payload.appendingPathComponent("bin/wine"), atomically: true, encoding: .utf8)
defer { try? fm.removeItem(at: work) }

let archive = work.appendingPathComponent("engine-1.0.tar.gz")
let tar = Process()
tar.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
tar.arguments = ["-czf", archive.path, "-C", payload.path, "."]
try tar.run()
tar.waitUntilExit()

let script = work.appendingPathComponent("winetricks")
try "#!/bin/sh\necho ok\n".write(to: script, atomically: true, encoding: .utf8)

func component(_ id: String, _ kind: Component.Kind, _ file: URL, sha: String? = nil) throws -> Component {
    let size = (try fm.attributesOfItem(atPath: file.path)[.size] as? Int64) ?? 0
    return Component(id: id, kind: kind, version: "1.0", url: file,
                     sha256: try sha ?? ComponentStore.sha256(of: file), size: size,
                     license: "LGPL-2.1-or-later", source: URL(string: "https://example.invalid")!)
}

let store = ComponentStore(root: work.appendingPathComponent("store"), remoteManifestURL: nil,
                           bundledManifestURL: URL(fileURLWithPath: "components/manifest.json"))

// The real manifest decodes and lists the engine.
let manifest = try await store.manifest()
check(manifest.component("wine") != nil, "bundled manifest decodes (\(manifest.components.count) components)")

// Archive: downloaded, verified, unpacked.
let engine = try component("engine", .engine, archive)
let reported = ProgressBox()
let dir = try await store.install(engine) { reported.value = $0 }
check(fm.fileExists(atPath: dir.appendingPathComponent("bin/wine").path), "archive unpacked to \(dir.lastPathComponent)/bin/wine")
check(reported.value == 1, "progress reaches 100 %")
check(await store.installedPath(for: engine) == dir, "installed version is recognised")

// Second install is a no-op.
let again = try await store.install(engine)
check(again == dir, "reinstall returns the existing folder")

// Single file (winetricks): copied and made executable.
let tool = try component("winetricks", .tool, script)
let toolDir = try await store.install(tool)
let mode = (try fm.attributesOfItem(atPath: toolDir.appendingPathComponent("winetricks").path)[.posixPermissions] as? Int) ?? 0
check(mode & 0o111 != 0, "single-file tool is executable")

// Wrong checksum is refused and leaves nothing behind.
let broken = try component("broken", .engine, archive, sha: String(repeating: "0", count: 64))
do {
    _ = try await store.install(broken)
    check(false, "checksum mismatch is refused")
} catch ComponentError.checksumMismatch {
    check(await store.installedPath(for: broken) == nil, "checksum mismatch is refused and not installed")
}

print("All component checks passed.")

final class ProgressBox: @unchecked Sendable {
    var value = 0.0
}
