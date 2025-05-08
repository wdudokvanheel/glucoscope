import SwiftUI

struct ThemedDivider: View{
    @EnvironmentObject var prefs: PreferenceService
    
    var body: some View{
        Divider()
            .overlay(prefs.theme.backgroundColor.colorInvert().opacity(0.5))
    }
}
    
