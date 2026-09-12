import SwiftUI
import UIKit

struct AlarmSettingsView: View {
    @ObservedObject var service: StandaloneAlarmService
    @EnvironmentObject private var prefs: PreferenceService
    @State private var adding = false
    @State private var editing: GlucoseAlarmRule?

    var body: some View {
        List {
            Section {
                Label(service.permissionDescription, systemImage: "bell.badge")
                    .font(.footnote)
                Text(service.schedulingDescription).font(.caption).foregroundStyle(.secondary)
                Button("Notification settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
            }
            Section("Your alarms") {
                ForEach(service.configuration.rules) { rule in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Button { editing = rule } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(rule.name).font(.body.weight(.medium))
                                    Text(summary(rule)).font(.caption).foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            Toggle(rule.name, isOn: Binding(get: { rule.enabled }, set: { enabled in
                                var updated = rule; updated.enabled = enabled; service.save(updated)
                            })).labelsHidden()
                        }
                        if service.activeRuleIDs.contains(rule.id) {
                            HStack {
                                Label("Active episode", systemImage: "bell.fill").font(.caption)
                                Spacer()
                                Button("Snooze") { service.snooze(rule.id) }
                                Button("Dismiss") { service.dismiss(rule.id) }
                            }.buttonStyle(.borderless)
                        }
                    }.padding(.vertical, 3)
                }.onDelete { indices in
                    let ids = indices.map { service.configuration.rules[$0].id }
                    ids.forEach(service.delete)
                }
                Button { adding = true } label: { Label("Add alarm", systemImage: "plus.circle.fill") }
            }
            Section {
                NavigationLink { AlarmGeneralSettingsView(service: service) } label: { Label("General settings", systemImage: "slider.horizontal.3") }
                NavigationLink { AlarmHistoryView(service: service) } label: { Label("Alarm history", systemImage: "clock.arrow.circlepath") }
            } footer: {
                Text("Alarms use current Bluetooth readings only. Up to four upcoming reminders per rule (48 total) are prepared for background delivery; glucose reminders never extend beyond the current reading’s freshness. iOS can delay delivery. Further reminders need new readings or the app to run. Check notification and Focus settings on your device.")
            }
        }
        .navigationTitle("Alarms")
        .tint(prefs.theme.accentColor)
        .sheet(isPresented: $adding) { AlarmTypeWizard(service: service).environmentObject(prefs) }
        .sheet(item: $editing) { rule in
            NavigationStack { AlarmRuleEditor(service: service, rule: rule) }.environmentObject(prefs)
        }
        .task { await service.refreshPermission() }
    }

    private func summary(_ rule: GlucoseAlarmRule) -> String {
        if rule.kind == .missing { return "No new readings for \(rule.missingMinutes) min" }
        let threshold = String(format: "%.1f mmol/L", rule.thresholdMMOL)
        return "\(rule.kind.isHigh ? "Above" : "Below") \(threshold)" + (rule.kind.isSustained ? " for \(rule.durationMinutes) min" : "")
    }
}

private struct AlarmTypeWizard: View {
    @ObservedObject var service: StandaloneAlarmService
    @EnvironmentObject private var prefs: PreferenceService
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(GlucoseAlarmKind.allCases) { kind in
                        NavigationLink {
                            AlarmRuleEditor(service: service,
                                rule: GlucoseAlarmRule(kind: kind, thresholdMMOL: kind.isHigh ? prefs.bgHigh : prefs.bgLow),
                                onSave: { dismiss() })
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Label(kind.title, systemImage: kind == .missing ? "antenna.radiowaves.left.and.right.slash" : kind.isHigh ? "arrow.up.circle" : "arrow.down.circle")
                                Text(kind.explanation).font(.caption).foregroundStyle(.secondary)
                            }.padding(.vertical, 4)
                        }
                    }
                } header: { Text("1 · Choose an alarm") } footer: { Text("You can create several alarms of the same type, each with its own threshold and schedule.") }
            }
            .navigationTitle("Add alarm")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }.tint(prefs.theme.accentColor)
    }
}

