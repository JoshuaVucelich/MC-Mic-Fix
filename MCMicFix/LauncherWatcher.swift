import Foundation
import Darwin
import AppKit

/// Watches for launchers opened outside MC Mic Fix (Dock / Finder / open).
@MainActor
final class LauncherWatcher {
    var onForeignLaunch: ((DetectedLauncher) -> Void)?

    private var observer: NSObjectProtocol?
    private var catalogProvider: (() -> LauncherCatalog)?
    private var isEnabled: (() -> Bool)?
    private var ourChildPIDs: (() -> Set<Int32>)?
    private var recentSelfLaunchUntil: Date = .distantPast

    func start(
        catalog: LauncherCatalog,
        isEnabled: @escaping () -> Bool,
        ourChildPIDs: @escaping () -> Set<Int32>
    ) {
        stop()
        self.catalogProvider = { catalog }
        self.isEnabled = isEnabled
        self.ourChildPIDs = ourChildPIDs

        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }
            let pid = app.processIdentifier
            let bundleURL = app.bundleURL
            let bundleID = app.bundleIdentifier
            Task { @MainActor in
                self?.handleLaunch(pid: pid, bundleURL: bundleURL, bundleIdentifier: bundleID)
            }
        }
    }

    func stop() {
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            self.observer = nil
        }
    }

    func markSelfLaunch() {
        recentSelfLaunchUntil = Date().addingTimeInterval(2.0)
    }

    private func handleLaunch(pid: Int32, bundleURL: URL?, bundleIdentifier: String?) {
        guard isEnabled?() == true else { return }
        if bundleIdentifier == Bundle.main.bundleIdentifier { return }

        if ourChildPIDs?().contains(pid) == true { return }
        if Date() < recentSelfLaunchUntil { return }

        // If we are anywhere in the parent chain, this is our spawn (or a re-exec
        // of it) — do not treat as foreign / autoRelaunch loop.
        if isAncestor(of: pid, candidate: ProcessInfo.processInfo.processIdentifier) {
            return
        }

        guard let bundleURL else { return }
        guard let catalog = catalogProvider?() else { return }

        let match = catalog.launchers.first { launcher in
            launcher.appURL.standardizedFileURL == bundleURL.standardizedFileURL
                || (launcher.bundleIdentifier != nil && launcher.bundleIdentifier == bundleIdentifier)
        }
        guard let launcher = match else { return }

        onForeignLaunch?(launcher)
    }

    /// Walk ppid via sysctl until init; true if `candidate` appears as an ancestor of `pid`.
    private func isAncestor(of pid: Int32, candidate: Int32) -> Bool {
        var current = pid
        var guardCount = 0
        while current > 1, guardCount < 64 {
            guard let parent = parentPID(of: current), parent > 0, parent != current else {
                return false
            }
            if parent == candidate { return true }
            current = parent
            guardCount += 1
        }
        return false
    }

    private func parentPID(of pid: Int32) -> Int32? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        let result = sysctl(&mib, u_int(mib.count), &info, &size, nil, 0)
        guard result == 0 else { return nil }
        return info.kp_eproc.e_ppid
    }
}
