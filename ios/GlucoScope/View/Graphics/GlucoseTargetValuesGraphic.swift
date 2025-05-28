import SwiftUI

struct ThemedGlucoseTargetGraphic: View {
    @EnvironmentObject var prefs: PreferenceService

    var body: some View{
        GlucoseTargetValuesGraphic(drop: prefs.theme.lowColor, stroke: prefs.theme.accentColor)
    }
}

struct GlucoseTargetValuesGraphic: View {
    let drop: Color
    let stroke: Color

    var body: some View {
        DynamicGraphic { gfx in
            Drop()
                .foregroundStyle(drop)

            Drop()
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            .black.opacity(0),
                            .black.opacity(0.5)
                        ]),
                        startPoint: UnitPoint(x: 0.5, y: Drop.top),
                        endPoint: UnitPoint(x: 0.5, y: Drop.bottom)
                    )
                )

            Crosshair()
                .stroke(stroke, style: StrokeStyle(lineWidth: gfx.lineWidth * 0.5, lineCap: .round, lineJoin: .round))
        }
    }
}

private struct Crosshair: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.size.width
        let height = rect.size.height
        path.addEllipse(in: CGRect(x: 0.24292 * width, y: 0.24341 * height, width: 0.51367 * width, height: 0.51367 * height))
        path.addEllipse(in: CGRect(x: 0.12573 * width, y: 0.12622 * height, width: 0.74805 * width, height: 0.74805 * height))

        path.move(to: CGPoint(x: 0.49976 * width, y: 0.95239 * height))
        path.addLine(to: CGPoint(x: 0.49976 * width, y: 0.7688 * height))
        path.move(to: CGPoint(x: 0.49976 * width, y: 0.23267 * height))
        path.addLine(to: CGPoint(x: 0.49976 * width, y: 0.0481 * height))
        path.move(to: CGPoint(x: 0.9519 * width, y: 0.50024 * height))
        path.addLine(to: CGPoint(x: 0.76831 * width, y: 0.50024 * height))
        path.move(to: CGPoint(x: 0.2312 * width, y: 0.50024 * height))
        path.addLine(to: CGPoint(x: 0.04761 * width, y: 0.50024 * height))
        return path
    }
}

private struct Drop: Shape {
    static let top: CGFloat = 0.37305
    static let bottom: CGFloat = 0.63574

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.width
        let height = rect.height
        let topY = Drop.top * height
        let bottomY = Drop.bottom * height

        path.move(to: CGPoint(x: 0.4043 * width, y: 0.53958 * height))
        path.addCurve(
            to: CGPoint(x: 0.49398 * width, y: topY),
            control1: CGPoint(x: 0.4043 * width, y: 0.49459 * height),
            control2: CGPoint(x: 0.47299 * width, y: 0.40069 * height)
        )
        path.addCurve(
            to: CGPoint(x: 0.50602 * width, y: topY),
            control1: CGPoint(x: 0.49703 * width, y: 0.36903 * height),
            control2: CGPoint(x: 0.50297 * width, y: 0.36903 * height)
        )
        path.addCurve(
            to: CGPoint(x: 0.5957 * width, y: 0.53958 * height),
            control1: CGPoint(x: 0.52701 * width, y: 0.40069 * height),
            control2: CGPoint(x: 0.5957 * width, y: 0.49459 * height)
        )
        path.addCurve(
            to: CGPoint(x: 0.5 * width, y: bottomY),
            control1: CGPoint(x: 0.5957 * width, y: 0.59269 * height),
            control2: CGPoint(x: 0.55286 * width, y: bottomY)
        )
        path.addCurve(
            to: CGPoint(x: 0.4043 * width, y: 0.53958 * height),
            control1: CGPoint(x: 0.44714 * width, y: bottomY),
            control2: CGPoint(x: 0.4043 * width, y: 0.59269 * height)
        )
        path.closeSubpath()

        return path
    }
}