private struct AlarmRuleEditor: View {
    @ObservedObject var service: StandaloneAlarmService
    @State var rule: GlucoseAlarmRule
    var onSave: (() -> Void)?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section("Main settings") {
                TextField("Alarm name", text: $rule.name)
                Toggle("Enabled", isOn: $rule.enabled)
                if rule.kind != .missing {
                    Stepper(value: $rule.thresholdMMOL, in: 2...30, step: 0.1) {
                        Text("\(rule.kind.isHigh ? "Above" : "Below") \(rule.thresholdMMOL, specifier: "%.1f") mmol/L")
                    }
                }
                if rule.kind.isSustained { Stepper("For \(rule.durationMinutes) min", value: $rule.durationMinutes, in: 1...180) }
                if rule.kind == .missing { Stepper("No readings for \(rule.missingMinutes) min", value: $rule.missingMinutes, in: 1...120) }
            }
            Section {
                NavigationLink("Advanced settings") { AlarmAdvancedSettingsView(service: service, rule: $rule) }
            } footer: {
                Text("Uses \(rule.soundOverride?.title ?? service.configuration.general.sound.title). \(rule.repeats ? "Automatically snoozes and repeats every \(rule.interval(service.configuration.general)) min." : "Notifies once per episode.") Dismiss silences this episode until recovery and a new threshold crossing.")
            }
        }
        .navigationTitle(rule.kind.title)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { service.save(rule); if let onSave { onSave() } else { dismiss() } }
                    .disabled(rule.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
}

private struct AlarmGeneralSettingsView: View {
    @ObservedObject var service: StandaloneAlarmService
    private func binding<T>(_ keyPath: WritableKeyPath<AlarmGeneralSettings, T>) -> Binding<T> {
        Binding(get: { service.configuration.general[keyPath: keyPath] }, set: {
            var general = service.configuration.general; general[keyPath: keyPath] = $0; service.updateGeneral(general)
        })
    }
    var body: some View {
        Form {
            Section("Defaults for every alarm") {
                Picker("Sound", selection: binding(\.sound)) {
                    ForEach(GlucoseAlarmSound.allCases) { Text($0.title).tag($0) }
                }
                Stepper("Snooze · \(service.configuration.general.snoozeMinutes) min", value: binding(\.snoozeMinutes), in: 1...120)
                Toggle("Stop repeating on recovery", isOn: binding(\.stopRepeatingOnRecovery))
            }
            Section {
                Toggle("Override Do Not Disturb", isOn: binding(\.overrideDoNotDisturb))
            } footer: { Text(criticalExplanation) }
            Section {
                Text("Each alarm follows these values unless you choose an override in its advanced settings. Alarm thresholds remain independent of graph targets.")
            }.font(.footnote)
        }.navigationTitle("General settings")
    }
    private var criticalExplanation: String {
        service.criticalAlertsAvailable
            ? "Critical Alerts are permitted by iOS. Your selected alarm must also request this override."
            : "This saves your requested behavior. Do Not Disturb override is not available in this build without Apple’s Critical Alerts entitlement and your permission. Ordinary notifications follow Focus and silent-mode settings."
    }
}

