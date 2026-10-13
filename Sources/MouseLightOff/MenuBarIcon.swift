import AppKit

enum MenuBarIcon {
    static let itemLength: CGFloat = 28
    static let symbolName = "computermouse"
    static let accessibilityLabel = "Mouse Light Off"

    static func makeStatusItem() -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: itemLength)
        item.isVisible = true
        if let button = item.button {
            configure(button)
        }
        return item
    }

    static func configure(_ button: NSButton) {
        button.image = makeImage()
        button.imagePosition = .imageOnly
        button.toolTip = accessibilityLabel
        button.setAccessibilityLabel(accessibilityLabel)
    }

    static func makeImage(
        loadSymbol: (String) -> NSImage? = {
            NSImage(systemSymbolName: $0, accessibilityDescription: accessibilityLabel)
        }
    ) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        // Keep a visible mouse even if a future OS cannot resolve the SF Symbol.
        let image =
            loadSymbol(symbolName)
            ?? NSImage(size: size, flipped: false) { _ in
                NSColor.black.setStroke()
                let outline = NSBezierPath(
                    roundedRect: NSRect(x: 4, y: 1, width: 10, height: 16), xRadius: 5, yRadius: 5)
                outline.lineWidth = 1.5
                outline.stroke()
                let wheel = NSBezierPath()
                wheel.move(to: NSPoint(x: 9, y: 11.5))
                wheel.line(to: NSPoint(x: 9, y: 14.5))
                wheel.lineWidth = 1.5
                wheel.lineCapStyle = .round
                wheel.stroke()
                return true
            }
        image.size = size
        image.isTemplate = true
        image.accessibilityDescription = accessibilityLabel
        return image
    }
}
