import SwiftUI

@main
struct MCMicFixApp: App {
    @State private var state = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(state: state)
        } label: {
            MenuBarLabel(state: state)
        }
        .menuBarExtraStyle(.window)

        // Standard Settings scene (opened via SettingsLink). Does not auto-open at launch.
        Settings {
            SettingsView(state: state)
                .frame(minWidth: 420, minHeight: 360)
        }

        Window("Welcome", id: "onboarding") {
            OnboardingView(state: state)
                .frame(width: 480, height: 360)
        }
        .defaultLaunchBehavior(.suppressed)
    }
}
