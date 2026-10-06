import SwiftUI

struct SettingsView: View {
    @Bindable var state: AppState

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Launch at Login", isOn: Binding(
                    get: { state.launchAtLoginEnabled },
                    set: { state.setLaunchAtLogin($0) }
                ))
                if let message = state.loginItemMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if state.showOpenLoginItemsButton {
                    Button("Open Login Items Settings") {
                        SMLogin.openLoginItemsSettings()
                    }
                }
            }

            Section("Watch launchers") {
                Toggle("Watch for launchers opened directly", isOn: $state.watchDirectLaunches)
                Toggle("Relaunch automatically", isOn: $state.autoRelaunch)
                    .disabled(!state.watchDirectLaunches)
                Text("When a watched launcher starts from the Dock or Finder, MC Mic Fix can warn you or quit it and start it again through this app so the microphone keeps working.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Advanced") {
                DisclosureGroup("Java options (optional, not required for mic)") {
                    Toggle("Pass Java options to launcher", isOn: $state.javaOptionsEnabled)
                    Picker("Preset", selection: $state.javaOptionsPresetRaw) {
                        ForEach(JavaOptionsPreset.allCases) { preset in
                            Text(preset.title).tag(preset.rawValue)
                        }
                    }
                    .disabled(!state.javaOptionsEnabled)
                    Text("These legacy flags do not grant microphone access. Leave them off unless you have a specific reason.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("About") {
                LabeledContent(
                    "Version",
                    value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
                )
                Text("MC Mic Fix keeps itself as the macOS responsible process when starting your launcher, so Minecraft voice-chat mods can use the microphone.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
