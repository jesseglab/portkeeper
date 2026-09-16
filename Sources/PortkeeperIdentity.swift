import SwiftUI

enum PortkeeperStyle {
    static let navy = Color(red: 0.055, green: 0.090, blue: 0.125)
    static let raised = Color(red: 0.120, green: 0.170, blue: 0.205)
    static let well = Color(red: 0.085, green: 0.125, blue: 0.160)
    static let ivory = Color(red: 0.960, green: 0.944, blue: 0.885)
    static let muted = Color(red: 0.655, green: 0.720, blue: 0.720)
    static let coral = Color(red: 0.905, green: 0.695, blue: 0.345)
    static let cyan = Color(red: 0.520, green: 0.750, blue: 0.720)
    static let line = Color(red: 0.315, green: 0.395, blue: 0.430)
}

struct PortkeeperBackdrop: View {
    var body: some View {
        ZStack {
            PortkeeperStyle.navy
            LinearGradient(colors: [PortkeeperStyle.raised.opacity(0.30), .clear, .black.opacity(0.24)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Canvas { context, size in
                for y in stride(from: 4.0, through: size.height, by: 8.0) {
                    for x in stride(from: 4.0, through: size.width, by: 8.0) {
                        let shift = Int(x / 8 + y / 8)
                        guard shift % 3 != 0 else { continue }
                        let strength = 0.05 + 0.07 * (y / max(size.height, 1))
                        context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.2, height: 1.2)),
                                     with: .color(PortkeeperStyle.ivory.opacity(strength)))
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }
}

struct PortkeeperChrome: ViewModifier {
    var radius: CGFloat = 14

    @ViewBuilder func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: radius))
        } else {
            content.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius))
        }
    }
}

extension View {
    func portkeeperChrome(radius: CGFloat = 14) -> some View {
        modifier(PortkeeperChrome(radius: radius))
    }
}

struct PortkeeperGlassButton<LabelContent: View>: View {
    let prominent: Bool
    let action: () -> Void
    let label: LabelContent

    init(prominent: Bool = false, action: @escaping () -> Void,
         @ViewBuilder label: () -> LabelContent) {
        self.prominent = prominent
        self.action = action
        self.label = label()
    }

    @ViewBuilder var body: some View {
        if #available(macOS 26.0, *) {
            if prominent {
                Button(action: action) { label }.buttonStyle(.glassProminent)
            } else {
                Button(action: action) { label }
                    .buttonStyle(.glass(.clear))
                    .tint(PortkeeperStyle.raised)
            }
        } else {
            if prominent {
                Button(action: action) { label }.buttonStyle(.borderedProminent)
            } else {
                Button(action: action) { label }
                    .buttonStyle(.bordered)
                    .tint(PortkeeperStyle.muted)
            }
        }
    }
}
