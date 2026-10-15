import AppKit

enum LighthouseStatusIcon {
    static func image(lit: Bool, alert: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            let context = NSGraphicsContext.current!.cgContext
            context.saveGState()
            context.translateBy(x: rect.minX, y: rect.minY)
            context.scaleBy(x: rect.width / 64, y: rect.height / 64)

            if lit {
                let amber = NSColor(calibratedRed: 0.36, green: 1, blue: 0.48, alpha: 1)
                let beam = NSBezierPath()
                beam.move(to: NSPoint(x: 36, y: 45))
                beam.line(to: NSPoint(x: 54, y: 40))
                beam.line(to: NSPoint(x: 54, y: 51))
                beam.close()
                amber.withAlphaComponent(alert ? 0.65 : 0.38).setFill()
                beam.fill()
            }

            NSColor(calibratedRed: 0.36, green: 1, blue: 0.48, alpha: lit ? 1 : 0.45).setFill()
            NSBezierPath(roundedRect: NSRect(x: 16, y: 5, width: 32, height: 8), xRadius: 4, yRadius: 4).fill()
            let tower = NSBezierPath()
            tower.move(to: NSPoint(x: 22, y: 12))
            tower.line(to: NSPoint(x: 42, y: 12))
            tower.line(to: NSPoint(x: 38, y: 38))
            tower.line(to: NSPoint(x: 26, y: 38))
            tower.close()
            tower.fill()
            NSBezierPath(roundedRect: NSRect(x: 22, y: 36, width: 20, height: 5), xRadius: 2, yRadius: 2).fill()
            NSBezierPath(roundedRect: NSRect(x: 24, y: 40, width: 16, height: 10), xRadius: 2, yRadius: 2).fill()
            NSBezierPath(roundedRect: NSRect(x: 19, y: 48, width: 26, height: 7), xRadius: 4, yRadius: 4).fill()
            NSBezierPath(ovalIn: NSRect(x: 22, y: 51, width: 20, height: 8)).fill()
            NSBezierPath(ovalIn: NSRect(x: 29, y: 58, width: 6, height: 6)).fill()

            // The lantern stays dark when idle and during the off beat of an alert.
            context.setBlendMode(.clear)
            NSBezierPath(roundedRect: NSRect(x: 28, y: 42, width: 8, height: 6), xRadius: 1, yRadius: 1).fill()
            NSBezierPath(roundedRect: NSRect(x: 29, y: 13, width: 6, height: 8), xRadius: 3, yRadius: 3).fill()
            context.setBlendMode(.normal)
            if lit {
                NSColor(calibratedRed: 0.36, green: 1, blue: 0.48, alpha: 1).setFill()
                NSBezierPath(roundedRect: NSRect(x: 29, y: 43, width: 6, height: 4), xRadius: 1, yRadius: 1).fill()
            }
            context.restoreGState()
            return true
        }
        image.isTemplate = false
        return image
    }
}
