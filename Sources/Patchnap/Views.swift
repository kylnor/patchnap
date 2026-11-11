import SwiftUI
import ServiceManagement
import PatchnapCore

struct MenuPanel: View {
    @Bindable var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { PatchMascot().frame(width: 56, height: 50); VStack(alignment: .leading, spacing: 3) { Text("Patchnap").font(.system(.title3, design: .rounded).bold()); Text(model.settings.enabled ? "Keeping an eye on things." : "Background updates paused.").font(.caption).foregroundStyle(.secondary) } }
            if model.demo { Text("Design preview • illustrative data").font(.caption).foregroundStyle(.secondary) }
            Text(model.snapshot.lastCheck == nil ? "Ready for your first check." : "\(model.pending) update\(model.pending == 1 ? "" : "s") waiting.").font(.headline)
            HStack {
                Button(model.checking ? "Checking…" : "Check now") { Task { await model.check() } }.disabled(model.checking || model.demo)
                Spacer()
                Button("Open Patchnap") { AppWindow.shared.show() }
            }
            Divider()
            Toggle("Background updates", isOn: Binding(get: { model.settings.enabled }, set: { model.setEnabled($0) })).disabled(model.demo)
            if let error = model.error { Text(error).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
            HStack { Text("Stable releases only").font(.caption).foregroundStyle(.secondary); Spacer(); Button("Quit") { NSApplication.shared.terminate(nil) }.buttonStyle(.plain).font(.caption) }
        }.padding(20).frame(width: 340).tint(.patchnapGrape)
        .onAppear { model.reload() }
    }
}

