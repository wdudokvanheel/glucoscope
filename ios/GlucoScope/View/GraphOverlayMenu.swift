import SwiftUI

struct GraphOverlayMenu: View {
    @EnvironmentObject var prefs: PreferenceService
    let graphRangeSelected: (GraphRange) -> Void
    let range: GraphRange

    init(range: GraphRange, _ graphRangeSelected: @escaping (GraphRange) -> Void) {
        self.range = range
        self.graphRangeSelected = graphRangeSelected
    }

    var body: some View {
        OrientationAdaptiveView {
            VStack(alignment: .trailing) {
                Spacer()
                GraphRangeSelector(range, graphRangeSelected)
            }
        } landscape: {
            VStack(alignment: .trailing) {
                Spacer()
                HStack {
                    Spacer()
                    GraphRangeSelector(range, self.graphRangeSelected)
                        .fixedSize(horizontal: true, vertical: true)
                    Spacer()
                }
                .padding(.bottom, 4)
            }
        }
        .padding(.horizontal, 8)
    }
}
