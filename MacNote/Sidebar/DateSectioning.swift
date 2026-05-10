import Foundation

/// Date-based groupings for the sidebar note list.
enum DateSection: String, CaseIterable {
    case today          = "Today"
    case lastSevenDays  = "Last 7 Days"
    case lastMonth      = "Last Month"
    case older          = "Older"

    // MARK: - Classification

    /// Return the section a `date` falls into relative to the current calendar day.
    static func section(for date: Date, now: Date = Date()) -> DateSection {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return .today }

        let sevenDaysAgo = cal.date(byAdding: .day, value: -7, to: now)!
        if date >= sevenDaysAgo { return .lastSevenDays }

        let thirtyDaysAgo = cal.date(byAdding: .day, value: -30, to: now)!
        if date >= thirtyDaysAgo { return .lastMonth }

        return .older
    }

    // MARK: - Grouping

    /// Group and sort `notes` into ordered `(section, notes)` pairs.
    /// Sections with no notes are omitted. Within each section, notes are sorted
    /// newest-first by `modifiedAt`.
    static func group(notes: [NoteItem], now: Date = Date()) -> [(section: DateSection, notes: [NoteItem])] {
        var buckets: [DateSection: [NoteItem]] = [:]

        for note in notes {
            let sec = section(for: note.modifiedAt, now: now)
            buckets[sec, default: []].append(note)
        }

        // Sort each bucket newest-first.
        for key in buckets.keys {
            buckets[key]?.sort { $0.modifiedAt > $1.modifiedAt }
        }

        // Return sections in canonical order, skipping empty ones.
        return DateSection.allCases.compactMap { sec -> (section: DateSection, notes: [NoteItem])? in
            guard let items = buckets[sec], !items.isEmpty else { return nil }
            return (section: sec, notes: items)
        }
    }
}