struct Dashboard: View {
    @Bindable var model: AppModel
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 18) {
                PatchMascot().frame(width: 95, height: 85)
                VStack(alignment: .leading, spacing: 5) {
                    Text("patchnap").font(.system(size: 29, weight: .heavy, design: .rounded))
                    Text("Updates handled. Go get some sleep.").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button(model.checking ? "Checking…" : "Check for updates") { Task { await model.check() } }.disabled(model.checking || model.demo)
            }.padding(.horizontal, 28).padding(.vertical, 16).background(Color.patchnapMint.opacity(0.20))
            if model.demo { Text("Design preview. All app names and update results below are illustrative.").font(.caption).padding(8).frame(maxWidth: .infinity).background(.quaternary) }
            TabView(selection: $model.tab) {
                OverviewView(model: model).tabItem { Label("Overview", systemImage: "moon") }.tag(0)
                AppsView(model: model).tabItem { Label("Apps", systemImage: "square.grid.2x2") }.tag(1)
                ActivityView(model: model).tabItem { Label("Activity", systemImage: "clock") }.tag(2)
                PreferencesView(model: model).tabItem { Label("Settings", systemImage: "gearshape") }.tag(3)
            }.padding(18)
        }.tint(.patchnapGrape)
        .alert("Patchnap needs your attention", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) { Button("OK") { model.error = nil } } message: { Text(model.error ?? "") }
        .task {
            while !Task.isCancelled {
                model.reload()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }
}
struct OverviewView: View {
    @Bindable var model: AppModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 9) {
                    Text(model.settings.enabled ? "We'll take it from here." : "One less thing to keep up with.").font(.system(.title2, design: .rounded).bold())
                    Text(model.snapshot.message).foregroundStyle(.secondary)
                    if let date = model.snapshot.lastCheck { Text("Last checked \(date.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary) }
                }
                HStack(spacing: 35) { metric("Supported apps", value: model.covered); metric("Updates waiting", value: model.pending); metric("Installed apps", value: model.snapshot.apps.count) }
                Divider()
                VStack(alignment: .leading, spacing: 10) {
                    Label("Stable releases only", systemImage: "checkmark.shield")
                    Label("Installs after 10+ idle minutes on power", systemImage: "powerplug")
                    Label("Open apps wait until you close them", systemImage: "pause.circle")
                }.font(.callout)
                if !model.settings.enabled {
                    Button("Enable background updates") { model.setEnabled(true) }.buttonStyle(.borderedProminent).disabled(model.demo)
                }
                if !model.snapshot.providerErrors.isEmpty {
                    VStack(alignment: .leading, spacing: 8) { Text("Update sources need attention").font(.headline); ForEach(model.snapshot.providerErrors, id: \.self) { Text($0).font(.callout).foregroundStyle(.secondary) } }
                }
                Text("App Store apps, supported Homebrew casks, and verified standalone downloads are covered in this alpha. Other apps stay visible with their update-source status.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    func metric(_ label: String, value: Int) -> some View { VStack(alignment: .leading, spacing: 6) { Text(value, format: .number).font(.title2.bold()).monospacedDigit(); Text(label).font(.caption).foregroundStyle(.secondary) } }
}
struct AppsView: View {
    @Bindable var model: AppModel
    var body: some View {
        let apps = model.visibleApps
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                TextField("Search installed apps", text: $model.filters.search)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("app-search")
                HStack(spacing: 16) {
                    Picker("Source", selection: $model.filters.source) {
                        Text("All sources").tag(Optional<Provider>.none)
                        ForEach(Provider.allCases, id: \.self) { provider in
                            Text(provider.label).tag(Optional(provider))
                        }
                    }.pickerStyle(.menu).foregroundStyle(.primary).accessibilityIdentifier("app-source-filter")
                    Picker("Status", selection: $model.filters.status) {
                        Text("All statuses").tag(Optional<AppStatus>.none)
                        ForEach(AppStatus.allCases) { status in
                            Text(status.label).tag(Optional(status))
                        }
                    }.pickerStyle(.menu).foregroundStyle(.primary).accessibilityIdentifier("app-status-filter")
                    if model.filters.isActive {
                        Button("Clear filters") { model.clearFilters() }
                            .accessibilityIdentifier("clear-app-filters")
                    }
                }.controlSize(.small)
                Text("\(apps.count) of \(model.snapshot.apps.count) apps")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(12)
            if apps.isEmpty {
                ContentUnavailableView {
                    Label(model.snapshot.apps.isEmpty ? "Check for your installed apps" : "No matching apps", systemImage: "square.grid.2x2")
                } description: {
                    Text(model.snapshot.apps.isEmpty ? "Run your first check to see supported sources and available updates." : "Try a different search, source, or status.")
                } actions: {
                    if model.filters.isActive { Button("Clear filters") { model.clearFilters() } }
                }
            } else {
                List(apps) { app in
                    HStack(spacing: 12) {
                        if !app.path.isEmpty { Image(nsImage: NSWorkspace.shared.icon(forFile: app.path)).resizable().frame(width: 32, height: 32) }
                        else { Image(systemName: "app").font(.title2).frame(width: 32) }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(app.name).fontWeight(.medium)
                            Text(app.installedVersion + (app.availableVersion.map { " → " + $0 } ?? "") + " · " + source(app.provider)).font(.caption).foregroundStyle(.secondary)
                            if let reason = app.reason { Text(reason).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                        }
                        Spacer()
                        Text(model.status(app)).font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: true, vertical: false)
                        Menu {
                            Button(model.settings.excluded.contains(app.id) ? "Include in updates" : "Exclude from updates") { model.exclude(app) }
                            Button(model.settings.heldVersions[app.id] == nil ? "Hold version \(app.installedVersion)" : "Release version hold") { model.hold(app) }
                            if !app.path.isEmpty { Button("Show in Finder") { NSWorkspace.shared.selectFile(app.path, inFileViewerRootedAtPath: "") } }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 14, weight: .semibold))
                                .frame(width: 28, height: 28)
                                .contentShape(Rectangle())
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .frame(width: 32, height: 28)
                        .accessibilityLabel("Actions for \(app.name)")
                        .help("Actions for \(app.name)")
                        .disabled(model.demo)
                    }.padding(.vertical, 5)
                }.listStyle(.inset)
            }
        }
    }
    func source(_ provider: Provider) -> String { switch provider { case .appStore: "App Store"; case .homebrew: "Homebrew"; case .catalog: "Verified catalog download"; case .unsupported: "Unsupported source" } }
}
struct ActivityView: View {
    @Bindable var model: AppModel
    var body: some View {
        if model.snapshot.history.isEmpty { ContentUnavailableView("Nothing to report yet", systemImage: "moon.zzz", description: Text("Verified updates and anything needing attention will appear here.")) }
        else {
            List(model.snapshot.history) { entry in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: entry.outcome == .updated ? "checkmark.circle" : "exclamationmark.circle").foregroundStyle(entry.outcome == .updated ? Color.green : Color.orange)
                    VStack(alignment: .leading, spacing: 4) { Text(entry.appName).fontWeight(.medium); Text(entry.message).font(.callout).foregroundStyle(.secondary); Text(entry.date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary) }
                }.padding(.vertical, 6)
            }.listStyle(.inset)
        }
    }
}
struct PreferencesView: View {
    @Bindable var model: AppModel
    var body: some View {
        Form {
            Section("Background maintenance") {
                Toggle("Enable automatic updates", isOn: Binding(get: { model.settings.enabled }, set: { model.setEnabled($0) })).disabled(model.demo)
                LabeledContent("Background service", value: model.registration)
                Picker("Check for updates", selection: Binding(get: { model.settings.checkInterval }, set: { model.settings.checkInterval = $0; model.save() })) { Text("Every hour").tag(3600.0); Text("Every 3 hours").tag(10800.0); Text("Every 6 hours").tag(21600.0) }.disabled(model.demo)
                Picker("Install after idle time", selection: Binding(get: { model.settings.idleSeconds }, set: { model.settings.idleSeconds = $0; model.save() })) { Text("10 minutes").tag(600.0); Text("15 minutes").tag(900.0); Text("30 minutes").tag(1800.0) }.disabled(model.demo)
                Text("Only on external power. Patchnap leaves open apps alone and catches up when your Mac is awake and idle.").font(.caption).foregroundStyle(.secondary)
                HStack { Button("Open Login Items") { SMAppService.openSystemSettingsLoginItems() }; Button("Remove background service") { Task { await model.removeBackground() } }.disabled(model.demo) }
            }
            Section("App Store installations") {
                LabeledContent("Installation helper", value: model.helperInstalled ? "Installed" : "Not installed")
                Text("App Store checks use your existing Apple Account. Installing updates requires a separate one-time administrator approval for a narrowly scoped helper.").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button(model.helperBusy ? "Working…" : "Enable App Store installs") { Task { await model.configureHelper() } }.disabled(model.helperBusy || model.demo)
                    if model.helperInstalled { Button("Remove helper") { Task { await model.configureHelper(remove: true) } }.disabled(model.helperBusy || model.demo) }
                }
            }
            Section("About") {
                LabeledContent("Patchnap", value: "\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development") · Early alpha")
                Link("Source code and issues", destination: URL(string: "https://github.com/kylnor/patchnap")!)
                Text("No telemetry. Settings and history stay on this Mac.").font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }
}
