import SwiftUI

struct DynamicGraphicInfo {
    let width: CGFloat
    let height: CGFloat
    let lineWidth: CGFloat
}

struct DynamicGraphic<Content: View>: View {
    private let content: (DynamicGraphicInfo) -> Content

    init(@ViewBuilder content: @escaping (DynamicGraphicInfo) -> Content) {
        self.content = content
    }

    var body: some View {
        GeometryReader { geom in
            let info = DynamicGraphicInfo(
                width: geom.size.width,
                height: geom.size.height,
                lineWidth: (geom.size.width / 376) * 16
            )
            ZStack {
                content(info)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}
