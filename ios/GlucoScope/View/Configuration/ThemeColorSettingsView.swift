import SwiftUI

struct ThemeColorSettingsView: View {
    @EnvironmentObject var preferenceService: PreferenceService
    
    var body: some View {
        Form {
            Section(header: Text("Main colors")) {
                
                ColorPicker("Background", selection: Binding<Color>(
                    get: { preferenceService.theme.backgroundColor },
                    set: { newColor in
                        var updatedTheme = preferenceService.theme
                        updatedTheme.background = newColor.toHex()
                        preferenceService.theme = updatedTheme
                    }
                ))
                
                ColorPicker("Low", selection: Binding<Color>(
                    get: { preferenceService.theme.lowColor },
                    set: { newColor in
                        var updatedTheme = preferenceService.theme
                        updatedTheme.low = newColor.toHex()
                        preferenceService.theme = updatedTheme
                    }
                ))
                
                ColorPicker("In Range", selection: Binding<Color>(
                    get: { preferenceService.theme.inRangeColor },
                    set: { newColor in
                        var updatedTheme = preferenceService.theme
                        updatedTheme.inRange = newColor.toHex()
                        preferenceService.theme = updatedTheme
                    }
                ))
                
                ColorPicker("High", selection: Binding<Color>(
                    get: { preferenceService.theme.highColor },
                    set: { newColor in
                        var updatedTheme = preferenceService.theme
                        updatedTheme.high = newColor.toHex()
                        preferenceService.theme = updatedTheme
                    }
                ))
                
                ColorPicker("Upper", selection: Binding<Color>(
                    get: { preferenceService.theme.upperColor },
                    set: { newColor in
                        var updatedTheme = preferenceService.theme
                        updatedTheme.upper = newColor.toHex()
                        preferenceService.theme = updatedTheme
                    }
                ))
            }
            
            Section(header: Text("Graph")) {
                ColorPicker("Grid X-axis/Time", selection: Binding<Color>(
                    get: { preferenceService.theme.gridLinesXColor },
                    set: { newColor in
                        var updatedTheme = preferenceService.theme
                        updatedTheme.gridLinesX = newColor.toHex()
                        preferenceService.theme = updatedTheme
                    }
                ))
                
                ColorPicker("Grid Y-axis/Value", selection: Binding<Color>(
                    get: { preferenceService.theme.gridLinesYColor },
                    set: { newColor in
                        var updatedTheme = preferenceService.theme
                        updatedTheme.gridLinesY = newColor.toHex()
                        preferenceService.theme = updatedTheme
                    }
                ))
                
                ColorPicker("Label X-Axis/Time", selection: Binding<Color>(
                    get: { preferenceService.theme.labelAxisXColor },
                    set: { newColor in
                        var updatedTheme = preferenceService.theme
                        updatedTheme.labelAxisX = newColor.toHex()
                        preferenceService.theme = updatedTheme
                    }
                ))
                
                ColorPicker("Label Y-Axis/Value", selection: Binding<Color>(
                    get: { preferenceService.theme.labelAxisYColor },
                    set: { newColor in
                        var updatedTheme = preferenceService.theme
                        updatedTheme.labelAxisY = newColor.toHex()
                        preferenceService.theme = updatedTheme
                    }
                ))
            }
            
            Section(header: Text("Indicator")) {
                ColorPicker("Label", selection: Binding<Color>(
                    get: { preferenceService.theme.indicatorLabelColor },
                    set: { newColor in
                        var updatedTheme = preferenceService.theme
                        updatedTheme.indicatorLabel = newColor.toHex()
                        preferenceService.theme = updatedTheme
                    }
                ))
                
                ColorPicker("Icon", selection: Binding<Color>(
                    get: { preferenceService.theme.indicatorIconColor },
                    set: { newColor in
                        var updatedTheme = preferenceService.theme
                        updatedTheme.indicatorIcon = newColor.toHex()
                        preferenceService.theme = updatedTheme
                    }
                ))
            }
        }
        .navigationTitle("Theme")
    }
}
