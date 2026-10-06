import SwiftUI
import UserNotifications

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

        Window("MC Mic Fix Settings", id: "settings") {
            SettingsView(state: state)
                .frame(minWidth: 420, minHeight: 360)
        }

        Window("Welcome", id: "onboarding") {
            OnboardingView(state: state)
                .frame(width: 480, height: 360)
        }
    }

    init() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
}
