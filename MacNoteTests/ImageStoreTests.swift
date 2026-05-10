import XCTest
@testable import MacNote

final class ImageStoreTests: XCTestCase {
    var tmpDir: URL!
    var store: ImageStore!

    override func setUpWithError() throws {
        tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        store = ImageStore(notesDirectory: tmpDir)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmpDir)
    }

    func testWriteAndURL() throws {
        let noteID = UUID()
        let data = "fake image data".data(using: .utf8)!
        let filename = try store.write(imageData: data, ext: "png", for: noteID)
        XCTAssertTrue(filename.hasPrefix(noteID.uuidString.lowercased()))
        XCTAssertTrue(filename.hasSuffix(".png"))
        let url = store.url(for: filename)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testSameDataProducesSameHash() throws {
        let noteID = UUID()
        let data = "same data".data(using: .utf8)!
        let f1 = try store.write(imageData: data, ext: "png", for: noteID)
        let f2 = try store.write(imageData: data, ext: "png", for: noteID)
        XCTAssertEqual(f1, f2, "Same content should produce same filename (dedup)")
    }

    func testGarbageCollectMovesOrphans() throws {
        let noteID = UUID()
        let data = "image".data(using: .utf8)!
        let filename = try store.write(imageData: data, ext: "png", for: noteID)
        // GC with empty live references — this file should move to .trash/
        try store.garbageCollect(noteUUID: noteID, liveReferences: [])
        let trashURL = tmpDir.appendingPathComponent(".trash").appendingPathComponent(filename)
        XCTAssertTrue(FileManager.default.fileExists(atPath: trashURL.path))
    }
}
