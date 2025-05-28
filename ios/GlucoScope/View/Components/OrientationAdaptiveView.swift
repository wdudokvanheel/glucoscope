import SwiftUI

struct OrientationAdaptiveView<Portrait: View, Landscape: View>: View {
    private let portrait: Portrait
    private let landscape: Landscape

    init(
        @ViewBuilder portrait: () -> Portrait,
        @ViewBuilder landscape: () -> Landscape
    ) {
        self.portrait = portrait()
        self.landscape = landscape()
    }

    var body: some View {
        GeometryReader { geometry in
            Group {
                if geometry.size.height > geometry.size.width {
                    portrait
                } else {
                    landscape
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }
}
