import SwiftUI
import XCTest
@testable import MacNote

final class CategoryChipContrastTests: XCTestCase {
    func testLightFillsUseDarkForeground() throws {
        let yellow = try XCTUnwrap(Color(hex: "FFF35A"))
        let orange = try XCTUnwrap(Color(hex: "FFB000"))

        XCTAssertFalse(CategoryChipContrast.usesLightForeground(for: yellow))
        XCTAssertFalse(CategoryChipContrast.usesLightForeground(for: orange))
        XCTAssertEqual(CategoryChipContrast.foregroundColor(for: yellow).toHex(), "000000")
    }

    func testDarkFillsUseLightForeground() throws {
        let purple = try XCTUnwrap(Color(hex: "4B0082"))
        let navy = try XCTUnwrap(Color(hex: "001F54"))

        XCTAssertTrue(CategoryChipContrast.usesLightForeground(for: purple))
        XCTAssertTrue(CategoryChipContrast.usesLightForeground(for: navy))
        XCTAssertEqual(CategoryChipContrast.foregroundColor(for: purple).toHex(), "FFFFFF")
    }

    func testSaturatedMidFillUsesHigherContrastForeground() throws {
        let systemBlue = try XCTUnwrap(Color(hex: "0A84FF"))

        XCTAssertFalse(CategoryChipContrast.usesLightForeground(for: systemBlue))
        XCTAssertEqual(CategoryChipContrast.foregroundColor(for: systemBlue).toHex(), "000000")
    }
}
