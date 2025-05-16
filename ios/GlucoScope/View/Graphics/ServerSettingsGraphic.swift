import SwiftUI

struct ServerSettingsGraphic: View {
    let cloudFill: Color
    let cloudStroke: Color
    let dropFill: Color
    let dropStroke: Color
    let gearsFill: Color

    init() {
        self.dropFill = .red
        self.dropStroke = .gray
        self.cloudFill = .white
        self.gearsFill = .white
        self.cloudStroke = .gray
    }

    var body: some View {
        GeometryReader { geom in
            let lineWidth = ((geom.size.width / 376) * 16)

            ZStack {
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
                    .stroke(dropStroke, style: StrokeStyle(lineWidth: lineWidth * 0.5, lineCap: .round, lineJoin: .round))

                Gears()
                    .stroke(cloudFill, style: StrokeStyle(lineWidth: lineWidth * 0.5, lineCap: .round, lineJoin: .round))
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

struct Gears: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.size.width
        let height = rect.size.height

        // --- gear teeth & spokes ---
        path.move(to: .init(x: 0.2989 * width, y: 0.73207 * height))
        path.addLine(to: .init(x: 0.25043 * width, y: 0.70732 * height))
        path.addCurve(
            to: .init(x: 0.22267 * width, y: 0.70699 * height),
            control1: .init(x: 0.24174 * width, y: 0.70288 * height),
            control2: .init(x: 0.23147 * width, y: 0.70276 * height)
        )
        path.addLine(to: .init(x: 0.20761 * width, y: 0.71424 * height))
        path.addCurve(
            to: .init(x: 0.17311 * width, y: 0.70927 * height),
            control1: .init(x: 0.19617 * width, y: 0.71975 * height),
            control2: .init(x: 0.18253 * width, y: 0.71778 * height)
        )
        path.addLine(to: .init(x: 0.14417 * width, y: 0.68314 * height))
        path.addCurve(
            to: .init(x: 0.13825 * width, y: 0.64398 * height),
            control1: .init(x: 0.13313 * width, y: 0.67316 * height),
            control2: .init(x: 0.13065 * width, y: 0.65678 * height)
        )
        path.addLine(to: .init(x: 0.14649 * width, y: 0.63012 * height))
        path.addCurve(
            to: .init(x: 0.14854 * width, y: 0.60232 * height),
            control1: .init(x: 0.1515 * width, y: 0.62169 * height),
            control2: .init(x: 0.15226 * width, y: 0.61139 * height)
        )
        path.addLine(to: .init(x: 0.13525 * width, y: 0.56984 * height))
        path.addCurve(
            to: .init(x: 0.11254 * width, y: 0.55106 * height),
            control1: .init(x: 0.13129 * width, y: 0.56018 * height),
            control2: .init(x: 0.12277 * width, y: 0.55314 * height)
        )
        path.addLine(to: .init(x: 0.10688 * width, y: 0.54991 * height))
        path.addCurve(
            to: .init(x: 0.08187 * width, y: 0.52052 * height),
            control1: .init(x: 0.09277 * width, y: 0.54704 * height),
            control2: .init(x: 0.08244 * width, y: 0.53491 * height)
        )
        path.addLine(to: .init(x: 0.08025 * width, y: 0.47966 * height))
        path.addCurve(
            to: .init(x: 0.10780 * width, y: 0.44739 * height),
            control1: .init(x: 0.07960 * width, y: 0.46340 * height),
            control2: .init(x: 0.09165 * width, y: 0.44936 * height)
        )
        path.addLine(to: .init(x: 0.10780 * width, y: 0.44739 * height))
        path.addCurve(
            to: .init(x: 0.13247 * width, y: 0.42943 * height),
            control1: .init(x: 0.11856 * width, y: 0.44608 * height),
            control2: .init(x: 0.12794 * width, y: 0.43928 * height)
        )
        path.addLine(to: .init(x: 0.14822 * width, y: 0.39521 * height))
        path.addCurve(
            to: .init(x: 0.14785 * width, y: 0.36832 * height),
            control1: .init(x: 0.15216 * width, y: 0.38665 * height),
            control2: .init(x: 0.15202 * width, y: 0.37677 * height)
        )
        path.addLine(to: .init(x: 0.13922 * width, y: 0.35082 * height))
        path.addCurve(
            to: .init(x: 0.14598 * width, y: 0.31409 * height),
            control1: .init(x: 0.13311 * width, y: 0.33842 * height),
            control2: .init(x: 0.13586 * width, y: 0.32349 * height)
        )
        path.addLine(to: .init(x: 0.16918 * width, y: 0.29255 * height))
        path.addCurve(
            to: .init(x: 0.20967 * width, y: 0.29082 * height),
            control1: .init(x: 0.18043 * width, y: 0.28211 * height),
            control2: .init(x: 0.19758 * width, y: 0.28138 * height)
        )
        path.addLine(to: .init(x: 0.21527 * width, y: 0.29518 * height))
        path.addCurve(
            to: .init(x: 0.24881 * width, y: 0.29833 * height),
            control1: .init(x: 0.22488 * width, y: 0.30268 * height),
            control2: .init(x: 0.23797 * width, y: 0.30391 * height)
        )
        path.addLine(to: .init(x: 0.28407 * width, y: 0.28016 * height))
        path.addCurve(
            to: .init(x: 0.29927 * width, y: 0.26266 * height),
            control1: .init(x: 0.29119 * width, y: 0.27649 * height),
            control2: .init(x: 0.29663 * width, y: 0.27022 * height)
        )
        path.addLine(to: .init(x: 0.30654 * width, y: 0.24179 * height))
        path.addCurve(
            to: .init(x: 0.33605 * width, y: 0.22082 * height),
            control1: .init(x: 0.31091 * width, y: 0.22924 * height),
            control2: .init(x: 0.32275 * width, y: 0.22082 * height)
        )
        path.addLine(to: .init(x: 0.36687 * width, y: 0.22082 * height))
        path.addCurve(
            to: .init(x: 0.39584 * width, y: 0.24035 * height),
            control1: .init(x: 0.37960 * width, y: 0.22082 * height),
            control2: .init(x: 0.39107 * width, y: 0.22855 * height)
        )
        path.addLine(to: .init(x: 0.40370 * width, y: 0.25978 * height))
        path.addCurve(
            to: .init(x: 0.41759 * width, y: 0.27544 * height),
            control1: .init(x: 0.40639 * width, y: 0.26644 * height),
            control2: .init(x: 0.41130 * width, y: 0.27197 * height)
        )
        path.addLine(to: .init(x: 0.45414 * width, y: 0.29556 * height))
        path.addCurve(
            to: .init(x: 0.48565 * width, y: 0.29477 * height),
            control1: .init(x: 0.46402 * width, y: 0.30100 * height),
            control2: .init(x: 0.47606 * width, y: 0.30070 * height)
        )
        path.addLine(to: .init(x: 0.49192 * width, y: 0.29089 * height))
        path.addCurve(
            to: .init(x: 0.52994 * width, y: 0.29487 * height),
            control1: .init(x: 0.50402 * width, y: 0.28341 * height),
            control2: .init(x: 0.51965 * width, y: 0.28504 * height)
        )
        path.addLine(to: .init(x: 0.55156 * width, y: 0.31553 * height))
        path.addCurve(
            to: .init(x: 0.55913 * width, y: 0.34938 * height),
            control1: .init(x: 0.56069 * width, y: 0.32425 * height),
            control2: .init(x: 0.56368 * width, y: 0.33761 * height)
        )
        path.addLine(to: .init(x: 0.55311 * width, y: 0.36498 * height))
        path.addCurve(
            to: .init(x: 0.55342 * width, y: 0.38828 * height),
            control1: .init(x: 0.55020 * width, y: 0.37250 * height),
            control2: .init(x: 0.55032 * width, y: 0.38084 * height)
        )
        path.addLine(to: .init(x: 0.57723 * width, y: 0.44527 * height))

        let circleX = 0.21660 * width
        let circleY = 0.36534 * height
        let circleW = (0.48456 - 0.21660) * width
        let circleH = (0.63369 - 0.36534) * height
        let circleRect = CGRect(x: circleX, y: circleY, width: circleW, height: circleH)
        let fullCircle = Path(ellipseIn: circleRect)
        let threeQuarter = fullCircle.trimmedPath(from: 0.25, to: 1.0)
        path.addPath(threeQuarter)

        return path
    }
}

private struct Drop: Shape {
    static let top: CGFloat = 0.13767
    static let bottom: CGFloat = 0.51172

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        let top = Self.top * h
        let bottom = Self.bottom * h

        path.move(to: CGPoint(x: 0.65039 * w, y: 0.37598 * h))
        path.addCurve(
            to: CGPoint(x: 0.77962 * w, y: top),
            control1: CGPoint(x: 0.65039 * w, y: 0.31057 * h),
            control2: CGPoint(x: 0.75337 * w, y: 0.17194 * h)
        )
        path.addCurve(
            to: CGPoint(x: 0.79168 * w, y: top),
            control1: CGPoint(x: 0.78268 * w, y: 0.13367 * h),
            control2: CGPoint(x: 0.78861 * w, y: 0.13367 * h)
        )
        path.addCurve(
            to: CGPoint(x: 0.9209 * w, y: 0.37598 * h),
            control1: CGPoint(x: 0.81793 * w, y: 0.17194 * h),
            control2: CGPoint(x: 0.9209 * w, y: 0.31057 * h)
        )
        path.addCurve(
            to: CGPoint(x: 0.78565 * w, y: bottom),
            control1: CGPoint(x: 0.9209 * w, y: 0.45095 * h),
            control2: CGPoint(x: 0.86034 * w, y: bottom)
        )
        path.addCurve(
            to: CGPoint(x: 0.65039 * w, y: 0.37598 * h),
            control1: CGPoint(x: 0.71095 * w, y: bottom),
            control2: CGPoint(x: 0.65039 * w, y: 0.45095 * h)
        )
        path.closeSubpath()

        return path
    }
}

private struct Cloud: Shape {
    static let top: CGFloat = 0.51442
    static let bottom: CGFloat = 0.87011

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.size.width
        let height = rect.size.height

