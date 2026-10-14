import SwiftUI

/// Original vector illustration; no images or assets from the reference app are bundled.
struct CleanerArtwork: View {
    var body: some View {
        GeometryReader { geometry in
            let s = min(geometry.size.width, geometry.size.height)
            ZStack {
                Ellipse().fill(Color.pink.opacity(0.35)).frame(width: s * 0.9, height: s * 0.4)
                    .blur(radius: s * 0.15).offset(y: s * 0.22)
                Ellipse().fill(.black.opacity(0.35)).frame(width: s * 0.65, height: s * 0.08)
                    .blur(radius: 9).offset(y: s * 0.42)
                RoundedRectangle(cornerRadius: s * 0.025)
                    .fill(LinearGradient(colors: [Color(red: 0.39, green: 0.19, blue: 0.67), Color(red: 0.79, green: 0.73, blue: 0.95), .white], startPoint: .top, endPoint: .bottom))
                    .frame(width: s * 0.32, height: s * 0.28).offset(y: s * 0.26)
                Image(systemName: "sparkle").font(.system(size: s * 0.075)).foregroundStyle(.purple.opacity(0.35)).offset(y: s * 0.30)
                Capsule().fill(LinearGradient(colors: [.white, Color(red: 0.53, green: 0.37, blue: 0.74)], startPoint: .top, endPoint: .bottom))
                    .frame(width: s * 0.48, height: s * 0.025).offset(y: s * 0.41)
                DisplayShape().fill(Color(red: 0.54, green: 0.02, blue: 0.60))
                    .frame(width: s * 0.96, height: s * 0.61).offset(y: -s * 0.008)
                    .shadow(color: .black.opacity(0.3), radius: 12, y: 12)
                DisplayShape()
                    .fill(LinearGradient(stops: [.init(color: Color(red: 1, green: 0.66, blue: 0.94), location: 0), .init(color: Color(red: 0.99, green: 0.35, blue: 0.84), location: 0.35), .init(color: Color(red: 0.81, green: 0.02, blue: 0.67), location: 0.8), .init(color: Color(red: 0.65, green: 0, blue: 0.62), location: 1)], startPoint: .top, endPoint: .bottom))
                    .overlay(DisplayShape().strokeBorder(.white.opacity(0.35), lineWidth: 1.4))
                    .frame(width: s * 0.96, height: s * 0.61).offset(y: -s * 0.035)
                DisplayShape().fill(LinearGradient(colors: [.white.opacity(0.3), .white.opacity(0.02), .purple.opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: s * 0.79, height: s * 0.46).offset(y: -s * 0.045)
                // Two articulated arms and a pale rubber blade.
                Capsule().fill(.black.opacity(0.17)).frame(width: s * 0.42, height: s * 0.026)
                    .rotationEffect(.degrees(24)).offset(x: s * 0.19, y: -s * 0.20)
                Capsule().fill(LinearGradient(colors: [.white, Color(red: 0.70, green: 0.55, blue: 0.93)], startPoint: .top, endPoint: .bottom))
                    .frame(width: s * 0.42, height: s * 0.035).rotationEffect(.degrees(24)).offset(x: s * 0.17, y: -s * 0.22)
                Capsule().fill(LinearGradient(colors: [.white, Color(red: 0.66, green: 0.45, blue: 0.89)], startPoint: .leading, endPoint: .trailing))
                    .frame(width: s * 0.28, height: s * 0.035).rotationEffect(.degrees(67)).offset(x: s * 0.33, y: -s * 0.04)
                Capsule().fill(LinearGradient(colors: [.white, Color(red: 0.92, green: 0.76, blue: 1)], startPoint: .leading, endPoint: .trailing))
                    .frame(width: s * 0.35, height: s * 0.035).rotationEffect(.degrees(70)).offset(x: s * 0.34, y: -s * 0.035)
                joint(s * 0.04).offset(x: -s * 0.018, y: -s * 0.305)
                joint(s * 0.045).offset(x: s * 0.356, y: -s * 0.136)
            }.frame(width: geometry.size.width, height: geometry.size.height)
        }
    }
    private func joint(_ size: CGFloat) -> some View {
        Circle().fill(LinearGradient(colors: [.white, Color(red: 0.62, green: 0.45, blue: 0.84)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: size, height: size).shadow(color: .purple.opacity(0.4), radius: 1, y: 2)
    }
}

private struct DisplayShape: InsettableShape {
    var inset: CGFloat = 0
    func inset(by amount: CGFloat) -> some InsettableShape { var copy = self; copy.inset += amount; return copy }
    func path(in bounds: CGRect) -> Path {
        let r = bounds.insetBy(dx: inset, dy: inset)
        let w = r.width, h = r.height, x = r.minX, y = r.minY
        return Path { p in
            p.move(to: CGPoint(x: x + w * 0.16, y: y))
            p.addQuadCurve(to: CGPoint(x: x + w * 0.08, y: y + h * 0.13), control: CGPoint(x: x + w * 0.09, y: y))
            p.addLine(to: CGPoint(x: x, y: y + h * 0.82))
            p.addQuadCurve(to: CGPoint(x: x + w * 0.09, y: y + h), control: CGPoint(x: x - w * 0.01, y: y + h))
            p.addLine(to: CGPoint(x: x + w * 0.91, y: y + h))
            p.addQuadCurve(to: CGPoint(x: x + w, y: y + h * 0.82), control: CGPoint(x: x + w * 1.01, y: y + h))
            p.addLine(to: CGPoint(x: x + w * 0.92, y: y + h * 0.13))
            p.addQuadCurve(to: CGPoint(x: x + w * 0.84, y: y), control: CGPoint(x: x + w * 0.91, y: y))
            p.closeSubpath()
        }
    }
}
