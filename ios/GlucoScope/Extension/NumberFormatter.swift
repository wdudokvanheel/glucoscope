import Foundation

extension NumberFormatter {
    static var decimal: NumberFormatter {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f
    }
}
