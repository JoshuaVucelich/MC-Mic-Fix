import SwiftUI
import AppKit

struct MenuBarView: View {
    @Bindable var state: AppState
    @Environment(\.openWindow) private var openWindow
    @State private var showMicTest = false

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

            Toggle(isOn: $showMicTest) {
                Text("Mic test")
            }
            .toggleStyle(.switch)

            if showMicTest {
                MicMeterView(meter: state.meter)
                    .onAppear { state.meter.start() }
                    .onDisappear { state.meter.stop() }
            }

            Divider()

            Button("Settings…") {
                openWindow(id: "settings")
                NSApp.activate(ignoringOtherApps: true)
            }
            Button("Quit MC Mic Fix") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(14)
        .frame(width: 320)
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

struct QuitRelaunchSheet: View {
    @Bindable var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Launcher already running")
                .font(.title3.weight(.semibold))
            Text("Quit and relaunch through MC Mic Fix")
                .font(.body)
                .foregroundStyle(.secondary)
            HStack {
                Button("Cancel") {
                    state.showQuitRelaunchPrompt = false
                }
                .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Quit and relaunch through MC Mic Fix") {
                    Task { await state.quitAndRelaunch() }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}
