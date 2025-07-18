import Combine
import Foundation
import SwiftUI

enum GlucoScopePreferenceKey: String {
    case connection
    case graph
    case theme
    case bgLow
    case bgHigh
    case bgUpper
}

struct GraphSettings: Encodable, Decodable, Equatable {
    let boundsLower: Double
    let boundsHigher: Double
}

let defaultTheme = Theme(
    name: "Default",
    variant: "",
    url: "",
    background: Color.black.toHex(),
    surface: "#1a1a1c",
    accent: Color.teal.toHex(),
    text: Color.white.toHex(),
    low: Color.red.toHex(),
    inRange: Color.green.toHex(),
    high: Color.yellow.toHex(),
    upper: Color.red.toHex(),
    indicatorLabel: Color.black.toHex(),
    indicatorIcon: Color.black.toHex(),
    gridLinesX: Color.gray.opacity(0.5).toHex(),
    gridLinesY: Color.gray.opacity(0.5).toHex(),
    labelAxisX: Color.gray.toHex(),
    labelAxisY: Color.gray.toHex()
)

let defaultGraph = GraphSettings(boundsLower: 2.5, boundsHigher: 20.0)

class PreferenceService: ObservableObject {
    @Preference(key: .connection, defaultValue: nil)
    var connection: String?

    @Preference(key: .graph, defaultValue: defaultGraph)
    var graph: GraphSettings

    @Preference(key: .theme, defaultValue: defaultTheme)
    var theme: Theme

    @Preference(key: .bgLow, defaultValue: 4.0)
    var bgLow: Double

    @Preference(key: .bgHigh, defaultValue: 7.0)
    var bgHigh: Double

    @Preference(key: .bgUpper, defaultValue: 10.0)
    var bgUpper: Double

    private var cancellables = Set<AnyCancellable>()

    init() {
        // Propegate any changes to prefences to the observers of this service
        self.listenForChanges(_connection, _graph, _theme, _bgLow, _bgHigh, _bgUpper)
    }

    func listenForChanges<each V>(
        _ prefs: repeat Preference<each V>
    ) {
        var publishers: [AnyPublisher<Void, Never>] = []

        for pref in repeat each prefs {                             // ②
            publishers.append(
                pref.publisher.map { _ in () }.eraseToAnyPublisher()
            )
        }

        Publishers.MergeMany(publishers)
            .sink { _ in self.objectWillChange.send() }
            .store(in: &cancellables)
    }
}

extension Theme {
    var isLight: Bool {
        #if os(iOS) || os(tvOS) || os(watchOS)
        let native = UIColor(backgroundColor)
        #elseif os(macOS)
        let native = NSColor(backgroundColor)
        #endif

        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        native.getRed(&r, green: &g, blue: &b, alpha: &a)

        // Euclidean distance in RGB space
        let distanceToWhite = sqrt(pow(1 - r, 2) + pow(1 - g, 2) + pow(1 - b, 2))
        let distanceToBlack = sqrt(pow(r, 2) + pow(g, 2) + pow(b, 2))

        return distanceToWhite < distanceToBlack
    }

    var backgroundColor: Color {
        Color(hex: background)
    }

    var surfaceColor: Color {
        Color(hex: surface)
    }

    var textColor: Color {
        Color(hex: text)
    }

    var accentColor: Color {
        Color(hex: accent)
    }

    var lowColor: Color {
        Color(hex: low)
    }

    var inRangeColor: Color {
        Color(hex: inRange)
    }

    var highColor: Color {
        Color(hex: high)
    }

    var upperColor: Color {
        Color(hex: upper)
    }

    var indicatorLabelColor: Color {
        Color(hex: indicatorLabel)
    }

    var indicatorIconColor: Color {
        Color(hex: indicatorIcon)
    }

    var gridLinesXColor: Color {
        Color(hex: gridLinesX)
    }

    var gridLinesYColor: Color {
        Color(hex: gridLinesY)
    }

    var labelAxisXColor: Color {
        Color(hex: labelAxisX)
    }

    var labelAxisYColor: Color {
        Color(hex: labelAxisY)
    }
}
