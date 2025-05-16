import SwiftUI

struct ThemedConnectionTypeGraphic: View {
    @EnvironmentObject var prefs: PreferenceService

    var body: some View {
        ConnectionTypeGraphic(dropFill: prefs.theme.lowColor, stroke: prefs.theme.surfaceColor, cloud: prefs.theme.textColor, accent: prefs.theme.accentColor)
    }
}

struct ConnectionTypeGraphic: View {
    let dropFill: Color
    let cloudFill: Color
    let cloudStroke: Color
    let lineStroke: Color
    let toggleStroke: Color
    let toggleSelector: Color

    init(dropFill: Color, stroke: Color, cloud: Color, accent: Color) {
        self.dropFill = dropFill
        self.cloudFill = cloud
        self.lineStroke = accent
        self.toggleSelector = accent
        self.cloudStroke = stroke
        self.toggleStroke = stroke
    }

    init() {
        self.dropFill = .red
        self.cloudFill = .white
        self.cloudStroke = .gray
        self.lineStroke = .white
        self.toggleStroke = .gray
        self.toggleSelector = .purple
    }

    var body: some View {
        GeometryReader { geom in
            let lineWidth = ((geom.size.width / 376) * 16)

            ZStack {
                Drop()
                    .foregroundStyle(dropFill)

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

                Drop()
                    .stroke(toggleStroke, style: StrokeStyle(lineWidth: lineWidth * 0.5, lineCap: .round, lineJoin: .round))

                // Drop stroke overlay
                Drop()
                    .stroke(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                .black.opacity(0),
                                .black.opacity(0.5)
                            ]),
                            startPoint: UnitPoint(x: 0.5, y: Drop.top),
                            endPoint: UnitPoint(x: 0.5, y: Drop.bottom)
                        ),
                        style: StrokeStyle(
                            lineWidth: lineWidth * 0.5,
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )

                Cloud()
                    .foregroundStyle(cloudFill)

                Cloud()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                .black.opacity(0),
                                .black.opacity(0.15)
                            ]),
                            startPoint: UnitPoint(x: 0.5, y: Cloud.top + 0.1),
                            endPoint: UnitPoint(x: 0.5, y: Cloud.bottom)
                        )
                    )

                Cloud()
                    .stroke(toggleStroke, style: StrokeStyle(lineWidth: lineWidth * 0.5, lineCap: .round))

                LineTop()
                    .stroke(lineStroke, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            
                LineBottom()
                    .stroke(lineStroke, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))

                ToggleShape(stroke: toggleStroke, selector: self.toggleSelector, lineWidth: lineWidth)
            }
            .aspectRatio(1, contentMode: .fit)
        }
    }
}

private struct Drop: Shape {
    static let top: CGFloat = 0.13473
    static let bottom: CGFloat = 0.39063

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.size.width
        let height = rect.size.height

        path.move(to: CGPoint(x: 0.16504 * width, y: 0.29689 * height))
        path.addCurve(
            to: CGPoint(x: 0.25277 * width, y: Drop.top * height),
            control1: CGPoint(x: 0.16504 * width, y: 0.25312 * height),
            control2: CGPoint(x: 0.23207 * width, y: 0.16187 * height)
        )
        path.addCurve(
            to: CGPoint(x: 0.26480 * width, y: Drop.top * height),
            control1: CGPoint(x: 0.25583 * width, y: 0.13073 * height),
            control2: CGPoint(x: 0.26175 * width, y: 0.13073 * height)
        )
        path.addCurve(
            to: CGPoint(x: 0.35254 * width, y: 0.29689 * height),
            control1: CGPoint(x: 0.28551 * width, y: 0.16187 * height),
            control2: CGPoint(x: 0.35254 * width, y: 0.25312 * height)
        )
        path.addCurve(
            to: CGPoint(x: 0.25879 * width, y: Drop.bottom * height),
            control1: CGPoint(x: 0.35254 * width, y: 0.34866 * height),
            control2: CGPoint(x: 0.31057 * width, y: Drop.bottom * height)
        )
        path.addCurve(
            to: CGPoint(x: 0.16504 * width, y: 0.29689 * height),
            control1: CGPoint(x: 0.20701 * width, y: Drop.bottom * height),
            control2: CGPoint(x: 0.16504 * width, y: 0.34866 * height)
        )
        path.closeSubpath()

        return path
    }
}

