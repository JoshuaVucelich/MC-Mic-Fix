import SwiftUI

struct MenuBarLabel: View {
    @Bindable var state: AppState

    var body: some View {
        // SF Symbol mic — badge when a launcher was opened outside us.
        Label {
            Text("MC Mic Fix")
        } icon: {
            Image(systemName: state.outsideLaunchBadge ? "mic.badge.xmark" : "mic.fill")
        }
    }
}
