import Foundation

/// Steam's browser processes (steamwebhelper under Wine, "Steam Helper" for Steam for Mac) keep
/// running behind every game, and run from the game bundle they even share its Game Mode priority.
/// While a game runs they go into macOS's background state – efficiency cores, throttled disk – so
/// the game has the performance cores to itself. Only the browser: Steam's main process talks to
/// the game and starts it, and a process it started would inherit the background state.
enum SteamPriority {
    private static let windowsHelpers = ["steamwebhelper"]
    private static let macHelpers = ["/Steam.AppBundle/Steam/Contents/Frameworks/Steam Helper.app/"]

    /// Follows the running game in a small detached script (Nightforge usually quits right after a
    /// launch), which puts Steam's browser back once the game has ended.
    static func watch(_ game: Game) {
        let pattern = game.platform == .mac
            ? game.installDir.path + "/"
            : "\\steamapps\\common\\\(game.installDirName)\\"
        let helpers = game.platform == .mac ? macHelpers : windowsHelpers
        let script = Engine.supportDir.appendingPathComponent("steam-priority.sh")
        let text = #"""
        #!/bin/bash
        # Written by Nightforge when a game starts: while it runs, Steam's browser processes wait on
        # the efficiency cores. Ends with the game and puts them back.
        PIDFILE="$1"; GAME="$2"; shift 2
        HELPERS=(); for helper in "$@"; do HELPERS+=(-e "$helper"); done
        # One at a time: this game takes over from one that has just ended. Only if that PID still is
        # this script: after a restart or a crash it can belong to anything.
        OLD="$(cat "$PIDFILE" 2>/dev/null)"
        [ -n "$OLD" ] && ps -p "$OLD" -o command= 2>/dev/null | grep -qF steam-priority.sh && kill "$OLD" 2>/dev/null
        echo $$ > "$PIDFILE"
        # -F: Windows paths are full of backslashes; game processes live under steamapps and never count as Steam.
        helpers() { printf '%s\n' "$1" | grep -iF "${HELPERS[@]}" | grep -viF steamapps; }
        absent=0
        while [ $absent -lt 2 ]; do      # a launcher handing over to the game leaves a short gap
          list="$(ps -axo pid=,pri=,command=)"
          # Not this script, whose own command line names the game's folder too.
          if printf '%s\n' "$list" | grep -iF -- "$GAME" | grep -viqF -e crashhandler -e "$0"; then
            absent=0
            # Priority 4 is the background state; only new helpers need it.
            helpers "$list" | awk '$2 != 4 { print $1 }' | while read -r pid; do taskpolicy -b -p "$pid" 2>/dev/null; done
          else
            absent=$((absent + 1))
          fi
          sleep 10
        done
        helpers "$(ps -axo pid=,pri=,command=)" | awk '{ print $1 }' | while read -r pid; do taskpolicy -B -p "$pid" 2>/dev/null; done
        [ "$(cat "$PIDFILE" 2>/dev/null)" = "$$" ] && rm -f "$PIDFILE"
        """#
        guard (try? text.write(to: script, atomically: true, encoding: .utf8)) != nil else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [script.path, Engine.supportDir.appendingPathComponent("steam-priority.pid").path, pattern] + helpers
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()  // keeps running after Nightforge has quit
    }
}
