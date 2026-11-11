import Foundation
import AppKit
import IOKit.ps
import CoreGraphics

public enum SystemConditions {
    @MainActor public static func read() -> Conditions {
        let onPower: Bool?
        if let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let source = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() {
            onPower = (source as String) == kIOPSACPowerValue
        } else { onPower = nil }
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .null)
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        return Conditions(onPower: onPower, idleSeconds: idle.isFinite ? idle : nil, runningBundleIDs: running)
    }
}

public enum Inventory {
    public static func installedApps() -> [InstalledApp] {
        let roots = [URL(fileURLWithPath: "/Applications"), FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")]
        var found: [InstalledApp] = []
        for root in roots {
            guard let iterator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { continue }
            for case let url as URL in iterator {
                if url.pathExtension == "app" {
                    iterator.skipDescendants()
                    guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { continue }
                    let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                        ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String) ?? url.deletingPathExtension().lastPathComponent
                    let version = (bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "Unknown"
                    found.append(InstalledApp(id: "bundle:\(id):\(url.path)", name: name, bundleID: id, path: url.path,
                                              installedVersion: version, provider: .unsupported, token: "", automatic: false,
                                              reason: "No supported update source yet."))
                }
            }
        }
        return found.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
