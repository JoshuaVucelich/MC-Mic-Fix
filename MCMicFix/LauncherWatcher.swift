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
    /// Ignore launches we ourselves just started (pid match + short grace).
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
            // Extract Sendable fields before hopping to MainActor (Swift 6).
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

        guard let bundleURL else { return }
        guard let catalog = catalogProvider?() else { return }

        let match = catalog.launchers.first { launcher in
            launcher.appURL.standardizedFileURL == bundleURL.standardizedFileURL
                || (launcher.bundleIdentifier != nil && launcher.bundleIdentifier == bundleIdentifier)
        }
        guard let launcher = match else { return }

        if let parent = parentPID(of: pid), parent == ProcessInfo.processInfo.processIdentifier {
            return
        }

        onForeignLaunch?(launcher)
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
