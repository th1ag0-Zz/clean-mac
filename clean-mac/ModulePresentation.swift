import SwiftUI

/// Shared presentation follows the module hierarchy observed in the reference app.
struct ModuleLandingView: View {
    let title: String
    let subtitle: String
    let symbol: String
    let accent: Color
    let features: [(String, String)]
    var actionTitle = "Analisar"
    let action: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 55)
            HStack(spacing: 42) {
                ModuleArtwork(symbol: symbol, accent: accent)
                    .frame(width: 285, height: 290).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 18) {
                    Text(title).font(.system(size: 36, weight: .regular)).tracking(-0.6)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(subtitle).font(.system(size: 15)).foregroundStyle(.white.opacity(0.7))
                        .lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                    VStack(alignment: .leading, spacing: 20) {
                        ForEach(features.indices, id: \.self) { index in
                            HStack(spacing: 14) {
                                ModuleIcon(symbol: features[index].0, accent: accent, size: 25)
                                Text(features[index].1).font(.system(size: 13, weight: .semibold))
                            }
                        }
                    }.padding(.top, 14)
                }.frame(maxWidth: 330, alignment: .leading)
            }.frame(maxWidth: .infinity)
            Spacer(minLength: 80)
            RoundScanButton(title: actionTitle, accent: accent, action: action)
                .padding(.bottom, 16)
        }.frame(maxWidth: .infinity, minHeight: 575)
    }
}

struct ModuleIcon: View {
    let symbol: String
    let accent: Color
    var size: CGFloat = 26
    var body: some View {
        Image(systemName: symbol).font(.system(size: size * 0.53, weight: .semibold))
            .foregroundStyle(LinearGradient(colors: [.white, .white.opacity(0.65)], startPoint: .top, endPoint: .bottom))
            .frame(width: size, height: size)
            .background(LinearGradient(colors: [accent.opacity(0.85), accent.opacity(0.25)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: size * 0.28))
            .overlay(RoundedRectangle(cornerRadius: size * 0.28).strokeBorder(.white.opacity(0.15), lineWidth: 0.7))
    }
}

struct ModuleArtwork: View {
    let symbol: String
    let accent: Color
    var body: some View {
        ZStack {
            Ellipse().fill(accent.opacity(0.35)).blur(radius: 45).frame(width: 250, height: 230)
            if symbol == "desktopcomputer" || symbol == "sparkles" {
                CleanerArtwork().rotation3DEffect(.degrees(-7), axis: (x: 1, y: 0, z: 0))
            } else {
                RoundedRectangle(cornerRadius: symbol.contains("disc") ? 125 : 65)
                    .fill(.black.opacity(0.3)).frame(width: 246, height: 244).offset(y: 12)
                RoundedRectangle(cornerRadius: symbol.contains("disc") ? 125 : 65)
                    .fill(LinearGradient(stops: [.init(color: .white.opacity(0.65), location: 0), .init(color: accent.opacity(0.85), location: 0.26), .init(color: accent.opacity(0.3), location: 0.6), .init(color: .black.opacity(0.65), location: 1)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(RoundedRectangle(cornerRadius: symbol.contains("disc") ? 125 : 65).strokeBorder(LinearGradient(colors: [.white.opacity(0.55), accent, .black.opacity(0.45)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 2))
                    .frame(width: 248, height: 240)
                    .rotation3DEffect(.degrees(-13), axis: (x: 1, y: 0.15, z: 0))
                    .shadow(color: accent.opacity(0.3), radius: 28, y: 16)
                Image(systemName: symbol).font(.system(size: 108, weight: .medium))
                    .foregroundStyle(LinearGradient(colors: [.white, .white.opacity(0.65), accent.opacity(0.8)], startPoint: .top, endPoint: .bottom))
                    .shadow(color: .black.opacity(0.4), radius: 3, x: 2, y: 9)
                    .rotation3DEffect(.degrees(-12), axis: (x: 1, y: 0.15, z: 0))
            }
        }
    }
}

struct RoundScanButton: View {
    let title: String
    var accent: Color = .purple
    let action: () -> Void
    @State private var hovered = false
    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                .multilineTextAlignment(.center).frame(width: 86, height: 86)
                .background(LinearGradient(colors: [accent, accent.opacity(0.5), .black.opacity(0.25)], startPoint: .topLeading, endPoint: .bottomTrailing), in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.8), lineWidth: 1.5))
                .overlay(Circle().strokeBorder(accent.opacity(0.35), lineWidth: 6).padding(-6))
                .shadow(color: accent.opacity(hovered ? 0.75 : 0.4), radius: hovered ? 28 : 18)
                .scaleEffect(hovered ? 1.05 : 1)
        }.buttonStyle(.plain).onHover { hovered = $0 }
            .animation(.easeOut(duration: 0.2), value: hovered).accessibilityLabel(title)
    }
}

struct ScanOrbitView: View {
    let title: String
    let detail: String
    let progress: Double?
    let cancel: () -> Void
    @State private var rotating = false
    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 50)
            ZStack {
                Circle().stroke(.white.opacity(0.08), lineWidth: 2)
                Circle().trim(from: 0, to: progress.map { max(0.02, min($0, 1)) } ?? 0.3)
                    .stroke(AngularGradient(colors: [.white.opacity(0.1), .white], center: .center), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(progress == nil && rotating ? 360 : -90))
                    .animation(progress == nil ? .linear(duration: 2).repeatForever(autoreverses: false) : .easeInOut, value: rotating)
                Image(systemName: "sparkle.magnifyingglass").font(.system(size: 62, weight: .ultraLight))
            }.frame(width: 205, height: 205)
            Text(title).font(.system(size: 28, weight: .medium))
            Text(detail).font(.system(size: 14)).foregroundStyle(AppStyle.muted).multilineTextAlignment(.center)
            if let progress { Text("\(Int(progress * 100))% das etapas").font(.system(size: 12)).foregroundStyle(AppStyle.muted) }
            Spacer(minLength: 45)
            Button("Cancelar análise", action: cancel).buttonStyle(.bordered).controlSize(.large)
        }.frame(maxWidth: .infinity, minHeight: 560).onAppear { rotating = true }
    }
}
