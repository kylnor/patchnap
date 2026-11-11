import SwiftUI
import AppKit

@main struct PatchnapApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene {
        MenuBarExtra("Patchnap", systemImage: "moon.zzz") {
            MenuPanel(model: AppModel.shared)
        }.menuBarExtraStyle(.window)
        Settings { PreferencesView(model: AppModel.shared).frame(width: 620, height: 430) }
    }
}
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let firstLaunch = !UserDefaults.standard.bool(forKey: "hasLaunched")
        UserDefaults.standard.set(true, forKey: "hasLaunched")
        if firstLaunch || CommandLine.arguments.contains("--show-window") || CommandLine.arguments.contains("--demo") { AppWindow.shared.show() }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { AppWindow.shared.show(); return true }
}
@MainActor final class AppWindow {
    static let shared = AppWindow()
    var window: NSWindow?
    func show() {
        if window == nil {
            let previewScheme: ColorScheme? = CommandLine.arguments.contains("--appearance-light") ? .light
                : CommandLine.arguments.contains("--appearance-dark") ? .dark : nil
            let controller = NSHostingController(rootView: Dashboard(model: AppModel.shared).transformEnvironment(\.colorScheme) { scheme in
                if let previewScheme { scheme = previewScheme }
            })
            let new = NSWindow(contentViewController: controller)
            new.title = AppModel.shared.demo ? "Patchnap Preview" : "Patchnap"; new.setContentSize(NSSize(width: 850, height: 650))
            new.minSize = NSSize(width: 680, height: 540)
            if CommandLine.arguments.contains("--compact") { new.setContentSize(NSSize(width: 680, height: 540)) }
            if CommandLine.arguments.contains("--appearance-light") { new.appearance = NSAppearance(named: .aqua) }
            if CommandLine.arguments.contains("--appearance-dark") { new.appearance = NSAppearance(named: .darkAqua) }
            new.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            new.isReleasedWhenClosed = false; new.center(); window = new
        }
        if AppModel.shared.demo && CommandLine.arguments.contains("--background-preview") {
            window?.orderBack(nil)
        } else {
            window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        }
    }
}
