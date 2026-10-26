// Checks CloudSaves against remotecache.vdf records written to a temporary Steam folder: no record,
// a file still out of step, a record from before the game ended, and all in step after it:
// tests/CloudSavesTest/run.sh
import Foundation

@main
struct CloudSavesTest {
    static var failures = 0

    static func check(_ condition: Bool, _ message: String) {
        if !condition {
            failures += 1
            print("✗ " + message)
        }
    }

    static func record(_ states: [String]) -> String {
        let files = states.enumerated().map { index, state in
            "\t\"save\(index).sav\"\n\t{\n\t\t\"root\"\t\t\"0\"\n\t\t\"size\"\t\t\"10\"\n\t\t\"syncstate\"\t\t\"\(state)\"\n\t}\n"
        }.joined()
        return "\"570\"\n{\n\t\"ChangeNumber\"\t\t\"5\"\n\t\"OSType\"\t\t\"0\"\n\(files)}\n"
    }

    static func main() {
        let steam = FileManager.default.temporaryDirectory.appendingPathComponent("nightforge-cloud-test-\(getpid())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: steam) }
        let folder = steam.appendingPathComponent("userdata/12345/570", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("remotecache.vdf")

        check(CloudSaves.state(appID: 570, steamRoot: steam, endedAt: Date()) == .noCloud, "no record: saves stay on the Mac")

        let before = Date().addingTimeInterval(-60)
        try? record(["1", "2"]).write(to: file, atomically: true, encoding: .utf8)
        check(CloudSaves.state(appID: 570, steamRoot: steam, endedAt: before) == .syncing, "a file out of step: still syncing")

        try? record(["1", "1"]).write(to: file, atomically: true, encoding: .utf8)
        check(CloudSaves.state(appID: 570, steamRoot: steam, endedAt: before) == .synced, "all in step, recorded after the game ended: synced")
        check(CloudSaves.state(appID: 570, steamRoot: steam, endedAt: Date().addingTimeInterval(60)) == .syncing,
              "a record from before the game ended doesn't count yet")

        try? "\"570\"\n{\n\t\"ChangeNumber\"\t\t\"5\"\n}\n".write(to: file, atomically: true, encoding: .utf8)
        check(CloudSaves.state(appID: 570, steamRoot: steam, endedAt: before) == .noCloud, "a record without files: nothing in the cloud")

        // The record of the account that touched the game last.
        let other = steam.appendingPathComponent("userdata/0/570", isDirectory: true)
        try? FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        try? record(["1"]).write(to: other.appendingPathComponent("remotecache.vdf"), atomically: true, encoding: .utf8)
        check(CloudSaves.record(appID: 570, steamRoot: steam)?.path.contains("/userdata/0/") == true, "the newest account record wins")

        print(failures == 0 ? "✓ CloudSaves" : "\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