        let top = Self.top * height
        let bottom = Self.bottom * height

        path.move(to: CGPoint(x: 0.82144 * width, y: bottom))
        path.addLine(to: CGPoint(x: 0.47312 * width, y: bottom))
        path.addCurve(
            to: CGPoint(x: 0.3984 * width, y: 0.84233 * height),
            control1: CGPoint(x: 0.4455 * width, y: 0.87046 * height),
            control2: CGPoint(x: 0.41878 * width, y: 0.86053 * height)
        )
        path.addCurve(
            to: CGPoint(x: 0.36341 * width, y: 0.77216 * height),
            control1: CGPoint(x: 0.37802 * width, y: 0.82414 * height),
            control2: CGPoint(x: 0.3655 * width, y: 0.79904 * height)
        )
        path.addCurve(
            to: CGPoint(x: 0.36341 * width, y: 0.76367 * height),
            control1: CGPoint(x: 0.36341 * width, y: 0.76933 * height),
            control2: CGPoint(x: 0.36341 * width, y: 0.7665 * height)
        )
        path.addCurve(
            to: CGPoint(x: 0.38209 * width, y: 0.70127 * height),
            control1: CGPoint(x: 0.36228 * width, y: 0.74141 * height),
            control2: CGPoint(x: 0.36886 * width, y: 0.71943 * height)
        )
        path.addCurve(
            to: CGPoint(x: 0.43633 * width, y: 0.66354 * height),
            control1: CGPoint(x: 0.39532 * width, y: 0.68311 * height),
            control2: CGPoint(x: 0.41442 * width, y: 0.66982 * height)
        )
        path.addCurve(
            to: CGPoint(x: 0.43633 * width, y: 0.65462 * height),
            control1: CGPoint(x: 0.43633 * width, y: 0.66049 * height),
            control2: CGPoint(x: 0.43633 * width, y: 0.65744 * height)
        )
        path.addCurve(
            to: CGPoint(x: 0.46101 * width, y: 0.57739 * height),
            control1: CGPoint(x: 0.43713 * width, y: 0.62715 * height),
            control2: CGPoint(x: 0.44567 * width, y: 0.60043 * height)
        )
        path.addCurve(
            to: CGPoint(x: 0.52329 * width, y: 0.52401 * height),
            control1: CGPoint(x: 0.47636 * width, y: 0.55435 * height),
            control2: CGPoint(x: 0.4979 * width, y: 0.53588 * height)
        )
        path.addCurve(
            to: CGPoint(x: 0.61085 * width, y: top),
            control1: CGPoint(x: 0.55077 * width, y: 0.51208 * height),
            control2: CGPoint(x: 0.58135 * width, y: 0.50873 * height)
        )
        path.addCurve(
            to: CGPoint(x: 0.68809 * width, y: 0.55579 * height),
            control1: CGPoint(x: 0.64035 * width, y: 0.52011 * height),
            control2: CGPoint(x: 0.66733 * width, y: 0.53456 * height)
        )
        path.addCurve(
            to: CGPoint(x: 0.72176 * width, y: 0.60455 * height),
            control1: CGPoint(x: 0.70227 * width, y: 0.5699 * height),
            control2: CGPoint(x: 0.71369 * width, y: 0.58642 * height)
        )
        path.addCurve(
            to: CGPoint(x: 0.74976 * width, y: 0.59134 * height),
            control1: CGPoint(x: 0.72986 * width, y: 0.598 * height),
            control2: CGPoint(x: 0.73947 * width, y: 0.59346 * height)
        )
        path.addCurve(
            to: CGPoint(x: 0.78085 * width, y: 0.59236 * height),
            control1: CGPoint(x: 0.76006 * width, y: 0.58921 * height),
            control2: CGPoint(x: 0.77073 * width, y: 0.58956 * height)
        )
        path.addCurve(
            to: CGPoint(x: 0.81801 * width, y: 0.6192 * height),
            control1: CGPoint(x: 0.79572 * width, y: 0.59746 * height),
            control2: CGPoint(x: 0.80867 * width, y: 0.60682 * height)
        )
        path.addCurve(
            to: CGPoint(x: 0.83326 * width, y: 0.6618 * height),
            control1: CGPoint(x: 0.82736 * width, y: 0.63158 * height),
            control2: CGPoint(x: 0.83267 * width, y: 0.64643 * height)
        )
        path.addCurve(
            to: CGPoint(x: 0.89648 * width, y: 0.6974 * height),
            control1: CGPoint(x: 0.858 * width, y: 0.66594 * height),
            control2: CGPoint(x: 0.88042 * width, y: 0.67856 * height)
        )
        path.addCurve(
            to: CGPoint(x: 0.92089 * width, y: 0.76454 * height),
            control1: CGPoint(x: 0.91254 * width, y: 0.71623 * height),
            control2: CGPoint(x: 0.9212 * width, y: 0.74004 * height)
        )
        path.addCurve(
            to: CGPoint(x: 0.82144 * width, y: bottom),
            control1: CGPoint(x: 0.92089 * width, y: 0.86097 * height),
            control2: CGPoint(x: 0.82255 * width, y: 0.86989 * height)
        )
        path.closeSubpath()

        return path
    }
}
