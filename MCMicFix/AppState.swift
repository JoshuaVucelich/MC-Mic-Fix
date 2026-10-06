import Foundation
import Observation
import AppKit
import UserNotifications

@MainActor
@Observable
final class AppState {
    var catalog = LauncherCatalog()
    var mic = MicPermission()
    var spawner = LauncherSpawner()
    var watcher = LauncherWatcher()
    var meter = MicLevelMeter()

    var selectedLauncherID: String? {
        didSet {
            UserDefaults.standard.set(selectedLauncherID, forKey: Keys.selectedLauncherID)
        }
    }

    var launchAtLoginEnabled: Bool = SMLogin.isEnabled {
        didSet { SMLogin.setEnabled(launchAtLoginEnabled) }
    }

    var watchDirectLaunches: Bool = UserDefaults.standard.bool(forKey: Keys.watchDirect) {
        didSet { UserDefaults.standard.set(watchDirectLaunches, forKey: Keys.watchDirect) }
    }

    var autoRelaunch: Bool = UserDefaults.standard.bool(forKey: Keys.autoRelaunch) {
        didSet { UserDefaults.standard.set(autoRelaunch, forKey: Keys.autoRelaunch) }
    }

    var javaOptionsEnabled: Bool = UserDefaults.standard.bool(forKey: Keys.javaOptionsEnabled) {
        didSet { UserDefaults.standard.set(javaOptionsEnabled, forKey: Keys.javaOptionsEnabled) }
    }

    var javaOptionsPresetRaw: String = UserDefaults.standard.string(forKey: Keys.javaOptionsPreset)
        ?? JavaOptionsPreset.none.rawValue
    {
        didSet { UserDefaults.standard.set(javaOptionsPresetRaw, forKey: Keys.javaOptionsPreset) }
    }

    var javaOptionsPreset: JavaOptionsPreset {
        get { JavaOptionsPreset(rawValue: javaOptionsPresetRaw) ?? .none }
        set { javaOptionsPresetRaw = newValue.rawValue }
    }

    var hasCompletedOnboarding: Bool = UserDefaults.standard.bool(forKey: Keys.onboardingDone) {
        didSet { UserDefaults.standard.set(hasCompletedOnboarding, forKey: Keys.onboardingDone) }
    }

    var showSettings = false
    var showOnboarding = false
    var showQuitRelaunchPrompt = false
    var outsideLaunchBadge = false
    var statusMessage: String = "Ready"
    var lastError: String?

    var selectedLauncher: DetectedLauncher? {
        catalog.launchers.first { $0.id == selectedLauncherID }
    }

    init() {
        catalog.refresh()
        if let saved = UserDefaults.standard.string(forKey: Keys.selectedLauncherID),
           catalog.launchers.contains(where: { $0.id == saved }) {
            selectedLauncherID = saved
        } else {
            selectedLauncherID = catalog.launchers.first?.id
        }
        if !UserDefaults.standard.bool(forKey: Keys.onboardingDone) {
            showOnboarding = true
        }
        mic.refresh()
        watcher.onForeignLaunch = { [weak self] launcher in
            Task { @MainActor in
                self?.handleForeignLaunch(launcher)
            }
        }
        watcher.start(catalog: catalog, isEnabled: { [weak self] in
            self?.watchDirectLaunches ?? false
        }, ourChildPIDs: { [weak self] in
            self?.spawner.childPIDs ?? []
        })
    }

    func refreshCatalog() {
        catalog.refresh()
        if selectedLauncherID == nil || !(catalog.launchers.contains { $0.id == selectedLauncherID }) {
            selectedLauncherID = catalog.launchers.first?.id
        }
    }

    func launchSelected() async {
        lastError = nil
        guard let launcher = selectedLauncher else {
            lastError = "Pick a launcher first."
            return
        }

        if LauncherSpawner.isAppRunning(bundleURL: launcher.appURL) {
            showQuitRelaunchPrompt = true
            return
        }

        await performLaunch(launcher)
    }

    func quitAndRelaunch() async {
        showQuitRelaunchPrompt = false
        guard let launcher = selectedLauncher else { return }
        LauncherSpawner.terminateRunning(bundleURL: launcher.appURL)
        // Brief pause so the process can exit before we spawn again.
        try? await Task.sleep(nanoseconds: 400_000_000)
        await performLaunch(launcher)
    }

    private func performLaunch(_ launcher: DetectedLauncher) async {
        mic.refresh()
        if mic.status == .notDetermined {
            _ = await mic.requestAccess()
        }
        guard mic.status == .authorized else {
            statusMessage = mic.statusLine
            lastError = "Microphone access is required before launching."
            return
        }

        do {
            statusMessage = "Launching \(launcher.displayName)…"
            watcher.markSelfLaunch()
            try spawner.launch(
                launcher: launcher,
                javaOptionsEnabled: javaOptionsEnabled,
                preset: javaOptionsPreset
            )
            statusMessage = "Launched \(launcher.displayName)"
            outsideLaunchBadge = false
        } catch {
            lastError = error.localizedDescription
            statusMessage = "Launch failed"
        }
    }

    private func handleForeignLaunch(_ launcher: DetectedLauncher) {
        outsideLaunchBadge = true
        statusMessage = "Opened outside MC Mic Fix — click to relaunch correctly"
        if autoRelaunch {
            Task { @MainActor in
                selectedLauncherID = launcher.id
                await quitAndRelaunch()
            }
        } else {
            let content = UNMutableNotificationContent()
            content.title = "MC Mic Fix"
            content.body = "\(launcher.displayName) opened outside MC Mic Fix. Click the menu bar icon to relaunch correctly."
            content.sound = .default
            let req = UNNotificationRequest(
                identifier: "outside-\(launcher.id)-\(UUID().uuidString)",
                content: content,
                trigger: nil
            )
            UNUserNotificationCenter.current().add(req)
        }
    }

    enum Keys {
        static let selectedLauncherID = "selectedLauncherID"
        static let watchDirect = "watchDirectLaunches"
        static let autoRelaunch = "autoRelaunch"
        static let javaOptionsEnabled = "javaOptionsEnabled"
        static let javaOptionsPreset = "javaOptionsPreset"
        static let onboardingDone = "onboardingDone"
    }
}
