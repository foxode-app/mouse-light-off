import AppKit
let output = CommandLine.arguments[1]
let image = NSImage(size: NSSize(width: 1024, height: 1024))
image.lockFocus()
NSColor(calibratedRed: 0.07, green: 0.16, blue: 0.17, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 38, y: 38, width: 948, height: 948), xRadius: 210, yRadius: 210).fill()
NSColor(calibratedRed: 0.82, green: 0.92, blue: 0.83, alpha: 1).setStroke()
let body = NSBezierPath(roundedRect: NSRect(x: 320, y: 205, width: 385, height: 595), xRadius: 190, yRadius: 190)
body.lineWidth = 43
body.stroke()
let wheel = NSBezierPath(roundedRect: NSRect(x: 488, y: 605, width: 46, height: 108), xRadius: 23, yRadius: 23)
NSColor(calibratedRed: 0.82, green: 0.92, blue: 0.83, alpha: 1).setFill()
wheel.fill()
let slash = NSBezierPath()
slash.move(to: NSPoint(x: 258, y: 230)); slash.line(to: NSPoint(x: 770, y: 787))
NSColor(calibratedRed: 0.07, green: 0.16, blue: 0.17, alpha: 1).setStroke()
slash.lineWidth = 92; slash.stroke()
NSColor(calibratedRed: 0.40, green: 0.75, blue: 0.60, alpha: 1).setStroke()
slash.lineWidth = 43; slash.lineCapStyle = .round; slash.stroke()
image.unlockFocus()
let data = NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!
try data.write(to: URL(fileURLWithPath: output))
