import SwiftUI

enum PortkeeperStyle {
    static let navy = Color.black
    static let raised = Color(red: 0.025, green: 0.085, blue: 0.04)
    static let well = Color(red: 0.012, green: 0.025, blue: 0.016)
    static let ivory = Color(red: 0.77, green: 0.96, blue: 0.80)
    static let muted = Color(red: 0.45, green: 0.64, blue: 0.49)
    static let green = Color(red: 0.36, green: 1, blue: 0.48)
    static let coral = green
    static let cyan = green
    static let line = Color(red: 0.12, green: 0.25, blue: 0.15)
}

struct PortkeeperBackdrop: View {
    var body: some View { Color.black.allowsHitTesting(false) }
}

struct PortkeeperChrome: ViewModifier {
    var radius: CGFloat = 6
    func body(content: Content) -> some View {
        content.background(Color.black, in: RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).stroke(PortkeeperStyle.line, lineWidth: 1))
    }
}

extension View {
    func portkeeperChrome(radius: CGFloat = 6) -> some View {
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
    var body: some View {
        Button(action: action) { label }
            .buttonStyle(TerminalButtonStyle(prominent: prominent))
    }
}

struct TerminalButtonStyle: ButtonStyle {
    var prominent = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .padding(.horizontal, 10).padding(.vertical, 7)
            .foregroundStyle(prominent ? Color.black : PortkeeperStyle.green)
            .background(prominent ? PortkeeperStyle.green : Color.black, in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(PortkeeperStyle.line, lineWidth: prominent ? 0 : 1))
            .opacity(enabled ? (configuration.isPressed ? 0.78 : 1) : 0.35)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : .smooth(duration: 0.16), value: configuration.isPressed)
    }
}
