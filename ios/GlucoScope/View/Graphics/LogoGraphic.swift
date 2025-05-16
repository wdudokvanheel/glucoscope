import SwiftUI

struct ThemedLogoGraphic: View {
    @EnvironmentObject var prefs: PreferenceService

    var body: some View {
        let light = prefs.theme.isLight ? prefs.theme.surfaceColor : prefs.theme.textColor
        let stroke = prefs.theme.isLight ? prefs.theme.textColor : prefs.theme.surfaceColor

        LogoGraphic(fill: prefs.theme.lowColor, stroke: stroke, light: light, background: light)
    }
}

struct LogoGraphic: View {
    let background: Color
    let dropFill: Color
    let dropStroke: Color

    let reflectionFill: Color
    let graphNodesFill: Color

    let graphNodesStroke = Color(hex: "#D9D9D9")

    init() {
        self.background = .white
        self.dropFill = .red
        self.dropStroke = Color(hex: "#323C4B")
        self.reflectionFill = .white
        self.graphNodesFill = .white
    }

    init(fill: Color, stroke: Color, light: Color, background: Color) {
        self.background = background
        self.dropFill = fill
        self.dropStroke = stroke
        self.reflectionFill = light
        self.graphNodesFill = light
    }

    var body: some View {
        GeometryReader { geom in
            let lineWidth = ((geom.size.width / 376)*16)

            ZStack(alignment: .top) {
                // Background rectangle
                RoundedRectangle(cornerRadius: 16)
                    .fill(background)

                // Background gradient overlay
                RoundedRectangle(cornerRadius: 16)
                    .fill(LinearGradient(colors: [.black.opacity(0), .black.opacity(0), .black.opacity(0.15)], startPoint: UnitPoint(x: 0.5, y: 0.65), endPoint: UnitPoint(x: 0.5, y: 1.0)))

//                    RoundedRectangle(cornerRadius: 16)
//                        .stroke(self.dropStroke, style: StrokeStyle(lineWidth: lineWidth))

                BurgerMenu(foreground: dropStroke, background: background)

                PowerLight(color: dropFill)

                ZStack {
                    // Drop fill
                    Drop()
                        .fill(dropFill)

                    // Drop fill overlay (darker bottom)
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

                    // Drop stroke
                    Drop()
                        .stroke(
                            dropStroke,
                            style: StrokeStyle(
                                lineWidth: lineWidth,
                                lineCap: .round,
                                lineJoin: .round
                            )
                        )

                    // Drop stroke overlay
                    Drop()
                        .stroke(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    .black.opacity(0),
                                    .black.opacity(0.3)
                                ]),
                                startPoint: UnitPoint(x: 0.5, y: Drop.top),
                                endPoint: UnitPoint(x: 0.5, y: Drop.bottom)
                            ),
                            style: StrokeStyle(
                                lineWidth: lineWidth,
                                lineCap: .round,
                                lineJoin: .round
                            )
                        )
                }

                Reflections()
                    .stroke(style: StrokeStyle(lineWidth: lineWidth*0.75, lineCap: .round))
                    .foregroundStyle(reflectionFill.opacity(0.9))

                // Render for the shadows first
                GraphNodes()
                    .stroke(style: StrokeStyle(lineWidth: lineWidth*0.75, lineCap: .round))
                    .shadow(color: .black.opacity(0.65), radius: 5, x: 0, y: 6)

                GraphLine()
                    .stroke(style: StrokeStyle(lineWidth: lineWidth*0.75, lineCap: .round))
                    .foregroundStyle(graphNodesFill)
                    .shadow(color: .black.opacity(0.65), radius: 5, x: 0, y: 6)