private struct Cloud: Shape {
    static let top: CGFloat = 0.70441
    static let bottom: CGFloat = 0.87304

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.width
        let height = rect.height

        // ───── bottom edge ─────
        path.move(to: CGPoint(x: 0.32915 * width, y: Cloud.bottom * height))
        path.addLine(to: CGPoint(x: 0.17543 * width, y: Cloud.bottom * height))

        // ───── left hump ─────
        path.addCurve(
            to: CGPoint(x: 0.14245 * width, y: 0.85987 * height),
            control1: CGPoint(x: 0.16324 * width, y: 0.87321 * height),
            control2: CGPoint(x: 0.15145 * width, y: 0.86850 * height)
        )
        path.addCurve(
            to: CGPoint(x: 0.12701 * width, y: 0.82660 * height),
            control1: CGPoint(x: 0.13346 * width, y: 0.85125 * height),
            control2: CGPoint(x: 0.12793 * width, y: 0.83935 * height)
        )
        path.addCurve(
            to: CGPoint(x: 0.12701 * width, y: 0.82258 * height),
            control1: CGPoint(x: 0.12701 * width, y: 0.82526 * height),
            control2: CGPoint(x: 0.12701 * width, y: 0.82392 * height)
        )
        path.addCurve(
            to: CGPoint(x: 0.13525 * width, y: 0.79299 * height),
            control1: CGPoint(x: 0.12651 * width, y: 0.81203 * height),
            control2: CGPoint(x: 0.12942 * width, y: 0.80160 * height)
        )

        // ───── rising slope ─────
        path.addCurve(
            to: CGPoint(x: 0.15919 * width, y: 0.77511 * height),
            control1: CGPoint(x: 0.14109 * width, y: 0.78438 * height),
            control2: CGPoint(x: 0.14952 * width, y: 0.77808 * height)
        )
        path.addCurve(
            to: CGPoint(x: 0.15919 * width, y: 0.77087 * height),
            control1: CGPoint(x: 0.15919 * width, y: 0.77366 * height),
            control2: CGPoint(x: 0.15919 * width, y: 0.77222 * height)
        )
        path.addCurve(
            to: CGPoint(x: 0.17008 * width, y: 0.73426 * height),
            control1: CGPoint(x: 0.15954 * width, y: 0.75785 * height),
            control2: CGPoint(x: 0.16331 * width, y: 0.74518 * height)
        )

        // ───── top of the cloud ─────
        path.addCurve(
            to: CGPoint(x: 0.19757 * width, y: 0.70895 * height),
            control1: CGPoint(x: 0.17686 * width, y: 0.72334 * height),
            control2: CGPoint(x: 0.18637 * width, y: 0.71458 * height)
        )
        path.addCurve(
            to: CGPoint(x: 0.23621 * width, y: Cloud.top * height),
            control1: CGPoint(x: 0.20970 * width, y: 0.70330 * height),
            control2: CGPoint(x: 0.22319 * width, y: 0.70171 * height)
        )
        path.addCurve(
            to: CGPoint(x: 0.27030 * width, y: 0.72402 * height),
            control1: CGPoint(x: 0.24923 * width, y: 0.70710 * height),
            control2: CGPoint(x: 0.26114 * width, y: 0.71395 * height)
        )

        // ───── right‑hand bumps ─────
        path.addCurve(
            to: CGPoint(x: 0.28516 * width, y: 0.74714 * height),
            control1: CGPoint(x: 0.27656 * width, y: 0.73071 * height),
            control2: CGPoint(x: 0.28160 * width, y: 0.73854 * height)
        )
        path.addCurve(
            to: CGPoint(x: 0.29752 * width, y: 0.74087 * height),
            control1: CGPoint(x: 0.28873 * width, y: 0.74403 * height),
            control2: CGPoint(x: 0.29298 * width, y: 0.74188 * height)
        )
        path.addCurve(
            to: CGPoint(x: 0.31124 * width, y: 0.74136 * height),
            control1: CGPoint(x: 0.30206 * width, y: 0.73987 * height),
            control2: CGPoint(x: 0.30677 * width, y: 0.74003 * height)
        )
        path.addCurve(
            to: CGPoint(x: 0.32764 * width, y: 0.75408 * height),
            control1: CGPoint(x: 0.31780 * width, y: 0.74378 * height),
            control2: CGPoint(x: 0.32351 * width, y: 0.74821 * height)
        )
        path.addCurve(
            to: CGPoint(x: 0.33437 * width, y: 0.77428 * height),
            control1: CGPoint(x: 0.33176 * width, y: 0.75996 * height),
            control2: CGPoint(x: 0.33411 * width, y: 0.76699 * height)
        )
        path.addCurve(
            to: CGPoint(x: 0.36227 * width, y: 0.79116 * height),
            control1: CGPoint(x: 0.34529 * width, y: 0.77624 * height),
            control2: CGPoint(x: 0.35518 * width, y: 0.78223 * height)
        )
        path.addCurve(
            to: CGPoint(x: 0.37304 * width, y: 0.82299 * height),
            control1: CGPoint(x: 0.36936 * width, y: 0.80008 * height),
            control2: CGPoint(x: 0.37318 * width, y: 0.81137 * height)
        )

