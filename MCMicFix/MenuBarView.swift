import SwiftUI
import AppKit

struct MenuBarView: View {
    @Bindable var state: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(state.mic.statusLine)
                    .font(.headline)
                Spacer()
                if state.outsideLaunchBadge {
                    Text("Outside")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.orange.opacity(0.25), in: Capsule())
                }
            }

            if state.mic.status == .denied || state.mic.status == .restricted {
                Button("Open Microphone Settings") {
                    state.mic.openSystemSettings()
                }
                .buttonStyle(.bordered)
            } else if state.mic.status == .notDetermined {
                Button("Grant Microphone Access") {
                    Task { _ = await state.mic.requestAccess() }
                }
                .buttonStyle(.borderedProminent)
            }

            Divider()

            Text("Launcher")
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("Launcher", selection: Binding(
                get: { state.selectedLauncherID ?? "" },
                set: { newValue in
                    if newValue == "__other__" {
                        if let picked = state.catalog.pickOtherApp() {
                            state.selectedLauncherID = picked.id
                        }
                    } else {
                        state.selectedLauncherID = newValue.isEmpty ? nil : newValue
                    }
                }
            )) {
                ForEach(state.catalog.launchers) { launcher in
                    Text(launcher.displayName).tag(launcher.id)
                }
                Text("Other…").tag("__other__")
            }
            .labelsHidden()
            .pickerStyle(.menu)

            Button {
                state.refreshCatalog()
            } label: {
                Label("Refresh launcher list", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .font(.caption)

            Button {
                Task { await state.launchSelected() }
            } label: {
                Text("Launch Minecraft")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(state.selectedLauncher == nil)

            if let err = state.lastError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(state.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            Toggle(isOn: $state.showMicTest) {
                Text("Mic test")
            }
            .toggleStyle(.switch)

            if state.showMicTest {
                MicMeterView(meter: state.meter)
            }

            Divider()

            SettingsLink {
                Text("Settings…")
            }
            Button("Quit MC Mic Fix") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(14)
        .frame(width: 320)
        .background(PopoverLifecycleWatcher {
            state.handlePopoverDismissed()
        })
        .onAppear {
            state.mic.refresh()
            state.refreshCatalog()
            if state.showOnboarding {
                openWindow(id: "onboarding")
                NSApp.activate(ignoringOtherApps: true)
                state.showOnboarding = false
            }
        }
        .sheet(isPresented: $state.showQuitRelaunchPrompt) {
            QuitRelaunchSheet(state: state)
        }
    }
}

/// Observes the hosting window so we stop the mic when the MenuBarExtra
/// popover resigns key or closes (onDisappear alone is unreliable).
private struct PopoverLifecycleWatcher: NSViewRepresentable {
    var onDismiss: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.attach(to: view, onDismiss: onDismiss)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onDismiss = onDismiss
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    /// NSViewRepresentable coordinators hop queues; mark unchecked for Swift 6.
    final class Coordinator: @unchecked Sendable {
        var onDismiss: (() -> Void)?
        private var resignKey: NSObjectProtocol?
        private var willClose: NSObjectProtocol?
        private weak var window: NSWindow?

        func attach(to view: NSView, onDismiss: @escaping () -> Void) {
            self.onDismiss = onDismiss
            let apply: () -> Void = { [weak self, weak view] in
                guard let self, let view, let window = view.window else { return }
                if self.resignKey != nil { return } // already attached
                self.window = window
                let center = NotificationCenter.default
                let dismiss: () -> Void = { self.onDismiss?() }
                self.resignKey = center.addObserver(
                    forName: NSWindow.didResignKeyNotification,
                    object: window,
                    queue: .main
                ) { _ in dismiss() }
                self.willClose = center.addObserver(
                    forName: NSWindow.willCloseNotification,
                    object: window,
                    queue: .main
                ) { _ in dismiss() }
            }
            if view.window != nil {
                apply()
            } else {
                DispatchQueue.main.async(execute: apply)
            }
        }

        deinit {
            if let resignKey { NotificationCenter.default.removeObserver(resignKey) }
            if let willClose { NotificationCenter.default.removeObserver(willClose) }
        }
    }
}

struct QuitRelaunchSheet: View {
    @Bindable var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Launcher already running")
                .font(.title3.weight(.semibold))
            Text("Quit and relaunch through MC Mic Fix")
                .font(.body)
                .foregroundStyle(.secondary)
            if state.showForceQuitOption {
                Text("The launcher did not quit in time. You can Force Quit it, then relaunch.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            HStack {
                Button("Cancel") {
                    state.showQuitRelaunchPrompt = false
                    state.showForceQuitOption = false
                }
                .keyboardShortcut(.cancelAction)
                Spacer()
                if state.showForceQuitOption {
                    Button("Force Quit") {
                        Task { await state.quitAndRelaunch(force: true) }
                    }
                    .buttonStyle(.bordered)
                }
                // Not the default action — Return must not trigger destructive quit.
                Button("Quit and relaunch through MC Mic Fix") {
                    Task { await state.quitAndRelaunch(force: false) }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 400)
    }
}
