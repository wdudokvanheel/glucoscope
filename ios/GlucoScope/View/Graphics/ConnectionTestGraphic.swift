import SwiftUI

struct ThemedConnectionTestGraphic: View {
    @EnvironmentObject var prefs: PreferenceService

    let state: ConenctionTestState?

    var body: some View {
        ConnectionTestGraphic(state: state, background: prefs.theme.backgroundColor, iconFill: prefs.theme.textColor, pendingColor: prefs.theme.highColor, successColor: prefs.theme.inRangeColor, failColor: prefs.theme.lowColor)
    }
}

struct ConnectionTestGraphic: View {
    let state: ConenctionTestState?

    let background: Color
    let iconFill: Color
    let pendingColor: Color
    let successColor: Color
    let failColor: Color

    init(state: ConenctionTestState?, background: Color, iconFill: Color, pendingColor: Color, successColor: Color, failColor: Color) {
        self.state = state
        self.background = background
        self.iconFill = iconFill
        self.pendingColor = pendingColor
        self.successColor = successColor
        self.failColor = failColor
    }

    init(state: ConenctionTestState?) {
        self.iconFill = .white
        self.background = .black
        self.pendingColor = .orange
        self.successColor = .green
        self.failColor = .red
        self.state = state
    }

    var powerLightButton: Color {
        if self.state == .success {
            return self.successColor
        }

        if self.state == .pending {
            return self.pendingColor
        }

        return self.failColor
    }

    var body: some View {
        DynamicGraphic { gfx in
            Cloud()
                .foregroundStyle(self.iconFill)

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

            // App fill
            RoundedRectangle(cornerRadius: 16)
                .fill(self.iconFill)
                .position(x: gfx.width * 0.25, y: gfx.height * 0.75)
                .frame(width: gfx.width * 0.5, height: gfx.height * 0.5)

            // App overlay gradient
            RoundedRectangle(cornerRadius: 16)
                .fill(LinearGradient(colors: [.black.opacity(0), .black.opacity(0), .black.opacity(0.15)], startPoint: UnitPoint(x: 0.5, y: 0.65), endPoint: UnitPoint(x: 0.5, y: 1.0)))
                .position(x: gfx.width * 0.25, y: gfx.height * 0.75)
                .frame(width: gfx.width * 0.5, height: gfx.height * 0.5)

            BurgerMenu(background: self.background, foreground: self.iconFill)

            PowerLightIcon(color: self.powerLightButton)


            switch self.state {
                case .success:
                    Check()
                        .stroke(self.successColor, style: StrokeStyle(lineWidth: gfx.lineWidth, lineCap: .round, lineJoin: .round))
                case .failed:
                    Cross()
                        .stroke(self.failColor, style: StrokeStyle(lineWidth: gfx.lineWidth, lineCap: .round, lineJoin: .round))
                case _:
                    Drop(fill: self.failColor)
            }
        }
    }
}

private struct Drop: View {
    let fill: Color

    var body: some View {
        DropShape()
            .foregroundStyle(self.fill)

        DropShape()
            .fill(
                LinearGradient(
                    gradient: Gradient(colors: [
                        .black.opacity(0),
                        .black.opacity(0.5)
                    ]),
                    startPoint: UnitPoint(x: 0.5, y: DropShape.top),
                    endPoint: UnitPoint(x: 0.5, y: DropShape.bottom)
                )
            )
    }
}

private struct DropShape: Shape {
    public static let left: CGFloat = 0.43066
    public static let right: CGFloat = 0.55566
    public static let top: CGFloat = 0.46976
    public static let bottom: CGFloat = 0.63867

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height

        let leftX = Self.left * w
        let rightX = Self.right * w
        let topY = Self.top * h
        let bottomY = Self.bottom * h

        path.move(to: CGPoint(x: leftX, y: 0.57584 * h))
        path.addCurve(
            to: CGPoint(x: 0.48716 * w, y: topY),
            control1: CGPoint(x: leftX, y: 0.54778 * h),
            control2: CGPoint(x: 0.47151 * w, y: 0.49063 * h)
        )
        path.addCurve(
            to: CGPoint(x: 0.49917 * w, y: topY),
            control1: CGPoint(x: 0.49019 * w, y: 0.46572 * h),
            control2: CGPoint(x: 0.49613 * w, y: 0.46572 * h)
        )
        path.addCurve(
            to: CGPoint(x: rightX, y: 0.57584 * h),
            control1: CGPoint(x: 0.51481 * w, y: 0.49063 * h),
            control2: CGPoint(x: rightX, y: 0.54778 * h)
        )
        path.addCurve(
            to: CGPoint(x: 0.49316 * w, y: bottomY),
            control1: CGPoint(x: rightX, y: 0.61054 * h),
            control2: CGPoint(x: 0.52768 * w, y: bottomY)
        )
        path.addCurve(
            to: CGPoint(x: leftX, y: 0.57584 * h),
            control1: CGPoint(x: 0.45865 * w, y: bottomY),
            control2: CGPoint(x: leftX, y: 0.61054 * h)
        )

