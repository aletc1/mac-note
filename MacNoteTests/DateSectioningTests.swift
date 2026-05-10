import XCTest
@testable import MacNote

final class DateSectioningTests: XCTestCase {
    func testTodaySection() {
        let section = DateSection.section(for: Date())
        XCTAssertEqual(section, .today)
    }

    func testLastSevenDays() {
        let threeDaysAgo = Calendar.current.date(byAdding: .day, value: -3, to: Date())!
        let section = DateSection.section(for: threeDaysAgo)
        XCTAssertEqual(section, .lastSevenDays)
    }

    func testLastMonth() {
        let twoWeeksAgo = Calendar.current.date(byAdding: .day, value: -14, to: Date())!
        let section = DateSection.section(for: twoWeeksAgo)
        XCTAssertEqual(section, .lastMonth)
    }

    func testOlder() {
        let twoMonthsAgo = Calendar.current.date(byAdding: .month, value: -2, to: Date())!
        let section = DateSection.section(for: twoMonthsAgo)
        XCTAssertEqual(section, .older)
    }

    func testGroupingPreservesOrder() {
        let notes = [
            NoteItem(id: UUID(), title: "Old", language: .plain, categoryID: nil,
                     createdAt: Calendar.current.date(byAdding: .month, value: -2, to: Date())!,
                     modifiedAt: Calendar.current.date(byAdding: .month, value: -2, to: Date())!,
                     path: URL(fileURLWithPath: "/tmp/a.txt")),
            NoteItem(id: UUID(), title: "New", language: .plain, categoryID: nil,
                     createdAt: Date(), modifiedAt: Date(),
                     path: URL(fileURLWithPath: "/tmp/b.txt")),
        ]
        let grouped = DateSection.group(notes: notes)
        XCTAssertEqual(grouped.first?.section, .today)
    }
}
