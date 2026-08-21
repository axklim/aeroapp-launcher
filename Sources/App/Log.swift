import Foundation

enum Log {
    /// The daemon logs through NSLog — under `brew services` stderr is the log
    /// file, and a bare `./build.sh` run prints to the terminal. The CLI prints
    /// plain lines to stderr instead; timestamps and pids are noise there.
    static var plain = false
}

func log(_ message: String) {
    if Log.plain {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    } else {
        NSLog("AeroAppLauncher: %@", message)
    }
}