        return path
    }
}

private struct Check: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.size.width
        let height = rect.size.height
        path.move(to: CGPoint(x: 0.37305 * width, y: 0.54568 * height))
        path.addLine(to: CGPoint(x: 0.46342 * width, y: 0.63822 * height))
        path.addCurve(to: CGPoint(x: 0.46622 * width, y: 0.63822 * height), control1: CGPoint(x: 0.46419 * width, y: 0.639 * height), control2: CGPoint(x: 0.46545 * width, y: 0.639 * height))
        path.addLine(to: CGPoint(x: 0.62695 * width, y: 0.47363 * height))

        return path
    }
}

private struct Cross: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.size.width
        let height = rect.size.height
        path.move(to: CGPoint(x: 0.57991 * width, y: 0.63965 * height))
        path.addLine(to: CGPoint(x: 0.41978 * width, y: 0.47363 * height))
        path.move(to: CGPoint(x: 0.58301 * width, y: 0.47363 * height))
        path.addLine(to: CGPoint(x: 0.41699 * width, y: 0.63965 * height))
        return path
    }
}

private struct BurgerMenu: View {
    let background: Color
    let foreground: Color

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let barW = 0.0625 * w
            let barH = 0.01563 * h
            let xOff = 0.64258 * w
            let ys: [CGFloat] = [0.80273, 0.82959].map { $0 * h }

            ZStack {
                ForEach(ys, id: \.self) { y in
                    RoundedRectangle(cornerRadius: 32)
                        .fill(.shadow(.inner(color: self.foreground, radius: 1, y: 2)))
                        .foregroundStyle(self.background)
                        .frame(width: barW, height: barH)
                        .cornerRadius(32)
                        .offset(x: xOff, y: y)
                }
            }
        }
    }
}

struct PowerLightIcon: View {
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            let lightW = 0.0625 * w
            let lightH = 0.03125 * h
            let lightX = 0.29492 * w
            let lightY = 0.80273 * h

            RoundedRectangle(cornerRadius: lightH / 2)
                .fill(self.color)
                .overlay(
                    RadialGradient(
                        gradient: Gradient(colors: [
                            .white.opacity(0.15),
                            .white.opacity(0)
                        ]),
                        center: .center,
                        startRadius: 0,
                        endRadius: max(lightW, lightH) / 2
                    )
                )
                .frame(width: lightW, height: lightH)
                .offset(x: lightX, y: lightY)
                .shadow(color: self.color.opacity(0.75), radius: 4)
        }
    }
}

private struct App: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.size.width
        let height = rect.size.height
        path.addRect(CGRect(x: 0.25 * width, y: 0.75 * height, width: 0.5 * width, height: 0.5 * height))
        path.addRect(CGRect(x: 0.29492 * width, y: 0.80273 * height, width: 0.0625 * width, height: 0.03125 * height))
        path.addRect(CGRect(x: 0.64258 * width, y: 0.80273 * height, width: 0.0625 * width, height: 0.01563 * height))
        path.addRect(CGRect(x: 0.64258 * width, y: 0.82959 * height, width: 0.0625 * width, height: 0.01563 * height))
        return path
    }
}

private struct Cloud: Shape {
    public static let left: CGFloat = 0.26573
    public static let right: CGFloat = 0.73437
    public static let top: CGFloat = 0.06477
    public static let bottom: CGFloat = 0.36327

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height

        let leftX = Self.left * w
        let rightX = Self.right * w
        let topY = Self.top * h
        let bottomY = Self.bottom * h

