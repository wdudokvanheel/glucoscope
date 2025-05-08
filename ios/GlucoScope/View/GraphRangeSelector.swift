import SwiftUI

struct GraphRange: Identifiable, Equatable, Hashable {
    var id: Int { hours }
    let hours: Int
    let window: Int
}

struct GraphRangeSelector: View {
    @EnvironmentObject var prefs: PreferenceService
    @State var selectedRange: GraphRange = .init(hours: 12, window: 5)
    let onSelect: (GraphRange) -> Void

    let ranges: [GraphRange] = [
        GraphRange(hours: 24, window: 10),
        GraphRange(hours: 12, window: 5),
        GraphRange(hours: 9, window: 5),
        GraphRange(hours: 6, window: 5),
        GraphRange(hours: 3, window: 1),
    ]

    init(_ range: GraphRange, _ onSelect: @escaping (GraphRange) -> Void) {
        self._selectedRange = State(initialValue: range)
        self.onSelect = onSelect
    }

    var body: some View {
        Picker("Time", selection: $selectedRange) {
            ForEach(ranges) { range in
                Text("\(range.hours)h")
                    .tag(range)
            }
        }
        .foregroundStyle(.red)
        .pickerStyle(.segmented)
        .onAppear {
            UISegmentedControl.appearance().selectedSegmentTintColor = UIColor(prefs.theme.accentColor)
            UISegmentedControl.appearance().setTitleTextAttributes([.foregroundColor: UIColor(prefs.theme.indicatorLabelColor)], for: .selected)
            UISegmentedControl.appearance().setTitleTextAttributes([.foregroundColor: UIColor(prefs.theme.textColor)], for: .normal)
            UISegmentedControl.appearance().backgroundColor = UIColor(prefs.theme.backgroundColor)
        }
        .onChange(of: selectedRange) { newValue in
            onSelect(newValue)
        }
    }
}
