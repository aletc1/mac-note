import AppKit
import os

/// TextKit 2 helper that renders `![alt](filename)` spans as inline images
/// at *display* time only.  The underlying text storage always stays plain
/// text — the rendered image is produced by a custom NSTextAttachment.
///
/// Usage:
///   1. After loading / editing text, call `registerImageRanges(in:)`.
///   2. Implement `NSTextLayoutManagerDelegate` and use the attachment cells
///      that this controller has registered.
final class ImageRenderer: NSObject {

    // MARK: - Types

    private struct ImageRange {
        let range: NSRange          // range of the full ![alt](filename) span
        let filename: String
    }

    // MARK: - State

    private var registeredRanges: [ImageRange] = []
    private let notesDirectory: URL

    /// Regex matching a full Markdown image span: `![alt text](filename)`
    private static let imageSpanRegex: NSRegularExpression = {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: #"!\[[^\]]*\]\(([^)]+)\)"#)
    }()

    // MARK: - Init

    init(notesDirectory: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".notes")) {
        self.notesDirectory = notesDirectory
    }

    // MARK: - API

    /// Scan `string` for `![alt](filename)` patterns and cache their ranges
    /// so the layout system can query them without re-running the regex on
    /// every draw call.
    func registerImageRanges(in string: NSString) {
        let fullRange = NSRange(location: 0, length: string.length)
        let matches = Self.imageSpanRegex.matches(in: string as String, range: fullRange)
        registeredRanges = matches.compactMap { match -> ImageRange? in
            guard match.numberOfRanges > 1 else { return nil }
            let filenameRange = match.range(at: 1)
            guard filenameRange.location != NSNotFound else { return nil }
            let filename = string.substring(with: filenameRange)
            return ImageRange(range: match.range, filename: filename)
        }
        Logger.editor.debug("ImageRenderer: registered \(self.registeredRanges.count) image range(s)")
    }

    /// Load the image for a given filename from the notes directory.
    /// Returns `nil` if the file doesn't exist or can't be decoded.
    func image(for filename: String) -> NSImage? {
        // Look in ~/.notes/images/ first, then directly in ~/.notes/
        let candidates: [URL] = [
            notesDirectory.appendingPathComponent("images").appendingPathComponent(filename),
            notesDirectory.appendingPathComponent(filename)
        ]
        for url in candidates {
            if let img = NSImage(contentsOf: url) {
                Logger.editor.debug("ImageRenderer: loaded image '\(filename)' from \(url.path)")
                return img
            }
        }
        Logger.editor.warning("ImageRenderer: image '\(filename)' not found in notes directory")
        return nil
    }

    /// Returns the nearest registered image range that contains or starts at `location`,
    /// used by the layout delegate to swap the span for an attachment.
    func imageRange(containing location: Int) -> (range: NSRange, filename: String)? {
        for entry in registeredRanges {
            let end = entry.range.location + entry.range.length
            if location >= entry.range.location && location < end {
                return (entry.range, entry.filename)
            }
        }
        return nil
    }

    /// Build an NSTextAttachment that displays the image inline.
    /// Falls back to a placeholder icon if the image isn't found.
    func attachment(for filename: String, maxWidth: CGFloat = 400) -> NSTextAttachment {
        let attachment = NSTextAttachment()
        if let img = image(for: filename) {
            // Scale to fit within maxWidth while preserving aspect ratio
            let ratio = min(maxWidth / img.size.width, 1.0)
            let size = NSSize(width: img.size.width * ratio, height: img.size.height * ratio)
            attachment.bounds = CGRect(origin: .zero, size: size)
            let cell = NSTextAttachmentCell(imageCell: img)
            attachment.attachmentCell = cell
        } else {
            // Placeholder: a small broken-image icon
            let placeholder = NSImage(systemSymbolName: "photo.badge.exclamationmark",
                                      accessibilityDescription: "Missing image: \(filename)")
            attachment.attachmentCell = NSTextAttachmentCell(imageCell: placeholder)
        }
        return attachment
    }
}
