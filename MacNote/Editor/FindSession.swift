import AppKit

/// Drives find-within-the-open-note: computes matches for `query` against the
/// current note's text and paints them onto `textView`.
///
/// Highlights are painted as `NSLayoutManager` *temporary* attributes, not
/// text-storage attributes. `HighlighterController.buildHighlighter` resets
/// `.foregroundColor`/`.font` across the entire text storage on every
/// keystroke (`HighlighterController.swift:240`) — a highlight written into
/// the storage would be wiped almost immediately. Temporary attributes live
/// in the layout manager instead, so the highlighter can't touch them.
@Observable
final class FindSession {

    weak var textView: MacNoteTextView?

    var query: String = "" {
        didSet {
            guard query != oldValue else { return }
            debouncer.schedule { [weak self] in self?.refresh() }
        }
    }

    private(set) var matches: [NSRange] = []
    private(set) var currentIndex: Int = 0

    private let debouncer = Debouncer(delay: 0.15)

    private static let allMatchesColor = NSColor.systemYellow.withAlphaComponent(0.4)
    private static let currentMatchColor = NSColor.systemOrange.withAlphaComponent(0.6)

    /// "3 of 12", "No matches", or nil when there's no active query — for the
    /// toolbar field's counter.
    var matchCountText: String? {
        guard !query.isEmpty else { return nil }
        guard !matches.isEmpty else { return "No matches" }
        return "\(currentIndex + 1) of \(matches.count)"
    }

    // MARK: - Matching (pure, unit-testable without a text view)

    /// Case-insensitive, literal (non-regex) search. Returns non-overlapping
    /// match ranges in order of appearance.
    static func matches(in text: String, query: String) -> [NSRange] {
        guard !query.isEmpty else { return [] }
        let text = text as NSString
        var results: [NSRange] = []
        var searchRange = NSRange(location: 0, length: text.length)
        while searchRange.length > 0 {
            let found = text.range(of: query, options: [.caseInsensitive], range: searchRange)
            guard found.location != NSNotFound else { break }
            results.append(found)
            let nextLocation = found.location + max(found.length, 1)
            guard nextLocation < text.length else { break }
            searchRange = NSRange(location: nextLocation, length: text.length - nextLocation)
        }
        return results
    }

    // MARK: - API

    /// Recompute matches against the text view's current content and repaint.
    /// Called after `query` changes and (debounced) after every edit while a
    /// query is active.
    func refresh() {
        guard let textView, let storage = textView.textStorage else {
            matches = []
            return
        }
        matches = Self.matches(in: storage.string, query: query)
        currentIndex = 0
        repaint()
        scrollToCurrentMatch()
    }

    /// Called by `EditorPane.Coordinator.textDidChange`. A no-op unless a
    /// query is active, so plain typing doesn't pay for a debounce timer.
    func noteContentDidChange() {
        guard !query.isEmpty else { return }
        debouncer.schedule { [weak self] in self?.refresh() }
    }

    func next() {
        guard !matches.isEmpty else { return }
        currentIndex = (currentIndex + 1) % matches.count
        repaint()
        scrollToCurrentMatch()
    }

    func previous() {
        guard !matches.isEmpty else { return }
        currentIndex = (currentIndex - 1 + matches.count) % matches.count
        repaint()
        scrollToCurrentMatch()
    }

    /// Empties the query and removes all highlights. Called when the user
    /// dismisses the find field and whenever the open note changes.
    func clear() {
        query = ""
        matches = []
        currentIndex = 0
        clearHighlights()
    }

    // MARK: - Private

    private func repaint() {
        clearHighlights()
        guard let textView, let layoutManager = textView.layoutManager else { return }
        for (index, range) in matches.enumerated() {
            let color = (index == currentIndex) ? Self.currentMatchColor : Self.allMatchesColor
            layoutManager.addTemporaryAttribute(.backgroundColor, value: color, forCharacterRange: range)
        }
    }

    private func clearHighlights() {
        guard let textView, let layoutManager = textView.layoutManager,
              let storage = textView.textStorage, storage.length > 0
        else { return }
        layoutManager.removeTemporaryAttribute(
            .backgroundColor, forCharacterRange: NSRange(location: 0, length: storage.length))
    }

    private func scrollToCurrentMatch() {
        guard matches.indices.contains(currentIndex) else { return }
        textView?.scrollRangeToVisible(matches[currentIndex])
    }
}