        path.move(to: CGPoint(x: 0.65076 * w, y: bottomY))
        path.addLine(to: CGPoint(x: 0.35796 * w, y: bottomY))
        path.addCurve(
            to: CGPoint(x: 0.29514 * w, y: 0.33996 * h),
            control1: CGPoint(x: 0.33474 * w, y: 0.36357 * h),
            control2: CGPoint(x: 0.31228 * w, y: 0.35524 * h)
        )
        path.addCurve(
            to: CGPoint(x: leftX, y: 0.28107 * h),
            control1: CGPoint(x: 0.27801 * w, y: 0.32469 * h),
            control2: CGPoint(x: 0.26749 * w, y: 0.30363 * h)
        )
        path.addCurve(
            to: CGPoint(x: leftX, y: 0.27394 * h),
            control1: CGPoint(x: leftX, y: 0.27869 * h),
            control2: CGPoint(x: leftX, y: 0.27632 * h)
        )
        path.addCurve(
            to: CGPoint(x: 0.28143 * w, y: 0.22158 * h),
            control1: CGPoint(x: 0.26478 * w, y: 0.25527 * h),
            control2: CGPoint(x: 0.27032 * w, y: 0.23682 * h)
        )
        path.addCurve(
            to: CGPoint(x: 0.32703 * w, y: 0.18991 * h),
            control1: CGPoint(x: 0.29255 * w, y: 0.20633 * h),
            control2: CGPoint(x: 0.30861 * w, y: 0.19518 * h)
        )
        path.addCurve(
            to: CGPoint(x: 0.32703 * w, y: 0.18242 * h),
            control1: CGPoint(x: 0.32703 * w, y: 0.18736 * h),
            control2: CGPoint(x: 0.32703 * w, y: 0.18480 * h)
        )
        path.addCurve(
            to: CGPoint(x: 0.34778 * w, y: 0.11761 * h),
            control1: CGPoint(x: 0.32770 * w, y: 0.15937 * h),
            control2: CGPoint(x: 0.33488 * w, y: 0.13695 * h)
        )
        path.addCurve(
            to: CGPoint(x: 0.40013 * w, y: 0.07282 * h),
            control1: CGPoint(x: 0.36068 * w, y: 0.09828 * h),
            control2: CGPoint(x: 0.37879 * w, y: 0.08278 * h)
        )
        path.addCurve(
            to: CGPoint(x: 0.47374 * w, y: topY),
            control1: CGPoint(x: 0.42323 * w, y: 0.06280 * h),
            control2: CGPoint(x: 0.44894 * w, y: 0.05999 * h)
        )
        path.addCurve(
            to: CGPoint(x: 0.53866 * w, y: 0.09949 * h),
            control1: CGPoint(x: 0.49853 * w, y: 0.06954 * h),
            control2: CGPoint(x: 0.52121 * w, y: 0.08167 * h)
        )
        path.addCurve(
            to: CGPoint(x: 0.56697 * w, y: 0.14041 * h),
            control1: CGPoint(x: 0.55059 * w, y: 0.11133 * h),
            control2: CGPoint(x: 0.56018 * w, y: 0.12520 * h)
        )
        path.addCurve(
            to: CGPoint(x: 0.59051 * w, y: 0.12932 * h),
            control1: CGPoint(x: 0.57378 * w, y: 0.13491 * h),
            control2: CGPoint(x: 0.58186 * w, y: 0.13110 * h)
        )
        path.addCurve(
            to: CGPoint(x: 0.61665 * w, y: 0.13018 * h),
            control1: CGPoint(x: 0.59917 * w, y: 0.12754 * h),
            control2: CGPoint(x: 0.60814 * w, y: 0.12783 * h)
        )
        path.addCurve(
            to: CGPoint(x: 0.64788 * w, y: 0.15270 * h),
            control1: CGPoint(x: 0.62914 * w, y: 0.13446 * h),
            control2: CGPoint(x: 0.64003 * w, y: 0.14231 * h)
        )
        path.addCurve(
            to: CGPoint(x: 0.66070 * w, y: 0.18845 * h),
            control1: CGPoint(x: 0.65574 * w, y: 0.16309 * h),
            control2: CGPoint(x: 0.66021 * w, y: 0.17555 * h)
        )
        path.addCurve(
            to: CGPoint(x: 0.71385 * w, y: 0.21833 * h),
            control1: CGPoint(x: 0.68150 * w, y: 0.19193 * h),
            control2: CGPoint(x: 0.70034 * w, y: 0.20252 * h)
        )
        path.addCurve(
            to: CGPoint(x: rightX, y: 0.27468 * h),
            control1: CGPoint(x: 0.72735 * w, y: 0.23413 * h),
            control2: CGPoint(x: rightX, y: 0.25411 * h)
        )
        path.addCurve(
            to: CGPoint(x: 0.65076 * w, y: bottomY),
            control1: CGPoint(x: rightX, y: 0.35560 * h),
            control2: CGPoint(x: 0.65170 * w, y: 0.36309 * h)
        )
        path.closeSubpath()

        return path
    }
}
