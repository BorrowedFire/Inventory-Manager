import AppKit
import Foundation
import SwiftUI

struct InstallGuideSheet: View {
    let moveToApplications: () -> Void
    let continueHere: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Install Inventory Manager")
                .font(.system(size: 30, weight: .bold, design: .serif))

            Text("For the cleanest internal setup, move the app into the Applications folder before you start using it.")
                .foregroundStyle(AppTheme.muted)

            VStack(alignment: .leading, spacing: 10) {
                installBullet("Install in Applications so the app launches from a stable path and keeps its icon and permissions more reliably.")
                installBullet("If macOS says the app is from an unidentified developer, right-click the app and choose Open once, or allow it in System Settings > Privacy & Security.")
                installBullet("After the app is in Applications, launch that copy going forward instead of the one from Downloads or a temporary folder.")
            }
            .frostedPanel()

            HStack {
                Button("Move to Applications") {
                    moveToApplications()
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.blue)

                Button("Open Applications Folder") {
                    InstallHelper.openApplicationsFolder()
                }

                Spacer()

                Button("Continue Here") {
                    continueHere()
                }
            }
        }
        .padding(28)
        .frame(width: 760)
        .background(
            LinearGradient(
                colors: [AppTheme.backgroundTop, AppTheme.backgroundBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private func installBullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "arrow.down.app")
                .foregroundStyle(AppTheme.blue)
                .padding(.top, 2)
            Text(text)
                .font(.caption)
                .foregroundStyle(AppTheme.muted)
        }
    }
}

enum InstallHelper {
    static var shouldPromptForApplicationsInstall: Bool {
        !Bundle.main.bundleURL.path.hasPrefix("/Applications/")
    }

    static func moveToApplications() throws -> URL {
        let fileManager = FileManager.default
        let sourceURL = Bundle.main.bundleURL.resolvingSymlinksInPath()
        let targetURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
            .appendingPathComponent(sourceURL.lastPathComponent)
            .resolvingSymlinksInPath()

        if sourceURL == targetURL {
            return targetURL
        }

        if fileManager.fileExists(atPath: targetURL.path) {
            let sourceVersion = AppBundleVersion(bundleURL: sourceURL)
            let targetVersion = AppBundleVersion(bundleURL: targetURL)

            if let sourceVersion, let targetVersion, targetVersion >= sourceVersion {
                AppLog.app.info("Applications copy is same or newer; launching existing copy")
                return targetURL
            }

            AppLog.app.info("Replacing older Applications copy")
            try fileManager.trashItem(at: targetURL, resultingItemURL: nil)
        }

        try fileManager.copyItem(at: sourceURL, to: targetURL)
        return targetURL
    }

    static func relaunchApplication(at url: URL) {
        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in
            Task { @MainActor in
                NSApplication.shared.terminate(nil)
            }
        }
    }

    static func openApplicationsFolder() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications", isDirectory: true))
    }
}

private struct AppBundleVersion: Comparable {
    let marketingVersion: [Int]
    let build: Int

    init?(bundleURL: URL) {
        guard let bundle = Bundle(url: bundleURL) else { return nil }

        let versionString = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let buildString = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        marketingVersion = versionString
            .split(separator: ".")
            .map { Int($0) ?? 0 }
        build = Int(buildString) ?? 0

        guard !marketingVersion.isEmpty else { return nil }
    }

    static func < (lhs: AppBundleVersion, rhs: AppBundleVersion) -> Bool {
        let maxCount = max(lhs.marketingVersion.count, rhs.marketingVersion.count)
        for index in 0..<maxCount {
            let left = index < lhs.marketingVersion.count ? lhs.marketingVersion[index] : 0
            let right = index < rhs.marketingVersion.count ? rhs.marketingVersion[index] : 0
            if left != right {
                return left < right
            }
        }
        return lhs.build < rhs.build
    }
}
