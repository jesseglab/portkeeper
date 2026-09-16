import AppKit

let size = 64
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                             bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                             isPlanar: false, colorSpaceName: .deviceRGB,
                             bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
let context = NSGraphicsContext.current!.cgContext
context.clear(CGRect(x: 0, y: 0, width: size, height: size))
context.setShouldAntialias(true)
NSColor.black.setFill()
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

context.setBlendMode(.clear)
NSBezierPath(roundedRect: NSRect(x: 28, y: 42, width: 8, height: 6), xRadius: 1, yRadius: 1).fill()
NSBezierPath(roundedRect: NSRect(x: 29, y: 13, width: 6, height: 8), xRadius: 3, yRadius: 3).fill()
context.setBlendMode(.normal)
NSGraphicsContext.current?.flushGraphics()
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .png, properties: [:])!
    .write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