private struct AlarmAdvancedSettingsView: View {
    @ObservedObject var service: StandaloneAlarmService
    @Binding var rule: GlucoseAlarmRule
    private var general: AlarmGeneralSettings { service.configuration.general }
    var body: some View {
        Form {
            Section("Repeat behavior") {
                Toggle("Repeat until stopped", isOn: $rule.repeats)
                if rule.repeats {
                    Toggle("Use snooze interval · \(rule.snooze(general)) min", isOn: Binding(
                        get: { rule.repeatMinutes == nil }, set: { rule.repeatMinutes = $0 ? nil : rule.snooze(general) }))
                    if rule.repeatMinutes != nil {
                        Stepper("Repeat every \(rule.repeatMinutes ?? 5) min", value: Binding(get: { rule.repeatMinutes ?? 5 }, set: { rule.repeatMinutes = $0 }), in: 1...120)
                    }
                }
                inheritedBool("Stop repeating on recovery", value: $rule.stopOnRecoveryOverride, resolved: general.stopRepeatingOnRecovery)
            }
            Section("Inherited settings") {
                Picker("Sound", selection: $rule.soundOverride) {
                    Text("Use default · \(general.sound.title)").tag(GlucoseAlarmSound?.none)
                    ForEach(GlucoseAlarmSound.allCases) { Text($0.title).tag(Optional($0)) }
                }
                Toggle("Use default snooze · \(general.snoozeMinutes) min", isOn: Binding(
                    get: { rule.snoozeOverride == nil }, set: { rule.snoozeOverride = $0 ? nil : general.snoozeMinutes }))
                if rule.snoozeOverride != nil {
                    Stepper("Snooze · \(rule.snooze(general)) min", value: Binding(get: { rule.snooze(general) }, set: { rule.snoozeOverride = $0 }), in: 1...120)
                }
                inheritedBool("Override Do Not Disturb", value: $rule.dndOverride, resolved: general.overrideDoNotDisturb)
                if !service.criticalAlertsAvailable { Text("Do Not Disturb override is requested only; Critical Alerts are not currently available.").font(.caption).foregroundStyle(.secondary) }
            }
            if rule.kind != .missing {
                Section {
                    Stepper(value: $rule.recoveryMarginMMOL, in: 0...2, step: 0.1) {
                        Text("Recovery margin · \(rule.recoveryMarginMMOL, specifier: "%.1f") mmol/L")
                    }
                } header: { Text("Recovery") } footer: {
                    Text("Default 0.3 mmol/L (about 5 mg/dL). Glucose must move this far inside the threshold to reset a sustained timer or rearm a dismissed alarm. Small fluctuations within the margin keep the condition active. Stale readings reset sustained timers.")
                }
            }
            Section {
                ForEach($rule.windows) { $window in
                    NavigationLink { AlarmWindowEditor(window: $window) } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(timeLabel(window.startMinute))–\(timeLabel(window.endMinute))")
                            Text(window.everyDay ? "Every day" : "\(window.weekdays.count) selected days").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }.onDelete { rule.windows.remove(atOffsets: $0) }
                Button { rule.windows.append(AlarmTimeWindow()) } label: { Label("Add time window", systemImage: "plus") }
            } header: { Text("Active time windows") } footer: {
                Text("No windows means always active. Any matching window activates the alarm. Overnight windows belong to their starting day. Repeats stop when the window closes. Valid readings before it opens count toward sustained duration.")
            }
            Section {
                Text("Manual Snooze checks the condition again when it expires. If glucose has recovered, it stays quiet even when automatic repeats are set to continue after recovery. Missing-reading alarms rearm when a fresh live reading arrives.")
            }.font(.footnote)
        }.navigationTitle("Advanced settings")
    }
    private func inheritedBool(_ title: String, value: Binding<Bool?>, resolved: Bool) -> some View {
        Picker(title, selection: value) {
            Text("Use default · \(resolved ? "On" : "Off")").tag(Bool?.none)
            Text("On").tag(Optional(true))
            Text("Off").tag(Optional(false))
        }
    }
    private func timeLabel(_ minute: Int) -> String { String(format: "%02d:%02d", minute / 60, minute % 60) }
}

private struct AlarmWindowEditor: View {
    @Binding var window: AlarmTimeWindow
    private func timeBinding(_ keyPath: WritableKeyPath<AlarmTimeWindow, Int>) -> Binding<Date> {
        Binding(get: { Calendar.current.startOfDay(for: Date()).addingTimeInterval(Double(window[keyPath: keyPath] * 60)) }, set: {
            window[keyPath: keyPath] = Calendar.current.component(.hour, from: $0) * 60 + Calendar.current.component(.minute, from: $0)
        })
    }
    var body: some View {
        Form {
            Section {
                DatePicker("From", selection: timeBinding(\.startMinute), displayedComponents: .hourAndMinute)
                DatePicker("Until", selection: timeBinding(\.endMinute), displayedComponents: .hourAndMinute)
                Picker("Days", selection: $window.everyDay) {
                    Text("Every day").tag(true)
                    Text("Specific days").tag(false)
                }
            } footer: { Text("Equal start and end times means the full selected day.") }
            if !window.everyDay {
                Section("Specific days") {
                    ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { day in
                        Button {
                            if window.weekdays.contains(day) { window.weekdays.remove(day) } else { window.weekdays.insert(day) }
                        } label: {
                            HStack {
                                Text(Calendar.current.weekdaySymbols[day - 1]).foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: window.weekdays.contains(day) ? "checkmark.square.fill" : "square")
                            }.contentShape(Rectangle())
                        }.accessibilityAddTraits(window.weekdays.contains(day) ? .isSelected : [])
                    }
                }
            }
        }.navigationTitle("Time window")
    }
}

private struct AlarmHistoryView: View {
    @ObservedObject var service: StandaloneAlarmService
    var body: some View {
        List {
            if service.history.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "bell").font(.largeTitle).foregroundStyle(.secondary)
                    Text("No alarm events").font(.headline)
                    Text("Notification requests, dismissals and snoozes appear here.")
                        .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }.frame(maxWidth: .infinity).padding(.vertical, 24)
            } else {
                Section {
                    ForEach(service.history) { event in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(event.ruleName).font(.headline)
                            Text(event.detail).font(.subheadline)
                            Text(event.date, format: .dateTime.month().day().hour().minute()).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                } footer: { Text("Up to 30 days and 1,000 recent events. A requested notification does not confirm delivery or an audible sound.") }
            }
        }.navigationTitle("Alarm history")
    }
}
