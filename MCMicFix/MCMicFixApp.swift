import SwiftUI

// Scene.defaultLaunchBehavior(_:) is macOS 15.0 and later. The compat entry
// point omits it so a deployment target of 14.0 does not reference that API.
// OnboardingView closes a finished welcome window on macOS 14, where a Window
// scene can still present itself at launch.
@main
enum MCMicFixMain {
    static func main() {
        if #available(macOS 15.0, *) {
            MCMicFixApp.main()
        } else {
            MCMicFixAppCompat.main()
        }
    }
}

@available(macOS 15.0, *)
struct MCMicFixApp: App {
    @State private var state = AppState()

    var body: some Scene {
        menuBarExtra(state: state)
        settingsScene(state: state)
        onboardingScene(state: state)
            .defaultLaunchBehavior(.suppressed)
    }
}

struct MCMicFixAppCompat: App {
    @State private var state = AppState()

    var body: some Scene {
        menuBarExtra(state: state)
        settingsScene(state: state)
        onboardingScene(state: state)
    }
}

@MainActor
private func menuBarExtra(state: AppState) -> some Scene {
    MenuBarExtra {
        MenuBarView(state: state)
    } label: {
        MenuBarLabel(state: state)
    }
    .menuBarExtraStyle(.window)
}

@MainActor
private func settingsScene(state: AppState) -> some Scene {
    // Standard Settings scene (opened via SettingsLink). Does not auto-open at launch.
    Settings {
        SettingsView(state: state)
            .frame(minWidth: 420, minHeight: 360)
    }
}

@MainActor
private func onboardingScene(state: AppState) -> some Scene {
    Window("Welcome", id: "onboarding") {
        OnboardingView(state: state)
            .frame(width: 480, height: 360)
    }
}
