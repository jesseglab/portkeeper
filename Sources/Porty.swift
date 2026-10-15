import AppKit
import QuartzCore
import SwiftUI

enum PortyMood: String, CaseIterable {
    case idle, starting, running, attention

    static func resolve(_ services: [ServiceState], hasIssue: Bool) -> Self {
        if hasIssue || services.contains(where: {
            switch $0 { case .failed, .unhealthy: return true; default: return false }
        }) { return .attention }
        if services.contains(where: { if case .starting = $0 { return true }; return false }) { return .starting }
        if services.contains(where: { if case .running = $0 { return true }; return false }) { return .running }
        return .idle
    }
    var description: String {
        switch self {
        case .idle: return "Porty is resting. No managed services are running."
        case .starting: return "Porty is watching projects start or restart."
        case .running: return "Porty is happy. Managed services are running."
        case .attention: return "Porty needs your attention. A service or port scan has an issue."
        }
    }
}

struct PortyFace: NSViewRepresentable {
    let mood: PortyMood
    var active = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeNSView(context: Context) -> PortyNativeView { PortyNativeView() }
    func updateNSView(_ view: PortyNativeView, context: Context) {
        view.configure(mood: mood, active: active, reduceMotion: reduceMotion)
    }
    static func dismantleNSView(_ view: PortyNativeView, coordinator: ()) { view.stopAnimation() }
}

