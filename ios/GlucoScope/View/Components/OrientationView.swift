import SwiftUI

enum Orientation {
    case portrait
    case landscape
}

struct OrientationView<Content: View>: View {
    private let content: (Orientation) -> Content

    init(@ViewBuilder content: @escaping (Orientation) -> Content) {
        self.content = content
    }

    var body: some View {
        GeometryReader { geometry in
            let orientation: Orientation = geometry.size.height > geometry.size.width
                ? .portrait
                : .landscape

            content(orientation)
                .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }
}
