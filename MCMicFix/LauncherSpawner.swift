import Foundation
import AppKit

enum LauncherSpawnError: LocalizedError {
    case missingExecutable(URL)
    case spawnFailed(String)
    case stillRunning(String)

    var errorDescription: String? {
        switch self {
        case .missingExecutable(let url):
            return "Executable not found: \(url.path)"
        case .spawnFailed(let message):
            return message
        case .stillRunning(let name):
            return "\(name) is still running. Quit it completely, then try again."
        }
    }
}

/// Spawns launcher binaries while keeping MC Mic Fix as the macOS TCC
/// *responsible process* so the microphone grant applies to Minecraft/Java.
@MainActor
final class LauncherSpawner {
    /// Live Process objects keyed by pid (kept so terminationHandler stays valid).
    private var processes: [Int32: Process] = [:]

    var childPIDs: Set<Int32> { Set(processes.keys) }

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

        // Abort if an instance is still running (by bundle id) — never spawn over it.
        if Self.isAppRunning(bundleIdentifier: launcher.bundleIdentifier, appURL: launcher.appURL) {
            throw LauncherSpawnError.stillRunning(launcher.displayName)
        }

        reapFinished()

        let process = Process()
        process.executableURL = exe
        process.arguments = []
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser

        var env = ProcessInfo.processInfo.environment
        if javaOptionsEnabled, let flags = preset.jvmFlags, !flags.isEmpty {
            env["_JAVA_OPTIONS"] = flags
            env["JDK_JAVA_OPTIONS"] = flags
        } else {
            env.removeValue(forKey: "_JAVA_OPTIONS")
            env.removeValue(forKey: "JDK_JAVA_OPTIONS")
        }
        process.environment = env

        process.terminationHandler = { @Sendable [weak self] proc in
            let pid = proc.processIdentifier
            Task { @MainActor in
                self?.processes.removeValue(forKey: pid)
            }
        }

        do {
            try process.run()
            processes[process.processIdentifier] = process
        } catch {
            throw LauncherSpawnError.spawnFailed(error.localizedDescription)
        }
    }

    private func reapFinished() {
        processes = processes.filter { _, proc in proc.isRunning }
    }

    /// True if this pid is one we spawned and it is still running.
    func isOurChild(pid: Int32) -> Bool {
        guard let proc = processes[pid] else { return false }
        return proc.isRunning
    }

    /// Activate an already-running child / instance (no respawn).
    static func activateRunning(bundleIdentifier: String?, appURL: URL) {
        let apps = matchingApps(bundleIdentifier: bundleIdentifier, appURL: appURL)
        for app in apps {
            app.activate(options: [.activateAllWindows])
        }
    }

    // MARK: - Running-app helpers (bundleIdentifier-first)

    static func isAppRunning(bundleIdentifier: String?, appURL: URL) -> Bool {
        !matchingApps(bundleIdentifier: bundleIdentifier, appURL: appURL).isEmpty
    }

    static func matchingApps(bundleIdentifier: String?, appURL: URL) -> [NSRunningApplication] {
        let running = NSWorkspace.shared.runningApplications
        if let bid = bundleIdentifier, !bid.isEmpty {
            let byID = running.filter { $0.bundleIdentifier == bid }
            if !byID.isEmpty { return byID }
        }
        // Fallback for Other… picks without a reliable bundle id.
        return running.filter {
            $0.bundleURL?.standardizedFileURL == appURL.standardizedFileURL
        }
    }

    static func terminateRunning(bundleIdentifier: String?, appURL: URL) {
        for app in matchingApps(bundleIdentifier: bundleIdentifier, appURL: appURL) {
            app.terminate()
        }
    }

    static func forceTerminateRunning(bundleIdentifier: String?, appURL: URL) {
        for app in matchingApps(bundleIdentifier: bundleIdentifier, appURL: appURL) {
            app.forceTerminate()
        }
    }

    /// Wait until matching apps have exited, or timeout. Returns true if clear.
    static func waitUntilExited(
        bundleIdentifier: String?,
        appURL: URL,
        timeoutSeconds: TimeInterval = 10
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            let still = matchingApps(bundleIdentifier: bundleIdentifier, appURL: appURL)
            if still.isEmpty || still.allSatisfy(\.isTerminated) {
                // Brief settle so LaunchServices releases the single-instance lock.
                try? await Task.sleep(nanoseconds: 150_000_000)
                if matchingApps(bundleIdentifier: bundleIdentifier, appURL: appURL).isEmpty {
                    return true
                }
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return matchingApps(bundleIdentifier: bundleIdentifier, appURL: appURL).isEmpty
    }
}
