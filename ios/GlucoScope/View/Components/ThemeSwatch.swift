import SwiftUI

struct ThemeSwatch: View {
    let theme: Theme
    
    init(_ theme: Theme) {
        self.theme = theme
    }

    var body: some View {
        HStack(spacing: 0) {
            theme.accentColor
            theme.highColor
            theme.upperColor
            theme.inRangeColor
        }
        .cornerRadius(4)
        .aspectRatio(2.5, contentMode: .fit)
        .fixedSize(horizontal: true, vertical: false)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(theme.backgroundColor, lineWidth: 3)
            )
    }
}
