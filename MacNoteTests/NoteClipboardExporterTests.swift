import XCTest
import AppKit
@testable import MacNote

final class NoteClipboardExporterTests: XCTestCase {
    var tmpDir: URL!

    override func setUpWithError() throws {
        tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmpDir)
    }

    func testHTMLEmbedsLocalMarkdownImageAsDataURL() throws {
        let imageData = Data("image bytes".utf8)
        try imageData.write(to: tmpDir.appendingPathComponent("note-image.png"))

        let html = NoteClipboardExporter.htmlString(
            from: "before\n![diagram](note-image.png)\nafter",
            notesDirectory: tmpDir
        )

        XCTAssertTrue(html.contains("before<br>"))
        XCTAssertTrue(html.contains("<img src=\"data:image/png;base64,\(imageData.base64EncodedString())\" alt=\"diagram\">"))
        XCTAssertTrue(html.contains("<br>after"))
    }

    func testHTMLFallsBackToMarkdownSourceWhenImageIsMissing() {
        let html = NoteClipboardExporter.htmlString(
            from: "![missing](missing.png)",
            notesDirectory: tmpDir
        )

        XCTAssertTrue(html.contains("![missing](missing.png)"))
        XCTAssertFalse(html.contains("<img"))
    }

    func testManifestIncludesMarkdownAndImagesForElectronConsumers() throws {
        let imageData = Data("image bytes".utf8)
        try imageData.write(to: tmpDir.appendingPathComponent("note-image.jpg"))

        let data = try XCTUnwrap(NoteClipboardExporter.manifestData(
            from: "![photo](note-image.jpg)",
            notesDirectory: tmpDir
        ))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let images = try XCTUnwrap(json["images"] as? [[String: String]])

        XCTAssertEqual(json["markdown"] as? String, "![photo](note-image.jpg)")
        XCTAssertEqual(images.first?["filename"], "note-image.jpg")
        XCTAssertEqual(images.first?["mimeType"], "image/jpeg")
        XCTAssertEqual(images.first?["base64"], imageData.base64EncodedString())
    }

    func testRichTextUsesAttachmentForExistingImage() throws {
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAFgwJ/l4QJ6wAAAABJRU5ErkJggg==")!
        try png.write(to: tmpDir.appendingPathComponent("pixel.png"))

        let attributed = NoteClipboardExporter.richText(
            from: "a ![](pixel.png) b",
            notesDirectory: tmpDir
        )
        var attachmentCount = 0
        attributed.enumerateAttribute(.attachment, in: NSRange(location: 0, length: attributed.length)) { value, _, _ in
            if value is NSTextAttachment {
                attachmentCount += 1
            }
        }

        XCTAssertEqual(attachmentCount, 1)
    }
}