/// Small layer-based face. Core Animation handles motion without a per-frame app callback.
@MainActor final class PortyNativeView: NSView {
    private let bodyLayer = CALayer()
    private let gradient = CAGradientLayer()
    private let silhouette = CAShapeLayer()
    private let leftEye = CALayer(), rightEye = CALayer()
    private let mouth = CAShapeLayer()
    private var blinkTimer: Timer?
    private(set) var mood: PortyMood = .idle
    private var active = false
    private var reduceMotion = false
    private var configured = false
    private var visibilityObserver: NSObjectProtocol?
    var hasBlinkScheduled: Bool { blinkTimer != nil }
    var hasStatusAnimation: Bool { bodyLayer.animation(forKey: "status") != nil }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.addSublayer(bodyLayer)
        bodyLayer.addSublayer(gradient)
        gradient.colors = [NSColor(calibratedRed: 0.65, green: 1, blue: 0.68, alpha: 1).cgColor,
                           NSColor(calibratedRed: 0.27, green: 0.98, blue: 0.38, alpha: 1).cgColor,
                           NSColor(calibratedRed: 0.03, green: 0.64, blue: 0.24, alpha: 1).cgColor]
        gradient.startPoint = CGPoint(x: 0.25, y: 1)
        gradient.endPoint = CGPoint(x: 0.75, y: 0)
        gradient.mask = silhouette
        for eye in [leftEye, rightEye] {
            eye.backgroundColor = NSColor(calibratedRed: 0.01, green: 0.07, blue: 0.03, alpha: 1).cgColor
            bodyLayer.addSublayer(eye)
        }
        mouth.fillColor = nil
        mouth.strokeColor = NSColor(calibratedRed: 0.01, green: 0.07, blue: 0.03, alpha: 1).cgColor
        mouth.lineCap = .round
        bodyLayer.addSublayer(mouth)
        setAccessibilityElement(false)
    }
    convenience init() { self.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func configure(mood: PortyMood, active: Bool, reduceMotion: Bool) {
        guard !configured || self.mood != mood || self.active != active || self.reduceMotion != reduceMotion else { return }
        let previous = self.mood
        let changedMood = configured && previous != mood
        configured = true
        self.mood = mood; self.active = active; self.reduceMotion = reduceMotion
        if changedMood { bodyLayer.removeAnimation(forKey: "status") }
        applyFace(animated: changedMood && canAnimate)
        updateActivity()
        if changedMood && mood == .running && canAnimate {
            let settle = CAKeyframeAnimation(keyPath: "transform.scale.y")
            let scale = min(bounds.width / 64, bounds.height / 48)
            settle.values = [scale, scale * 0.90, scale * 1.035, scale]
            settle.keyTimes = [0, 0.25, 0.65, 1]
            settle.duration = 0.42
            settle.timingFunctions = Array(repeating: CAMediaTimingFunction(name: .easeInEaseOut), count: 3)
            bodyLayer.add(settle, forKey: "reaction")
        }
    }
    private var canAnimate: Bool { active && !reduceMotion && window?.isVisible == true && !isHiddenOrHasHiddenAncestor }

    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        let scale = min(bounds.width / 64, bounds.height / 48)
        bodyLayer.bounds = CGRect(x: 0, y: 0, width: 64, height: 48)
        bodyLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        bodyLayer.setAffineTransform(CGAffineTransform(scaleX: scale, y: scale))
        gradient.frame = bodyLayer.bounds
        silhouette.frame = gradient.bounds
        silhouette.path = Self.blobPath
        for item in [bodyLayer, gradient, silhouette, leftEye, rightEye, mouth] {
            item.contentsScale = window?.backingScaleFactor ?? 2
        }
        CATransaction.commit()
        applyFace(animated: false)
        updateActivity()
    }
    private static let blobPath: CGPath = {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 6, y: 8))
        p.addCurve(to: CGPoint(x: 5, y: 29), control1: CGPoint(x: -1, y: 13), control2: CGPoint(x: 0, y: 23))
        p.addCurve(to: CGPoint(x: 20, y: 42), control1: CGPoint(x: 10, y: 32), control2: CGPoint(x: 10, y: 40))
        p.addCurve(to: CGPoint(x: 42, y: 41), control1: CGPoint(x: 28, y: 46), control2: CGPoint(x: 36, y: 43))
        p.addCurve(to: CGPoint(x: 54, y: 42), control1: CGPoint(x: 48, y: 39), control2: CGPoint(x: 47, y: 48))
        p.addCurve(to: CGPoint(x: 59, y: 29), control1: CGPoint(x: 59, y: 40), control2: CGPoint(x: 56, y: 33))
        p.addCurve(to: CGPoint(x: 59, y: 9), control1: CGPoint(x: 65, y: 22), control2: CGPoint(x: 65, y: 15))
        p.addCurve(to: CGPoint(x: 6, y: 8), control1: CGPoint(x: 53, y: 2), control2: CGPoint(x: 17, y: 2))
        p.closeSubpath()
        return p
    }()
    private func applyFace(animated: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        CATransaction.setAnimationDuration(0.22)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
        let eyeHeight: CGFloat = mood == .idle ? 6.5 : mood == .attention ? 10 : 9
        let gaze: CGFloat = mood == .starting ? 2 : 0
        for (eye, x) in [(leftEye, CGFloat(24)), (rightEye, CGFloat(42))] {
            eye.bounds = CGRect(x: 0, y: 0, width: 5.7, height: eyeHeight)
            eye.position = CGPoint(x: x, y: 28 + gaze)
            eye.cornerRadius = 2.85
        }
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 29, y: mood == .attention ? 17 : 20))
        p.addQuadCurve(to: CGPoint(x: 37, y: mood == .attention ? 17 : 20),
                       control: CGPoint(x: 33, y: mood == .attention ? 23 : mood == .idle ? 18 : 14))
        mouth.path = p; mouth.lineWidth = 2.6
        bodyLayer.opacity = mood == .idle ? 0.72 : 1
        CATransaction.commit()
    }
    private func updateActivity() {
        guard canAnimate else { stopAnimation(); return }
        if blinkTimer == nil { scheduleBlink() }
        if mood == .starting || mood == .attention {
            if bodyLayer.animation(forKey: "status") == nil {
                let pulse = CABasicAnimation(keyPath: "opacity")
                pulse.fromValue = 1; pulse.toValue = mood == .attention ? 0.5 : 0.82
                pulse.duration = mood == .attention ? 0.8 : 1.1
                pulse.autoreverses = true; pulse.repeatCount = .infinity
                pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                bodyLayer.add(pulse, forKey: "status")
            }
        } else { bodyLayer.removeAnimation(forKey: "status") }
    }
    private func scheduleBlink() {
        guard canAnimate else { return }
        let timer = Timer(timeInterval: Double.random(in: 4.5...7.5), repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.blinkTimer = nil
                self.blink()
                self.scheduleBlink()
            }
        }
        timer.tolerance = 0.25
        blinkTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }
    func blink() {
        guard canAnimate else { return }
        let blink = CAKeyframeAnimation(keyPath: "transform.scale.y")
        blink.values = [1, 0.08, 0.08, 1]
        blink.keyTimes = [0, 0.35, 0.5, 1]
        blink.duration = 0.20
        blink.timingFunctions = Array(repeating: CAMediaTimingFunction(name: .easeInEaseOut), count: 3)
        for eye in [leftEye, rightEye] { eye.add(blink, forKey: "blink") }
    }
    func stopAnimation() {
        blinkTimer?.invalidate(); blinkTimer = nil
        for item in [bodyLayer, leftEye, rightEye, mouth] { item.removeAllAnimations() }
    }
    func refreshVisibility() { updateActivity() }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let visibilityObserver { NotificationCenter.default.removeObserver(visibilityObserver) }
        visibilityObserver = nil
        if let window {
            visibilityObserver = NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.updateActivity() }
            }
        }
        updateActivity()
    }
    override func viewDidHide() { super.viewDidHide(); stopAnimation() }
    override func viewDidUnhide() { super.viewDidUnhide(); updateActivity() }
    deinit { if let visibilityObserver { NotificationCenter.default.removeObserver(visibilityObserver) } }
}
