import Foundation
import os
import SwiftUI

struct SettingsTab: Identifiable, Equatable {
    var id: String
    var label: String
    var icon: String
}

///  SwiftUI's TabView is hard to customize with dynamic colors, which the theming requires, so the SettingsView uses a custom tab view
struct SettingsView: View {
    @EnvironmentObject var prefs: PreferenceService
    @Environment(\.presentationMode) var presentationMode: Binding
    @State private var selectedTab: SettingsTab
    
    private let tabs: [SettingsTab] = [
        SettingsTab(id: "theme", label: "Themes", icon: "paintpalette.fill"),
        SettingsTab(id: "bgvalues", label: "Glucose values", icon: "drop.fill"),
        SettingsTab(id: "connection", label: "Connection", icon: "network"),
        SettingsTab(id: "about", label: "About", icon: "info.circle")
    ]

    init() {
        self.selectedTab = tabs[0]
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    switch self.selectedTab.id {
                    case "bgvalues":
                        GlucoseValuesSettingsView()
                    case "theme":
                        ThemeSettingsView()
                    case "connection":
                        ConnectionSettingsView()
                    case "about":
                        AboutView()
                    default:
                        Text("Select a setting below")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                HStack {
                    ForEach(tabs) { tab in
                        VStack {
                            Button(action: {
                                self.selectedTab = tab
                            }, label: {
                                VStack(spacing: 4) {
                                    Image(systemName: tab.icon)
                                        .font(.title2)
                                    Text(tab.label)
                                        .font(.caption)
                                }
                                .foregroundStyle(tab == selectedTab ? prefs.theme.accentColor : prefs.theme.textColor.opacity(0.65))
                            })
                        }
                        .padding(.top, 16)
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 50)
                .frame(maxWidth: .infinity)
                .background(prefs.theme.surfaceColor)
            }
            .edgesIgnoringSafeArea([])
        }
        .navigationBarItems(leading: backButton)
        .navigationBarBackButtonHidden()
        .navigationBarTitleDisplayMode(.inline)
        .accentColor(prefs.theme.accentColor)
        .background(prefs.theme.backgroundColor.ignoresSafeArea())
    }

    var backButton: some View {
        Button(action: {
            self.presentationMode.wrappedValue.dismiss()
        }) {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                Text("Back")
            }
            .foregroundColor(prefs.theme.accentColor)
        }
    }
}
