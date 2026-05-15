import XCTest
import AppKit
@testable import MacNote

final class MacNoteTextViewTests: XCTestCase {

    func testPasteboardTypeResolvesKnownImageExtensions() {
        XCTAssertEqual(MacNoteTextView.pasteboardType(forExtension: "png")?.rawValue, "public.png")
        XCTAssertEqual(MacNoteTextView.pasteboardType(forExtension: "jpg")?.rawValue, "public.jpeg")
        XCTAssertEqual(MacNoteTextView.pasteboardType(forExtension: "jpeg")?.rawValue, "public.jpeg")
        XCTAssertEqual(MacNoteTextView.pasteboardType(forExtension: "gif")?.rawValue, "com.compuserve.gif")
        XCTAssertEqual(MacNoteTextView.pasteboardType(forExtension: "tiff")?.rawValue, "public.tiff")
        XCTAssertEqual(MacNoteTextView.pasteboardType(forExtension: "tif")?.rawValue, "public.tiff")
    }

    func testPasteboardTypeIsCaseInsensitive() {
        XCTAssertEqual(MacNoteTextView.pasteboardType(forExtension: "PNG")?.rawValue, "public.png")
        XCTAssertEqual(MacNoteTextView.pasteboardType(forExtension: "JPeG")?.rawValue, "public.jpeg")
    }

    func testPasteboardTypeReturnsNilForNonImageExtensions() {
        XCTAssertNil(MacNoteTextView.pasteboardType(forExtension: "txt"))
        XCTAssertNil(MacNoteTextView.pasteboardType(forExtension: "swift"))
        XCTAssertNil(MacNoteTextView.pasteboardType(forExtension: ""))
        XCTAssertNil(MacNoteTextView.pasteboardType(forExtension: "not-a-real-extension"))
    }
}
