import SwiftUI
import AppKit

struct OnboardingView: View {
    @Bindable var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var page = 0

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                whyPage.tag(0)
                pickPage.tag(1)
                habitPage.tag(2)
            }
            // Click-only: no swipe required; we use buttons below.
            .tabViewStyle(.automatic)
            .frame(maxHeight: .infinity)

            HStack {
                if page > 0 {
                    Button("Back") { page -= 1 }
                }
                Spacer()
                if page < 2 {
                    Button("Next") { page += 1 }
                        .buttonStyle(.borderedProminent)
                } else {
                    Button("Done") {
                        state.hasCompletedOnboarding = true
                        dismiss()
                        // Close the onboarding window if presented as a Window.
                        if let win = NSApp.windows.first(where: { $0.identifier?.rawValue == "onboarding" }) {
                            win.close()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
        }
        .onAppear {
            closeWelcomeWindowIfOnboardingFinished()
        }
    }

    /// macOS 14 has no `defaultLaunchBehavior(.suppressed)` (macOS 15.0+).
    /// A Window scene may present at launch. Close it when onboarding is
    /// already finished so a returning session is not left on this window.
    private func closeWelcomeWindowIfOnboardingFinished() {
        guard state.hasCompletedOnboarding else { return }
        if #available(macOS 15.0, *) {
            return
        }
        Task { @MainActor in
            NSApp.windows.first { $0.identifier?.rawValue == "onboarding" }?.close()
        }
    }

    private var whyPage: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Why the microphone?")
                .font(.title2.weight(.semibold))
            Text("macOS only lets apps use the mic when the right app asks for it. Minecraft’s own launcher never asks, so proximity-chat mods stay silent.")
            Text("MC Mic Fix asks for the mic once, then starts Minecraft for you so the game inherits that permission.")
            Spacer()
        }
        .padding(24)
    }

    private var pickPage: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pick your launcher & grant mic")
                .font(.title2.weight(.semibold))

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

            HStack {
                Text(state.mic.statusLine)
                Spacer()
                if state.mic.status == .notDetermined {
                    Button("Grant Microphone Access") {
                        Task { _ = await state.mic.requestAccess() }
                    }
                    .buttonStyle(.borderedProminent)
                } else if state.mic.status != .authorized {
                    Button("Open Settings") { state.mic.openSystemSettings() }
                }
            }
            Spacer()
        }
        .padding(24)
        .onAppear {
            state.refreshCatalog()
            state.mic.refresh()
        }
    }

    private var habitPage: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Always start from MC Mic Fix")
                .font(.title2.weight(.semibold))
            Text("Use the mic icon in the menu bar and press Launch Minecraft. Starting Minecraft from the Dock or Spotlight skips the fix.")
            Text("Optional: turn on “Watch for launchers opened directly” in Settings if you want a reminder.")
            Spacer()
        }
        .padding(24)
    }
}
