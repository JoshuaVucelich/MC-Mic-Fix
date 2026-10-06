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

    var launchAtLoginEnabled: Bool = SMLogin.isEnabled
    var loginItemMessage: String?
    var showOpenLoginItemsButton = false

    var watchDirectLaunches: Bool = UserDefaults.standard.bool(forKey: Keys.watchDirect) {
        didSet {
            UserDefaults.standard.set(watchDirectLaunches, forKey: Keys.watchDirect)
            if watchDirectLaunches {
                requestNotificationsIfNeeded()
            }
        }
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

    var showOnboarding = false
    var showQuitRelaunchPrompt = false
    var showForceQuitOption = false
    var outsideLaunchBadge = false
    var showMicTest = false {
        didSet {
            if showMicTest {
                startMicTest()
            } else {
                stopMicTest()
            }
        }
    }
    var statusMessage: String = "Ready"
    var lastError: String?

    private var resignObservers: [NSObjectProtocol] = []
    private var notificationsRequested = UserDefaults.standard.bool(forKey: Keys.notificationsRequested)

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
        launchAtLoginEnabled = SMLogin.isEnabled

        watcher.onForeignLaunch = { [weak self] launcher in
            Task { @MainActor in
                self?.handleForeignLaunch(launcher)
            }
        }
        watcher.start(
            catalog: catalog,
            isEnabled: { [weak self] in self?.watchDirectLaunches ?? false },
            ourChildPIDs: { [weak self] in self?.spawner.childPIDs ?? [] }
        )

        installLifecycleObservers()

        if watchDirectLaunches {
            requestNotificationsIfNeeded()
        }
    }

    deinit {
        // Observers removed best-effort; AppState lives for app lifetime.
    }

    // MARK: - Mic test lifecycle (owned here, not by the view)

    private var micTestAutoStopTask: Task<Void, Never>?

    func startMicTest() {
        mic.refresh()
        guard mic.status == .authorized else {
            showMicTest = false
            return
        }
        meter.start(autoStopAfter: .seconds(60))
        micTestAutoStopTask?.cancel()
        micTestAutoStopTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(60))
            guard !Task.isCancelled else { return }
            self?.showMicTest = false
        }
    }

    func stopMicTest() {
        micTestAutoStopTask?.cancel()
        micTestAutoStopTask = nil
        meter.stop()
        if showMicTest { showMicTest = false }
    }

    /// Call when the menu-bar popover resigns key / closes or the app deactivates.
    func handlePopoverDismissed() {
        stopMicTest()
    }

    private func installLifecycleObservers() {
        let center = NotificationCenter.default
        let resignActive = center.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handlePopoverDismissed() }
        }
        resignObservers.append(resignActive)
    }

    // MARK: - Catalog / launch

    func refreshCatalog() {
        catalog.refresh()
        if selectedLauncherID == nil || !(catalog.launchers.contains { $0.id == selectedLauncherID }) {
            selectedLauncherID = catalog.launchers.first?.id
        }
    }

    func launchSelected() async {
        lastError = nil
        showForceQuitOption = false
        guard let launcher = selectedLauncher else {
            lastError = "Pick a launcher first."
            return
        }

        // If the running instance is our own child, just activate it.
        if let ourPID = spawner.childPIDs.first(where: { spawner.isOurChild(pid: $0) }),
           LauncherSpawner.matchingApps(
            bundleIdentifier: launcher.bundleIdentifier,
            appURL: launcher.appURL
           ).contains(where: { $0.processIdentifier == ourPID }) {
            LauncherSpawner.activateRunning(
                bundleIdentifier: launcher.bundleIdentifier,
                appURL: launcher.appURL
            )
            statusMessage = "\(launcher.displayName) already running — activated"
            return
        }

        if LauncherSpawner.isAppRunning(
            bundleIdentifier: launcher.bundleIdentifier,
            appURL: launcher.appURL
        ) {
            showQuitRelaunchPrompt = true
            return
        }

        await performLaunch(launcher)
    }

    func quitAndRelaunch(force: Bool = false) async {
        guard let launcher = selectedLauncher else {
            showQuitRelaunchPrompt = false
            return
        }

        if force {
            LauncherSpawner.forceTerminateRunning(
                bundleIdentifier: launcher.bundleIdentifier,
                appURL: launcher.appURL
            )
        } else {
            LauncherSpawner.terminateRunning(
                bundleIdentifier: launcher.bundleIdentifier,
                appURL: launcher.appURL
            )
        }

        statusMessage = force ? "Force-quitting…" : "Waiting for launcher to quit…"
        let cleared = await LauncherSpawner.waitUntilExited(
            bundleIdentifier: launcher.bundleIdentifier,
            appURL: launcher.appURL,
            timeoutSeconds: 10
        )

        if !cleared {
            showForceQuitOption = true
            showQuitRelaunchPrompt = true
            statusMessage = "Still running — try Force Quit"
            lastError = "\(launcher.displayName) did not quit in time."
            return
        }

        showQuitRelaunchPrompt = false
        showForceQuitOption = false

        // Final guard immediately before spawn.
        if LauncherSpawner.isAppRunning(
            bundleIdentifier: launcher.bundleIdentifier,
            appURL: launcher.appURL
        ) {
            lastError = "\(launcher.displayName) is still running. Aborting launch so the mic stays fixed."
            statusMessage = "Launch aborted — quit the launcher first"
            return
        }

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

        // Re-check right before spawn (B3).
        if LauncherSpawner.isAppRunning(
            bundleIdentifier: launcher.bundleIdentifier,
            appURL: launcher.appURL
        ) {
            lastError = "\(launcher.displayName) is still running. Aborting launch so the mic stays fixed."
            statusMessage = "Launch aborted"
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
            lastError = nil
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
                // Same safe quit-and-relaunch flow as the manual prompt.
                await quitAndRelaunch(force: false)
            }
        } else {
            postOutsideNotification(for: launcher)
        }
    }

    // MARK: - Login item

    func setLaunchAtLogin(_ enabled: Bool) {
        let result = SMLogin.setEnabled(enabled)
        switch result {
        case .enabled:
            launchAtLoginEnabled = true
            loginItemMessage = nil
            showOpenLoginItemsButton = false
        case .disabled:
            launchAtLoginEnabled = false
            loginItemMessage = nil
            showOpenLoginItemsButton = false
        case .requiresApproval:
            launchAtLoginEnabled = SMLogin.isEnabled
            loginItemMessage = "macOS needs your approval for Login Items."
            showOpenLoginItemsButton = true
        case .failed(let message):
            launchAtLoginEnabled = SMLogin.isEnabled
            loginItemMessage = message
            showOpenLoginItemsButton = false
        }
    }

    // MARK: - Notifications (only when watcher enabled, once)

    private func requestNotificationsIfNeeded() {
        guard !notificationsRequested else { return }
        notificationsRequested = true
        UserDefaults.standard.set(true, forKey: Keys.notificationsRequested)
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func postOutsideNotification(for launcher: DetectedLauncher) {
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

    enum Keys {
        static let selectedLauncherID = "selectedLauncherID"
        static let watchDirect = "watchDirectLaunches"
        static let autoRelaunch = "autoRelaunch"
        static let javaOptionsEnabled = "javaOptionsEnabled"
        static let javaOptionsPreset = "javaOptionsPreset"
        static let onboardingDone = "onboardingDone"
        static let notificationsRequested = "notificationsRequested"
    }
}