                ZStack {
                    // Nodes fill
                    GraphNodes()
                        .fill(graphNodesFill)
                    // Nodes outline
                    GraphNodes()
                        .stroke(style: StrokeStyle(lineWidth: lineWidth*0.75, lineCap: .round))
                        .foregroundStyle(graphNodesFill)
                    // Overlay to darken nodes
                    GraphNodes()
                        .stroke(style: StrokeStyle(lineWidth: lineWidth*0.75, lineCap: .round))
                        .foregroundStyle(Color.black.opacity(0.2))
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

private struct Drop: Shape {
    public static let top = 0.12971
    public static let bottom = 0.87891

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.size.width
        let height = rect.size.height
        path.move(to: CGPoint(x: 0.23047*width, y: 0.60986*height))
        path.addCurve(to: CGPoint(x: 0.49353*width, y: Self.top*height), control1: CGPoint(x: 0.23047*width, y: 0.47446*height), control2: CGPoint(x: 0.45388*width, y: 0.18077*height))
        path.addCurve(to: CGPoint(x: 0.50549*width, y: Self.top*height), control1: CGPoint(x: 0.49662*width, y: 0.12574*height), control2: CGPoint(x: 0.5024*width, y: 0.12574*height))
        path.addCurve(to: CGPoint(x: 0.76855*width, y: 0.60986*height), control1: CGPoint(x: 0.54514*width, y: 0.18077*height), control2: CGPoint(x: 0.76855*width, y: 0.47446*height))
        path.addCurve(to: CGPoint(x: 0.49951*width, y: 0.87891*height), control1: CGPoint(x: 0.76855*width, y: 0.75845*height), control2: CGPoint(x: 0.6481*width, y: 0.87891*height))
        path.addCurve(to: CGPoint(x: 0.23047*width, y: 0.60986*height), control1: CGPoint(x: 0.35092*width, y: 0.87891*height), control2: CGPoint(x: 0.23047*width, y: 0.75845*height))
        path.closeSubpath()
        return path
    }
}

private struct Reflections: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.size.width
        let height = rect.size.height
        path.move(to: CGPoint(x: 0.49365*width, y: 0.21973*height))
        path.addCurve(to: CGPoint(x: 0.46484*width, y: 0.2627*height), control1: CGPoint(x: 0.49365*width, y: 0.21973*height), control2: CGPoint(x: 0.47656*width, y: 0.24365*height))
        path.move(to: CGPoint(x: 0.34473*width, y: 0.46094*height))
        path.addCurve(to: CGPoint(x: 0.29834*width, y: 0.57617*height), control1: CGPoint(x: 0.34473*width, y: 0.46094*height), control2: CGPoint(x: 0.30322*width, y: 0.53174*height))
        path.move(to: CGPoint(x: 0.43066*width, y: 0.31299*height))
        path.addCurve(to: CGPoint(x: 0.37256*width, y: 0.4082*height), control1: CGPoint(x: 0.43066*width, y: 0.31299*height), control2: CGPoint(x: 0.39502*width, y: 0.36768*height))
        return path
    }
}

struct GraphNodes: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.size.width
        let height = rect.size.height
        path.addEllipse(in: CGRect(x: 0.61914*width, y: 0.54492*height, width: 0.0625*width, height: 0.0625*height))
        path.addEllipse(in: CGRect(x: 0.35156*width, y: 0.65332*height, width: 0.0625*width, height: 0.0625*height))
        return path
    }
}

struct GraphLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.size.width
        let height = rect.size.height
        path.move(to: CGPoint(x: 0.38623*width, y: 0.68506*height))
        path.addLine(to: CGPoint(x: 0.44216*width, y: 0.68506*height))
        path.addCurve(to: CGPoint(x: 0.44757*width, y: 0.68289*height), control1: CGPoint(x: 0.44418*width, y: 0.68506*height), control2: CGPoint(x: 0.44611*width, y: 0.68429*height))
        path.addCurve(to: CGPoint(x: 0.50928*width, y: 0.63037*height), control1: CGPoint(x: 0.45818*width, y: 0.67273*height), control2: CGPoint(x: 0.50283*width, y: 0.63037*height))
        path.addCurve(to: CGPoint(x: 0.55957*width, y: 0.66846*height), control1: CGPoint(x: 0.5166*width, y: 0.63037*height), control2: CGPoint(x: 0.5498*width, y: 0.66846*height))
        path.addCurve(to: CGPoint(x: 0.65*width, y: 0.57666*height), control1: CGPoint(x: 0.56934*width, y: 0.66846*height), control2: CGPoint(x: 0.65*width, y: 0.57666*height))
        return path
    }
}

struct PowerLight: View {
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let lightW = 0.125*w
            let lightH = 0.0625*h
            let lightX = 0.08984*w
            let lightY = 0.10547*h

            Rectangle()
                .fill(color)
                .overlay(
                    RadialGradient(
                        gradient: Gradient(colors: [
                            .white.opacity(0.15),
                            .white.opacity(0.0)
                        ]),
                        center: .center,
                        startRadius: 0,
                        endRadius: max(lightW, lightH) / 2
                    )
                )
                .frame(width: lightW, height: lightH)
                .cornerRadius(32)
                .offset(x: lightX, y: lightY)
                .shadow(color: color.opacity(0.75), radius: 4)
        }
    }
}

struct BurgerMenu: View {
    let foreground: Color
    let background: Color

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let barW = 0.125*w
            let barH = 0.03125*h
            let xOff = 0.78516*w
            let ys: [CGFloat] = [0.10547, 0.15918].map { $0*h }

            ZStack {
                ForEach(ys, id: \.self) { y in
                    RoundedRectangle(cornerRadius: 32)
                        .fill(.shadow(.inner(color: background, radius: 1, y: 2)))
                        .foregroundStyle(foreground)
                        .overlay(
                            LinearGradient(
                                gradient: Gradient(colors: [.black.opacity(0.3), .black.opacity(0)]),
                                startPoint: .topTrailing,
                                endPoint: .bottomLeading
                            )
                        )
                        .frame(width: barW, height: barH)
                        .cornerRadius(32)
                        .offset(x: xOff, y: y)
                }
            }
        }
    }
}
