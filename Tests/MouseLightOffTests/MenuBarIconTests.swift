import AppKit
import XCTest

@testable import MouseLightOff

final class MenuBarIconTests: XCTestCase {
    func testSystemMouseSymbolResolvesAndRenders() throws {
        var symbolResolved = false
        let image = MenuBarIcon.makeImage { name in
            let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)
            symbolResolved = symbol != nil
            return symbol
        }
        XCTAssertTrue(symbolResolved, "The shipped SF Symbol must exist on the running macOS.")
        try assertVisibleTemplate(image)
    }

    func testMissingSystemSymbolStillRendersMouse() throws {
        let image = MenuBarIcon.makeImage(loadSymbol: { _ in nil })
        try assertVisibleTemplate(image)
    }

    private func assertVisibleTemplate(_ image: NSImage, file: StaticString = #filePath, line: UInt = #line)
        throws
    {
        XCTAssertTrue(image.isTemplate, file: file, line: line)
        XCTAssertEqual(image.accessibilityDescription, "Mouse Light Off", file: file, line: line)
        XCTAssertGreaterThan(image.size.width, 0, file: file, line: line)
        XCTAssertGreaterThan(MenuBarIcon.itemLength, image.size.width, file: file, line: line)
        let data = try XCTUnwrap(image.tiffRepresentation, file: file, line: line)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: data), file: file, line: line)
        let hasVisiblePixel = (0..<bitmap.pixelsWide).contains { x in
            (0..<bitmap.pixelsHigh).contains { y in
                (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0
            }
        }
        XCTAssertTrue(
            hasVisiblePixel, "The menu bar image must contain visible pixels.", file: file, line: line)
    }
}
