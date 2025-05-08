import Foundation
import os
import SwiftUI

extension Color {
    /// Interpolates between two SwiftUI Colors.
    static func interpolate(from start: Color, to end: Color, fraction: CGFloat) -> Color {
        let clampedFraction = max(0, min(fraction, 1))  // Ensure fraction is [0, 1]
        
        // Convert both SwiftUI Colors to UIColor, then extract RGBA.
        let startUI = UIColor(start)
        let endUI = UIColor(end)
        
        var (sr, sg, sb, sa) = (CGFloat(0), CGFloat(0), CGFloat(0), CGFloat(0))
        var (er, eg, eb, ea) = (CGFloat(0), CGFloat(0), CGFloat(0), CGFloat(0))
        
        startUI.getRed(&sr, green: &sg, blue: &sb, alpha: &sa)
        endUI.getRed(&er, green: &eg, blue: &eb, alpha: &ea)
        
        // Interpolate each component
        let r = sr + (er - sr) * clampedFraction
        let g = sg + (eg - sg) * clampedFraction
        let b = sb + (eb - sb) * clampedFraction
        let a = sa + (ea - sa) * clampedFraction
        
        // Return the new SwiftUI Color
        return Color(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}
