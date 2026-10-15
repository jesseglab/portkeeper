import AppKit
import Foundation

// Illustrated install guide using the real app icon; Finder appearance varies by macOS settings.
let app = CommandLine.arguments[1]
let background = CommandLine.arguments[2]
let output = CommandLine.arguments[3]
let name = URL(fileURLWithPath: app).deletingPathExtension().lastPathComponent
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1440, pixelsHigh: 960, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
let transform = NSAffineTransform(); transform.scale(by: 2); transform.concat()
NSImage(contentsOfFile: background)!.draw(in: NSRect(x: 0, y: 0, width: 720, height: 480))
let bundle = URL(fileURLWithPath: app)
let info = NSDictionary(contentsOf: bundle.appendingPathComponent("Contents/Info.plist"))!
var filename = (info["CFBundleIconFile"] as? String) ?? ""
if !filename.isEmpty && (filename as NSString).pathExtension.isEmpty { filename += ".icns" }
let resource = bundle.appendingPathComponent("Contents/Resources").appendingPathComponent(filename)
let icon = NSImage(contentsOf: resource) ?? NSImage(contentsOfFile: "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/GenericApplicationIcon.icns")!
icon.draw(in: NSRect(x: 152, y: 170, width: 104, height: 104))
func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor { NSColor(srgbRed: r/255, green: g/255, blue: b/255, alpha: 1) }
color(92, 150, 111).setFill()
NSBezierPath(roundedRect: NSRect(x: 471, y: 231, width: 43, height: 33), xRadius: 7, yRadius: 7).fill()
color(131, 206, 155).setFill()
NSBezierPath(roundedRect: NSRect(x: 466, y: 184, width: 100, height: 69), xRadius: 9, yRadius: 9).fill()
let mark = NSString(string: "A")
let markAttrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 35, weight: .medium), .foregroundColor: color(31, 77, 45)]
mark.draw(at: NSPoint(x: 504, y: 199), withAttributes: markAttrs)
for (text, center) in [(name, CGFloat(204)), ("Applications", CGFloat(516))] {
    let string = NSString(string: text)
    let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: color(12, 27, 16)]
    let size = string.size(withAttributes: attrs)
    string.draw(at: NSPoint(x: center-size.width/2, y: 480-329-size.height/2), withAttributes: attrs)
}
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
