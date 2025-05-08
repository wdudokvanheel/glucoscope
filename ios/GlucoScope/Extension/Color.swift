import SwiftUI

#if canImport(UIKit)
import UIKit
typealias SystemColor = UIColor
#elseif canImport(AppKit)
import AppKit
typealias SystemColor = NSColor
#endif

extension Color {
    
    /// Creates a SwiftUI Color from a hex string.
    /// - Parameter hex: A string in `#RRGGBB` or `#RRGGBBAA` format (the "#" is optional).
    init?(hex: String) {
        // Remove any leading "#" and make sure it’s uppercase.
        var cleanedHex = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanedHex.hasPrefix("#") {
            cleanedHex.removeFirst()
        }
        cleanedHex = cleanedHex.uppercased()
        
        // The string should be either 6 or 8 characters (RGB or RGBA).
        guard cleanedHex.count == 6 || cleanedHex.count == 8 else {
            return nil
        }
        
        var rgbValue: UInt64 = 0
        guard Scanner(string: cleanedHex).scanHexInt64(&rgbValue) else {
            return nil
        }
        
        let r, g, b, a: UInt64
        if cleanedHex.count == 6 {
            // RGB (6 characters)
            r = (rgbValue & 0xFF0000) >> 16
            g = (rgbValue & 0x00FF00) >> 8
            b = rgbValue & 0x0000FF
            a = 0xFF
        } else {
            // RGBA (8 characters)
            r = (rgbValue & 0xFF000000) >> 24
            g = (rgbValue & 0x00FF0000) >> 16
            b = (rgbValue & 0x0000FF00) >> 8
            a = rgbValue & 0x000000FF
        }
        
        self.init(
            .sRGB,
            red: Double(r) / 255.0,
            green: Double(g) / 255.0,
            blue: Double(b) / 255.0,
            opacity: Double(a) / 255.0
        )
    }
    
    /// Converts a SwiftUI Color to a hex string in #RRGGBB or #RRGGBBAA format (including the `#`).
    /// If you only need the RGB (without alpha), just omit alpha from the output.
    func toHex(includeAlpha: Bool = true) -> String? {
        // Convert SwiftUI Color -> CGColor -> SystemColor (UIColor/NSColor)
        guard let cgColor = self.cgColor else {
            return nil
        }
        
        #if os(iOS) || os(tvOS) || os(watchOS)
        let color = SystemColor(cgColor: cgColor)
        #else
        let color = SystemColor(cgColor: cgColor) ?? .black
        #endif
        
        guard let components = color.cgColor.components, components.count >= 3 else {
            return nil
        }
        
        // Extract the RGBA components
        let r = Float(components[0])
        let g = Float(components[1])
        let b = Float(components[2])
        let a = Float(components.count >= 4 ? components[3] : 1.0)
        
        // Create the hex string
        if includeAlpha {
            // #RRGGBBAA
            return String(
                format: "#%02lX%02lX%02lX%02lX",
                lroundf(r * 255),
                lroundf(g * 255),
                lroundf(b * 255),
                lroundf(a * 255)
            )
        } else {
            // #RRGGBB
            return String(
                format: "#%02lX%02lX%02lX",
                lroundf(r * 255),
                lroundf(g * 255),
                lroundf(b * 255)
            )
        }
    }
}
