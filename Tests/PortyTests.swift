import AppKit
import SwiftUI

extension TerminalWorkspaceTests {
    @MainActor static func runPortyTests() async {
        expect(PortyMood.resolve([], hasIssue: false) == .idle, "Porty rests when no services run")
        expect(PortyMood.resolve([.running, .starting], hasIssue: false) == .starting, "Startup takes priority over healthy running services")
        expect(PortyMood.resolve([.running], hasIssue: false) == .running, "Porty smiles for healthy services")
        expect(PortyMood.resolve([.starting, .failed("exit")], hasIssue: false) == .attention, "Failures take priority over startup")
        expect(PortyMood.resolve([.running, .unhealthy("error")], hasIssue: false) == .attention, "Unhealthy services trigger Porty's concerned expression")
        expect(PortyMood.resolve([.running], hasIssue: true) == .attention, "Port scans and active issues also trigger attention")

        let panel = EdgePanel(title: "Porty · Animation tests")
        let face = PortyNativeView(frame: CGRect(x: 0, y: 0, width: 80, height: 60))
        panel.contentView = face
        panel.setFrame(CGRect(x: 80, y: 80, width: 80, height: 60), display: false)
        face.configure(mood: .idle, active: true, reduceMotion: false)
        panel.orderFrontRegardless()
        face.layoutSubtreeIfNeeded()
        try? await Task.sleep(nanoseconds: 100_000_000)
        expect(face.hasBlinkScheduled && !face.hasStatusAnimation, "Idle Porty schedules occasional blinks without a continuous status animation")
        face.configure(mood: .attention, active: true, reduceMotion: false)
        expect(face.hasStatusAnimation, "Errors animate on Core Animation layers")
        face.configure(mood: .running, active: true, reduceMotion: false)
        expect(!face.hasStatusAnimation, "Recovery removes the repeating error pulse")
        face.configure(mood: .starting, active: true, reduceMotion: true)
        expect(face.mood == .starting && !face.hasBlinkScheduled && !face.hasStatusAnimation, "Reduced Motion keeps the status face and stops all animation scheduling")
        face.configure(mood: .attention, active: false, reduceMotion: false)
        expect(!face.hasBlinkScheduled && !face.hasStatusAnimation, "Inactive copies do no blink or pulse work")
        face.configure(mood: .attention, active: true, reduceMotion: false)
        face.isHidden = true
        expect(!face.hasBlinkScheduled && !face.hasStatusAnimation, "Hidden Porty stops animation work")
        face.isHidden = false
        expect(face.hasBlinkScheduled && face.hasStatusAnimation, "Revealed Porty resumes its current status")
        panel.orderOut(nil)
        try? await Task.sleep(nanoseconds: 150_000_000)
        expect(!face.hasBlinkScheduled && !face.hasStatusAnimation, "Ordering the panel out stops its mascot animations")
        panel.orderFrontRegardless()
        expect(face.hasBlinkScheduled && face.hasStatusAnimation, "Reopening the panel restores Porty's current status")
        panel.contentView = nil
        expect(!face.hasBlinkScheduled, "Detaching Porty cancels its blink timer")
        print("All Porty status and animation lifecycle tests passed.")
    }

    @MainActor static var portyPreviewWindow: NSWindow?
    @MainActor static func previewPorty() {
        let view = HStack(spacing: 24) {
            ForEach(PortyMood.allCases, id: \.self) { mood in
                VStack(spacing: 16) {
                    PortyFace(mood: mood).frame(width: 128, height: 96)
                    Text(mood.rawValue.uppercased()).font(.system(size: 11, design: .monospaced)).foregroundStyle(.green)
                    PortyFace(mood: mood).frame(width: 30, height: 24)
                }
            }
        }.padding(32).background(Color.black)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 648, height: 232), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Porty · Status expressions"
        window.contentView = NSHostingView(rootView: view)
        window.center(); window.makeKeyAndOrderFront(nil)
        portyPreviewWindow = window
    }
}
