import SwiftUI

/// Ilustração própria para a tela inicial, construída com formas SwiftUI.
struct CleanerArtwork: View {
    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            ZStack {
                Circle()
                    .fill(Color(red: 0.95, green: 0.15, blue: 0.79).opacity(0.42))
                    .frame(width: size * 0.90, height: size * 0.90)
                    .blur(radius: size * 0.16)
                RoundedRectangle(cornerRadius: size * 0.03)
                    .fill(LinearGradient(colors: [.white, Color(red: 0.72, green: 0.63, blue: 0.93)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: size * 0.29, height: size * 0.24)
                    .offset(y: size * 0.30)
                RoundedRectangle(cornerRadius: size * 0.02)
                    .fill(Color(red: 0.88, green: 0.77, blue: 0.98))
                    .frame(width: size * 0.48, height: size * 0.035)
                    .offset(y: size * 0.43)
                RoundedRectangle(cornerRadius: size * 0.10)
                    .fill(LinearGradient(colors: [Color(red: 1.0, green: 0.64, blue: 0.91),
                                                  Color(red: 0.95, green: 0.25, blue: 0.76),
                                                  Color(red: 0.57, green: 0.04, blue: 0.65)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay {
                        RoundedRectangle(cornerRadius: size * 0.10)
                            .strokeBorder(.white.opacity(0.36), lineWidth: 1)
                    }
                    .frame(width: size * 0.88, height: size * 0.58)
                    .shadow(color: Color(red: 0.07, green: 0.01, blue: 0.18).opacity(0.5),
                            radius: size * 0.07, y: size * 0.035)
                    .offset(y: -size * 0.04)
                RoundedRectangle(cornerRadius: size * 0.06)
                    .fill(LinearGradient(colors: [.white.opacity(0.34), .clear],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: size * 0.73, height: size * 0.41)
                    .offset(y: -size * 0.09)
                Capsule()
                    .fill(Color(red: 0.99, green: 0.84, blue: 0.99))
                    .frame(width: size * 0.47, height: size * 0.025)
                    .rotationEffect(.degrees(23))
                    .offset(x: size * 0.09, y: -size * 0.16)
                Circle()
                    .fill(Color(red: 0.90, green: 0.78, blue: 0.99))
                    .frame(width: size * 0.045, height: size * 0.045)
                    .offset(x: -size * 0.13, y: -size * 0.25)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
