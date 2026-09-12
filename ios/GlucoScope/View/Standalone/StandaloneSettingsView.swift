import SwiftUI

struct StandaloneSettingsView: View {
    @EnvironmentObject private var prefs: PreferenceService
    @ObservedObject var runtime: AppRuntime

    var body: some View {
        List {
            Section("Display") {
                NavigationLink {
                    StandaloneUISettingsView()
                } label: {
                    settingsRow("UI", "Display thresholds and graph preferences", "display")
                }
                NavigationLink {
                    ThemeSettingsView()
                        .navigationTitle("Theming")
                } label: {
                    settingsRow("Theming", "Colors and appearance", "paintpalette.fill")
                }
            }

            Section("Services") {
                NavigationLink {
                    ServerUploadsView(coordinator: runtime.uploads)
                } label: {
                    settingsRow(
                        "Server uploads",
                        runtime.uploads.hasPendingUploads
                            ? "\(runtime.uploads.pendingReadingCount) readings pending"
                            : "Nightscout and GlucoScope destinations",
                        "arrow.up.circle.fill"
                    )
                }
                NavigationLink {
                    AlarmSettingsView(service: runtime.alarms)
                } label: {
                    settingsRow("Alarms", "Rules, schedules and sounds", "bell.badge.fill")
                }
                NavigationLink {
                    LiveActivitySettingsView(service: runtime.liveActivity)
                } label: {
                    settingsRow("Live Activity", runtime.liveActivity.status, "waveform.path.ecg.rectangle")
                }
            }

            Section("Sensor") {
                Button {
                    runtime.standaloneTab = .sensor
                } label: {
                    settingsRow(
                        "Sensor & Bluetooth",
                        "Setup, connection, freshness and redacted logs",
                        "sensor"
                    )
                }
            }

            Section("GlucoScope") {
                NavigationLink {
                    AboutView()
                } label: {
                    settingsRow("About", "Version, source and privacy", "info.circle")
                }
            }

            Section {
                Button(role: .destructive) {
                    runtime.requestViewerMode()
                } label: {
                    Label("Switch to Viewer", systemImage: "eye.fill")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } footer: {
                Text("Switching stops sensor collection, standalone recording, alarms and Live Activity, and pauses every upload destination. Your pairing, local history, settings and upload queues are kept.")
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .tint(prefs.theme.accentColor)
        .task { await runtime.uploads.refresh() }
    }

    private func settingsRow(_ title: String, _ detail: String, _ icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(prefs.theme.accentColor)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(.primary)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
