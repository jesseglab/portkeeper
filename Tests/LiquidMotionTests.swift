@testable import NotchworkKit
import AppKit
import SwiftUI

extension TerminalWorkspaceTests {
    @MainActor static func runMotionTests() async {
        var spring = LiquidSpring(0)
        spring.target = 1
        var previous: CGFloat = 0
        var monotonic = true
        for _ in 0..<120 {
            spring.advance(1 / 120)
            monotonic = monotonic && spring.value >= previous && spring.value <= 1
            previous = spring.value
        }
        expect(monotonic, "Opening spring is monotonic")
        expect(spring.isSettled(position: 0.001, speed: 0.01), "Liquid spring settles without overshoot")
        var sixty = LiquidSpring(0), highRefresh = LiquidSpring(0)
        sixty.target = 640; highRefresh.target = 640
        for _ in 0..<30 { sixty.advance(1 / 60) }
        for _ in 0..<60 { highRefresh.advance(1 / 120) }
        expect(abs(sixty.value - highRefresh.value) < 0.00001, "Motion timing is identical at 60 and 120 Hz")
        var reversal = LiquidSpring(0)
        reversal.target = 1; reversal.advance(0.08)
        let before = reversal.value, speed = reversal.velocity
        reversal.target = 0
        expect(reversal.value == before && reversal.velocity == speed, "Reversing a hover preserves position and velocity")
        reversal.advance(1 / 120)
        expect(reversal.value > before, "Reversal carries momentum before changing direction")
        for _ in 0..<120 { reversal.advance(1 / 120) }
        expect(reversal.isSettled(position: 0.001, speed: 0.01), "Reversed motion returns cleanly to the collapsed state")
        var stalled = LiquidSpring(0); stalled.target = 1; stalled.advance(2)
        expect(stalled.isSettled(position: 0.001, speed: 0.01), "Delayed display frames cannot destabilize the spring")
        expect(LiquidShape.reveal(0) == 0 && LiquidShape.reveal(1) == 1 && LiquidShape.reveal(0.5) > 0, "Content reveal follows the surface continuously")

        let panel = EdgePanel(title: "Portkeeper · Motion test")
        let surface = LiquidSurfaceView(edge: .notch,
            expanded: VStack { Text("portkeeper_").font(.system(size: 24, design: .monospaced)); Text("live output").font(.system(size: 13, design: .monospaced)) }.foregroundStyle(.green).frame(maxWidth: .infinity, maxHeight: .infinity),
            compact: Text("›_").foregroundStyle(.green).frame(maxWidth: .infinity, maxHeight: .infinity))
        panel.contentView = surface
        let screen = NSScreen.main!.frame
        let compact = CGRect(x: screen.midX - 130, y: screen.maxY - 36, width: 260, height: 36)
        let expanded = CGRect(x: screen.midX - 230, y: screen.maxY - 460, width: 460, height: 460)
        surface.move(compact: compact, expanded: expanded, open: false, animated: false)
        expect(surface.subviews.count == 1, "Collapsed surface keeps its expensive content out of the window")
        panel.orderFrontRegardless()
        surface.move(compact: compact, expanded: expanded, open: true, animated: true)
        expect(surface.subviews.count == 2, "Opening reconnects content before the animation begins")
        let canvas = panel.frame
        try? await Task.sleep(nanoseconds: 120_000_000)
        expect(surface.isAnimating && surface.presentedFrame.height > compact.height && surface.presentedFrame.height < expanded.height, "Native display link renders intermediate surface geometry")
        expect(panel.frame == canvas, "Window canvas stays fixed while its mask morphs")
        let point = CGPoint(x: screen.midX, y: screen.maxY - 10)
        expect(surface.containsScreenPoint(point), "Visible notch surface remains interactive during motion")
        expect(!surface.containsScreenPoint(CGPoint(x: expanded.minX, y: expanded.minY)), "Transparent animation canvas does not intercept outside clicks")
        surface.move(compact: compact, expanded: expanded, open: false, animated: true)
        try? await Task.sleep(nanoseconds: 900_000_000)
        expect(!surface.isAnimating && panel.frame == compact, "Close animation trims the canvas only after settling")
        expect(surface.subviews.count == 1, "Closing suspends hidden content after the transition settles")
        surface.move(compact: compact, expanded: expanded, open: true, animated: false)
        expect(!surface.isAnimating && panel.frame == expanded && surface.presentedFrame == expanded, "Reduced-motion path immediately reaches its final geometry")
        surface.stopMotion(); panel.orderOut(nil)

        let drawer = EdgePanel(title: "Portkeeper · Drawer motion test")
        let drawerSurface = LiquidSurfaceView(edge: .drawer,
            expanded: Text("active terminals").foregroundStyle(.green), compact: Text("›_"))
        drawer.contentView = drawerSurface
        let geometry = NotchGeometry(NSScreen.main!)
        let handle = geometry.drawerFrame(expanded: false)
        let console = geometry.drawerFrame(expanded: true)
        drawerSurface.move(compact: handle, expanded: console, open: true, animated: true)
        drawer.orderFrontRegardless()
        expect(drawerSurface.isAnimating && drawerSurface.presentedFrame == handle, "First terminal drawer opening starts at its compact handle")
        try? await Task.sleep(nanoseconds: 120_000_000)
        expect(drawerSurface.presentedFrame.width > handle.width && drawerSurface.presentedFrame.width < console.width, "Drawer morphs continuously from the screen edge")
        expect(abs(drawerSurface.presentedFrame.maxX - geometry.screen.maxX) < 0.001, "Drawer stays anchored to the screen edge")
        drawerSurface.move(compact: handle, expanded: console, open: true, animated: false)
        expect(!drawerSurface.isAnimating && drawerSurface.presentedFrame == console, "Enabling Reduced Motion during a transition stops its display driver")
        let pixel = 1 / drawer.backingScaleFactor
        let frameDifferences = [drawer.frame.minX - console.minX, drawer.frame.minY - console.minY,
                                drawer.frame.width - console.width, drawer.frame.height - console.height]
        expect(frameDifferences.allSatisfy { abs($0) <= pixel }, "Settled drawer canvas matches the visible screen bounds within one native pixel: \(drawer.frame) vs \(console)")
        drawerSurface.stopMotion(); drawer.orderOut(nil)
        print("All liquid motion tests passed.")
    }
}
