import SwiftUI

#if canImport(UIKit)
import UIKit

typealias SystemColor = UIColor
#elseif canImport(AppKit)
import AppKit

typealias SystemColor = NSColor
#endif

extension Color {
    init(hex: String) {
        var cleanedHex = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanedHex.hasPrefix("#") {
            cleanedHex.removeFirst()
        }
        cleanedHex = cleanedHex.uppercased()

        guard cleanedHex.count == 6 || cleanedHex.count == 8 else {
            // Fall back to transparent black
            self.init(.sRGB, red: 0, green: 0, blue: 0, opacity: 0)
            return
        }

        var rgbValue: UInt64 = 0
        guard Scanner(string: cleanedHex).scanHexInt64(&rgbValue) else {
            // Fall back to transparent black
            self.init(.sRGB, red: 0, green: 0, blue: 0, opacity: 0)
            return
        }

        let r, g, b, a: UInt64
        if cleanedHex.count == 6 {
            r = (rgbValue & 0xFF0000) >> 16
            g = (rgbValue & 0x00FF00) >> 8
            b = rgbValue & 0x0000FF
            a = 0xFF
        } else {
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

    func toHex(includeAlpha: Bool = false) -> String {
        #if os(iOS) || os(tvOS) || os(watchOS)
        let nativeColor = UIColor(self)
        guard let components = nativeColor.cgColor.components else {
            return includeAlpha ? "#00000000" : "#000000"
        }
        #elseif os(macOS)
        let nativeColor = NSColor(self)
        guard let deviceColor = nativeColor.usingColorSpace(.deviceRGB) else {
            return includeAlpha ? "#00000000" : "#000000"
        }
        let components = [deviceColor.redComponent,
                          deviceColor.greenComponent,
                          deviceColor.blueComponent,
                          deviceColor.alphaComponent]
        #endif

        // Extract RGBA
        let r = Float(components[0])
        let g = Float(components[1])
        let b = Float(components[2])
        let a = Float(components.count >= 4 ? components[3] : 1.0)

        // Create #RRGGBB or #RRGGBBAA
        if includeAlpha {
            return String(format: "#%02lX%02lX%02lX%02lX",
                          lroundf(r * 255),
                          lroundf(g * 255),
                          lroundf(b * 255),
                          lroundf(a * 255))
        } else {
            return String(format: "#%02lX%02lX%02lX",
                          lroundf(r * 255),
                          lroundf(g * 255),
                          lroundf(b * 255))
        }
    }
}
