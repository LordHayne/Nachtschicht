// Checks UpdateState: when an installed game has an update waiting, how big it is, and when Steam
// is applying it (from the manifest's StateFlags and bytes): tests/UpdateStateTest/run.sh
import Foundation

@main
struct UpdateStateTest {
    static var failures = 0

    static func check(_ condition: Bool, _ message: String) {
        if !condition {
            failures += 1
            print("✗ " + message)
        }
    }

    static func main() {
        // As on this Mac: Palworld fully installed, the bytes of its last download both equal.
        let installed = UpdateState(flags: 4, toDownload: 31_755_444_704, downloaded: 31_755_444_704, targetBuild: "25246127", build: "25246127")
        check(installed.pending == nil && !installed.isRunning, "fully installed: nothing waits")
        // Steamworks Common Redist here: flags 6, size not known yet.
        let unknown = UpdateState(flags: 6, toDownload: 0, downloaded: 0, targetBuild: "24098430", build: "24098430")
        check(unknown.pending == 0, "update required, size not known yet: 0")
        let sized = UpdateState(flags: 6, toDownload: 1_200_000_000, downloaded: 200_000_000)
        check(sized.pending == 1_000_000_000, "what's left of the update: \(sized.pending ?? -1)")
        let newBuild = UpdateState(flags: 4, toDownload: 0, downloaded: 0, targetBuild: "26220470", build: "26220464")
        check(newBuild.pending == 0, "heading for another build counts as waiting")
        check(UpdateState(flags: 4, toDownload: 0, downloaded: 0, targetBuild: "0", build: "26220464").pending == nil, "build 0 means none")
        let running = UpdateState(flags: 1026, toDownload: 1_000, downloaded: 250)
        check(running.isRunning && running.fraction == 0.25, "update started: running, a quarter done")
        check(UpdateState(flags: 4 | 1_048_576, toDownload: 0, downloaded: 0).isRunning && UpdateState(flags: 4 | 1_048_576, toDownload: 0, downloaded: 0).fraction == nil,
              "downloading without sizes: running, no percentage")
        check(UpdateState(flags: 1024, toDownload: 100, downloaded: 100).fraction == 0.99, "never shows 100 % before it's done")

        print(failures == 0 ? "✓ UpdateState" : "\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
