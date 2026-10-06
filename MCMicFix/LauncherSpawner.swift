import Foundation
import AppKit

enum LauncherSpawnError: LocalizedError {
    case missingExecutable(URL)
    case spawnFailed(String)
    case alreadyRunning

    var errorDescription: String? {
        switch self {
        case .missingExecutable(let url):
            return "Executable not found: \(url.path)"
        case .spawnFailed(let message):
            return message
        case .alreadyRunning:
            return "That launcher is already running."
        }
    }
}

/// Spawns launcher binaries while keeping MC Mic Fix as the macOS TCC
/// *responsible process* so the microphone grant applies to Minecraft/Java.
@MainActor
final class LauncherSpawner {
    /// PIDs we started (and any still-running children we track).
    private(set) var childPIDs: Set<Int32> = []

    /*
     RESPONSIBILITY / TCC — READ BEFORE CHANGING THIS FILE

     macOS TCC attributes microphone access to the "responsible process."
     Child processes inherit that responsibility unless spawn attrs disclaim it.

     We MUST launch launcher Mach-O binaries with Foundation.Process (posix_spawn
     under the hood) and MUST NOT call responsibility_spawnattrs_setdisclaim.

     NEVER use NSWorkspace.openApplication or `/usr/bin/open` for launchers.
     Those go through LaunchServices → launchd parents the app → the launcher
     becomes self-responsible again → official Minecraft has no mic usage string
     / audio-input entitlement → proximity chat breaks.

     Treat every launcher the same (Minecraft, Prism, Modrinth, CurseForge, …):
     always Process-spawn their Contents/MacOS executable.
     */

    func launch(
        launcher: DetectedLauncher,
        javaOptionsEnabled: Bool,
        preset: JavaOptionsPreset
    ) throws {
        let exe = launcher.executableURL
        guard FileManager.default.isExecutableFile(atPath: exe.path) else {
            throw LauncherSpawnError.missingExecutable(exe)
        }

        // Reap finished children from our set.
        childPIDs = Set(childPIDs.filter { kill($0, 0) == 0 })

        let process = Process()
        process.executableURL = exe
        process.arguments = []
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser

        var env = ProcessInfo.processInfo.environment
        if javaOptionsEnabled, let flags = preset.jvmFlags, !flags.isEmpty {
            // Optional / legacy only — not required for the mic fix.
            env["_JAVA_OPTIONS"] = flags
            env["JDK_JAVA_OPTIONS"] = flags
        } else {
            // Do not inherit a stale parent value into the child.
            env.removeValue(forKey: "_JAVA_OPTIONS")
            env.removeValue(forKey: "JDK_JAVA_OPTIONS")
        }
        process.environment = env

        process.terminationHandler = { [weak self] proc in
            let pid = proc.processIdentifier
            Task { @MainActor in
                self?.childPIDs.remove(pid)
            }
        }

        do {
            try process.run()
            childPIDs.insert(process.processIdentifier)
        } catch {
            throw LauncherSpawnError.spawnFailed(error.localizedDescription)
        }
    }

    // MARK: - Running-app helpers (for quit-and-relaunch prompt)

    static func isAppRunning(bundleURL: URL) -> Bool {
        let running = NSWorkspace.shared.runningApplications
        return running.contains { app in
            app.bundleURL?.standardizedFileURL == bundleURL.standardizedFileURL
        }
    }

    static func terminateRunning(bundleURL: URL) {
        let matches = NSWorkspace.shared.runningApplications.filter {
            $0.bundleURL?.standardizedFileURL == bundleURL.standardizedFileURL
        }
        for app in matches {
            app.terminate()
        }
    }

    var childPIDsSnapshot: Set<Int32> { childPIDs }
}
