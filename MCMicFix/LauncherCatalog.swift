import Foundation
import AppKit

struct DetectedLauncher: Identifiable, Hashable, Sendable {
    let id: String
    let kind: LauncherKind
    let displayName: String
    let appURL: URL
    let executableURL: URL
    let bundleIdentifier: String?
}

enum LauncherKind: String, CaseIterable, Identifiable, Sendable {
    case minecraft
    case prism
    case modrinth
    case curseforge
    case multimc
    case atlauncher
    case gdlauncher
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .minecraft: return "Minecraft Launcher"
        case .prism: return "Prism Launcher"
        case .modrinth: return "Modrinth App"
        case .curseforge: return "CurseForge"
        case .multimc: return "MultiMC"
        case .atlauncher: return "ATLauncher"
        case .gdlauncher: return "GDLauncher"
        case .other: return "Other"
        }
    }

    /// Well-known .app names under /Applications and ~/Applications.
    var candidateAppNames: [String] {
        switch self {
        case .minecraft: return ["Minecraft.app"]
        case .prism: return ["Prism Launcher.app"]
        case .modrinth: return ["Modrinth App.app"]
        case .curseforge: return ["CurseForge.app"]
        case .multimc: return ["MultiMC.app"]
        case .atlauncher: return ["ATLauncher.app"]
        case .gdlauncher: return ["GDLauncher.app"]
        case .other: return []
        }
    }
}

@MainActor
@Observable
final class LauncherCatalog {
    private(set) var launchers: [DetectedLauncher] = []

    func refresh() {
        var found: [DetectedLauncher] = []
        let searchRoots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
        ]

        for kind in LauncherKind.allCases where kind != .other {
            for root in searchRoots {
                for name in kind.candidateAppNames {
                    let appURL = root.appendingPathComponent(name)
                    if let launcher = Self.resolve(appURL: appURL, kind: kind) {
                        // Prefer /Applications over ~/Applications if both exist.
                        if !found.contains(where: { $0.kind == kind }) {
                            found.append(launcher)
                        }
                    }
                }
            }
        }

        // Keep a previously picked "Other…" entry if still on disk.
        if let savedPath = UserDefaults.standard.string(forKey: "otherLauncherPath") {
            let url = URL(fileURLWithPath: savedPath)
            if let other = Self.resolve(appURL: url, kind: .other),
               !found.contains(where: { $0.appURL == other.appURL }) {
                found.append(other)
            }
        }

        launchers = found.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    /// Present an NSOpenPanel for picking any .app; returns the resolved launcher or nil.
    func pickOtherApp() -> DetectedLauncher? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.application]
        panel.title = "Choose a Minecraft launcher"
        panel.message = "Pick any .app to launch through MC Mic Fix."
        panel.directoryURL = URL(fileURLWithPath: "/Applications")

        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        guard let launcher = Self.resolve(appURL: url, kind: .other) else { return nil }

        UserDefaults.standard.set(url.path, forKey: "otherLauncherPath")
        if let idx = launchers.firstIndex(where: { $0.kind == .other }) {
            launchers[idx] = launcher
        } else {
            launchers.append(launcher)
            launchers.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        }
        return launcher
    }

    static func resolve(appURL: URL, kind: LauncherKind) -> DetectedLauncher? {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: appURL.path, isDirectory: &isDir), isDir.boolValue else {
            return nil
        }
        guard appURL.pathExtension == "app" else { return nil }

        let infoURL = appURL.appendingPathComponent("Contents/Info.plist")
        guard let info = NSDictionary(contentsOf: infoURL) as? [String: Any] else { return nil }
        guard let executableName = info["CFBundleExecutable"] as? String else { return nil }

        let executableURL = appURL
            .appendingPathComponent("Contents/MacOS", isDirectory: true)
            .appendingPathComponent(executableName)
        guard fm.isExecutableFile(atPath: executableURL.path) else { return nil }

        let bundleID = info["CFBundleIdentifier"] as? String
        let bundleName = (info["CFBundleName"] as? String)
            ?? (info["CFBundleDisplayName"] as? String)
            ?? appURL.deletingPathExtension().lastPathComponent

        let displayName: String
        if kind == .other {
            displayName = bundleName
        } else {
            displayName = kind.displayName
        }

        let id = (bundleID ?? appURL.path) + "|" + kind.rawValue
        return DetectedLauncher(
            id: id,
            kind: kind,
            displayName: displayName,
            appURL: appURL,
            executableURL: executableURL,
            bundleIdentifier: bundleID
        )
    }
}