        // ───── close along bottom ─────
        path.addCurve(
            to: CGPoint(x: 0.32915 * width, y: Cloud.bottom * height),
            control1: CGPoint(x: 0.37304 * width, y: 0.86871 * height),
            control2: CGPoint(x: 0.32964 * width, y: 0.87294 * height)
        )
        path.closeSubpath()

        return path
    }
}

private struct ToggleShape: View {
    let stroke: Color
    let selector: Color
    let lineWidth: CGFloat

    var body: some View {
        GeometryReader { geom in
            let width = geom.size.width
            let height = geom.size.height

            ZStack {
                RoundedRectangle(cornerRadius: 32)
                    .foregroundStyle(selector)
                    .frame(
                        width: 0.23438 * width,
                        height: 0.10938 * height
                    )
                    .position(
                        x: 0.63086 * width + (0.23438 * width) / 2,
                        y: 0.44531 * height + (0.10938 * height) / 2
                    )

                RoundedRectangle(cornerRadius: 32)
                    .foregroundStyle(Color.black.opacity(0.5))
                    .frame(
                        width: 0.23438 * width,
                        height: 0.10938 * height
                    )
                    .position(
                        x: 0.63086 * width + (0.23438 * width) / 2,
                        y: 0.44531 * height + (0.10938 * height) / 2
                    )

                // Alt position: 0.6416
                RoundedRectangle(cornerRadius: 32)
                    .fill(selector)
                    .frame(
                        width: 0.10449 * width,
                        height: 0.08594 * height
                    )
                    .position(
                        x: 0.75 * width + (0.10449 * width) / 2,
                        y: 0.45703 * height + (0.08594 * height) / 2
                    )

                RoundedRectangle(cornerRadius: 32)
                    .stroke(stroke, style: StrokeStyle(lineWidth: lineWidth * 0.75, lineCap: .round))
                    .frame(
                        width: 0.23438 * width,
                        height: 0.10938 * height
                    )
                    .position(
                        x: 0.63086 * width + (0.23438 * width) / 2,
                        y: 0.44531 * height + (0.10938 * height) / 2
                    )
            }
        }
    }
}

private struct LineTop: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()

        let width = rect.size.width
        let height = rect.size.height

        let cornerRadius = 0.05 * width

        let start = CGPoint(x: 0.50391 * width, y: 0.19629 * height)
        let cornerCenter = CGPoint(x: 0.75391 * width - cornerRadius, y: 0.19629 * height + cornerRadius)
        let end = CGPoint(x: 0.75391 * width, y: 0.32129 * height)


        path.move(to: start)

        path.addLine(to: CGPoint(x: cornerCenter.x, y: start.y))

        path.addArc(
            center: cornerCenter,
            radius: cornerRadius,
            startAngle: .degrees(-90),
            endAngle: .degrees(0),
            clockwise: false
        )

        path.addLine(to: end)

        return path
    }
}

private struct LineBottom: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()

        let width = rect.size.width
        let height = rect.size.height

        let cornerRadius = 0.05 * width

        let start = CGPoint(x: 0.50391 * width, y: 0.80371 * height)
        let cornerCenter = CGPoint(x: 0.75391 * width - cornerRadius, y: 0.80371 * height - cornerRadius)
        let end = CGPoint(x: 0.75391 * width, y: 0.67871 * height)

        path.move(to: start)

        path.addLine(to: CGPoint(x: cornerCenter.x, y: start.y))

        path.addArc(
            center: cornerCenter,
            radius: cornerRadius,
            startAngle: .degrees(90),
            endAngle: .degrees(0),
            clockwise: true
        )

        path.addLine(to: end)

        return path
    }
}
