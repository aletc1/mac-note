import XCTest
@testable import MacNote

final class NoteLanguageTests: XCTestCase {

    func testInferFromKnownExtensions() {
        let cases: [(String, NoteLanguage)] = [
            ("note.md",   .markdown),
            ("data.json", .json),
            ("main.swift",.swift),
            ("script.py", .python),
            ("app.js",    .javascript),
            ("app.ts",    .typescript),
            ("ci.yaml",   .yaml),
            ("build.sh",  .bash),
            ("index.html",.html),
            ("plain.txt", .plain),
        ]
        for (filename, expected) in cases {
            let url = URL(fileURLWithPath: "/tmp/\(filename)")
            XCTAssertEqual(NoteLanguage.infer(from: url), expected, "failed for \(filename)")
        }
    }

    func testInferUnknownExtensionFallsBackToPlain() {
        let url = URL(fileURLWithPath: "/tmp/file.xyz")
        XCTAssertEqual(NoteLanguage.infer(from: url), .plain)
    }

    func testFileExtensionMatchesRawValue() {
        for lang in NoteLanguage.allCases {
            XCTAssertEqual(lang.fileExtension, lang.rawValue, "\(lang) fileExtension mismatch")
        }
    }

    func testAllCasesHaveNonEmptyDisplayName() {
        for lang in NoteLanguage.allCases {
            XCTAssertFalse(lang.displayName.isEmpty, "\(lang) has empty displayName")
        }
    }

    func testCodableRoundTrip() throws {
        for lang in NoteLanguage.allCases {
            let data = try JSONEncoder().encode(lang)
            let decoded = try JSONDecoder().decode(NoteLanguage.self, from: data)
            XCTAssertEqual(decoded, lang)
        }
    }
}
