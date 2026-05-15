import AppKit
import UniformTypeIdentifiers
import os

// MARK: - ImageAttachment

enum ImageDisplaySize: Int, CaseIterable {
    case small
    case medium
    case large
    case originalFit

    var menuTitle: String {
        switch self {
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        case .originalFit: return "Original Fit"
        }
    }

    var maxWidth: CGFloat? {
        switch self {
        case .small: return 200
        case .medium: return 400
        case .large: return 720
        case .originalFit: return nil
        }
    }
}

/// NSTextAttachment subclass that remembers its markdown source so `markdownContent`
/// can reconstruct the raw `![alt](filename)` string for saving.
final class ImageAttachment: NSTextAttachment {
    let markdownSource: String
    let filename: String
    var displaySize: ImageDisplaySize

    init(
        image: NSImage,
        filename: String,
        markdownSource: String,
        displaySize: ImageDisplaySize = .medium
    ) {
        self.filename = filename
        self.markdownSource = markdownSource
        self.displaySize = displaySize
        super.init(data: nil, ofType: nil)
        self.image = image
        // Non-zero initial bounds so TextKit renders the attachment before the
        // first layout pass calls attachmentBounds(for:...).
        let size = image.size
        if size.width > 0, size.height > 0 {
            bounds = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        }
    }

    required init?(coder: NSCoder) { nil }

    /// Called by the layout engine on every layout pass.
    /// Scales the rendered rect to fill the available line width so the image
    /// fits the text container — no pixels are modified, only the display size.
    override func attachmentBounds(
        for textContainer: NSTextContainer?,
        proposedLineFragment lineFrag: CGRect,
        glyphPosition position: CGPoint,
        characterIndex charIndex: Int
    ) -> CGRect {
        guard let img = image, img.size.width > 0, img.size.height > 0 else { return bounds }
        let widthCap = displaySize.maxWidth ?? lineFrag.size.width
        let available = min(lineFrag.size.width, widthCap)
        guard available > 0 else { return bounds }
        let targetWidth = min(img.size.width, available)
        let scale = targetWidth / img.size.width
        return CGRect(x: 0, y: 0,
                      width: (img.size.width * scale).rounded(),
                      height: (img.size.height * scale).rounded())
    }
}

// MARK: - MacNoteTextView

final class MacNoteTextView: NSTextView {

    // MARK: - Dependencies (set by coordinator / parent)

    var highlighterController: HighlighterController?
    var imageRenderer: ImageRenderer?
    var notesDirectory: URL = NoteStore.defaultNotesDirectory
    var currentNoteID: UUID?
    private var contextMenuAttachment: ImageAttachment?

    // MARK: - Private

    /// Captures: group 1 = alt text, group 2 = filename
    private static let imageSpanRegex: NSRegularExpression = {
        try! NSRegularExpression(pattern: #"!\[([^\]]*)\]\(([^)]*)\)"#)
    }()

    private static let monoFont = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
    private static let defaultAttrs: [NSAttributedString.Key: Any] = [.font: monoFont]

    // MARK: - Setup

    override func awakeFromNib() {
        super.awakeFromNib()
        commonSetup()
    }

    func commonSetup() {
        isRichText = true
        allowsUndo = true
        usesFindPanel = true
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        font = Self.monoFont
        typingAttributes = Self.defaultAttrs
        textContainerInset = NSSize(width: 16, height: 16)
    }

    // MARK: - Markdown load / extract

    /// Replace the text storage with the rendered form of `content`.
    /// `![alt](filename)` spans become `ImageAttachment` objects; plain text keeps its font.
    /// The delegate is suppressed so no spurious `textDidChange` fires during load.
    func loadMarkdown(_ content: String) {
        guard let ts = textStorage else { return }

        let nsContent = content as NSString
        let fullRange = NSRange(location: 0, length: nsContent.length)
        let matches = Self.imageSpanRegex.matches(in: content, range: fullRange)

        let result = NSMutableAttributedString()
        var cursor = 0

        for match in matches {
            // Text before this image span
            if match.range.location > cursor {
                let pre = NSRange(location: cursor, length: match.range.location - cursor)
                result.append(NSAttributedString(string: nsContent.substring(with: pre),
                                                 attributes: Self.defaultAttrs))
            }

            let matchStr = nsContent.substring(with: match.range)
            let filenameRange = match.range(at: 2)

            if filenameRange.location != NSNotFound, filenameRange.length > 0 {
                let filename = nsContent.substring(with: filenameRange)
                let imageURL = notesDirectory.appendingPathComponent(filename)
                let nsImage = NSImage(contentsOf: imageURL) ?? placeholderImage()
                let attachment = ImageAttachment(image: nsImage, filename: filename,
                                                 markdownSource: matchStr)
                result.append(NSAttributedString(attachment: attachment))
            } else {
                // Empty filename — keep as plain text
                result.append(NSAttributedString(string: matchStr, attributes: Self.defaultAttrs))
            }

            cursor = match.range.location + match.range.length
        }

        // Text after the last image span
        if cursor < nsContent.length {
            let tail = NSRange(location: cursor, length: nsContent.length - cursor)
            result.append(NSAttributedString(string: nsContent.substring(with: tail),
                                             attributes: Self.defaultAttrs))
        }

        let savedDelegate = delegate
        delegate = nil
        defer { delegate = savedDelegate }

        ts.beginEditing()
        ts.setAttributedString(result)
        ts.endEditing()

        typingAttributes = Self.defaultAttrs
    }

    /// Reconstruct the markdown string from the text storage.
    /// `ImageAttachment` runs emit their stored `markdownSource`; everything else emits the raw string.
    var markdownContent: String {
        guard let ts = textStorage else { return string }
        var result = ""
        ts.enumerateAttributes(in: NSRange(location: 0, length: ts.length), options: []) { attrs, range, _ in
            if let att = attrs[.attachment] as? ImageAttachment {
                result += att.markdownSource
            } else {
                result += (ts.string as NSString).substring(with: range)
            }
        }
        return result
    }

    // MARK: - Paste override

    override func paste(_ sender: Any?) {
        Logger.paste.debug("paste(_:) invoked")
        let pasteboard = NSPasteboard.general

        if let image = NSImage(pasteboard: pasteboard) {
            insertInlineImage(image, filename: nil)
            return
        }

        if let str = pasteboard.string(forType: .string) {
            insertText(str, replacementRange: selectedRange())
        }
    }

    // MARK: - Drag-and-drop

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let pb = sender.draggingPasteboard
        if pb.canReadItem(withDataConformingToTypes: [NSPasteboard.PasteboardType.tiff.rawValue,
                                                      NSPasteboard.PasteboardType.png.rawValue,
                                                      "public.file-url"]) {
            return .copy
        }
        return super.draggingEntered(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        Logger.paste.debug("performDragOperation(_:) invoked")
        let pb = sender.draggingPasteboard

        if let image = NSImage(pasteboard: pb) {
            var suggestedName: String? = nil
            if let urlString = pb.string(forType: .init("public.file-url")),
               let url = URL(string: urlString) {
                suggestedName = url.lastPathComponent
            }
            insertInlineImage(image, filename: suggestedName)
            return true
        }

        return super.performDragOperation(sender)
    }

    // MARK: - Copy override

    override func copy(_ sender: Any?) {
        // If the selection resolves to a single image (optionally surrounded by
        // whitespace), copy the image bytes instead of routing to text copy.
        if let attachment = soleImageAttachment(in: selectedRange()) {
            copyImageToClipboard(attachment)
            return
        }
        super.copy(sender)
    }

    /// Returns the only `ImageAttachment` in `range` if the rest of the range
    /// contains nothing but whitespace; otherwise nil.
    private func soleImageAttachment(in range: NSRange) -> ImageAttachment? {
        guard let ts = textStorage, range.length > 0,
              range.location >= 0, range.location + range.length <= ts.length
        else { return nil }

        var found: ImageAttachment?
        var rejected = false
        ts.enumerateAttribute(.attachment, in: range, options: []) { value, subRange, stop in
            if let img = value as? ImageAttachment {
                if found != nil { rejected = true; stop.pointee = true; return }
                found = img
            } else {
                let text = (ts.string as NSString).substring(with: subRange)
                if text.unicodeScalars.contains(where: { !CharacterSet.whitespacesAndNewlines.contains($0) }) {
                    rejected = true
                    stop.pointee = true
                }
            }
        }
        return rejected ? nil : found
    }

    // MARK: - Context menu

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        guard let (attachment, range) = imageAttachment(at: point) else {
            return super.menu(for: event)
        }

        contextMenuAttachment = attachment
        setSelectedRange(range)

        let menu = NSMenu(title: "Image")

        let copyItem = NSMenuItem(title: "Copy Image",
                                  action: #selector(copyImageFromMenu(_:)),
                                  keyEquivalent: "c")
        copyItem.keyEquivalentModifierMask = .command
        copyItem.target = self
        menu.addItem(copyItem)
        menu.addItem(.separator())

        let openItem = NSMenuItem(title: "Open Original",
                                  action: #selector(openOriginalImageFromMenu(_:)),
                                  keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)
        menu.addItem(.separator())

        for size in ImageDisplaySize.allCases {
            let item = NSMenuItem(title: size.menuTitle,
                                  action: #selector(setImageDisplaySizeFromMenu(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.tag = size.rawValue
            item.state = attachment.displaySize == size ? .on : .off
            menu.addItem(item)
        }

        return menu
    }

    // MARK: - Smart cursor (skip over image attachments)

    override func keyDown(with event: NSEvent) {
        guard event.modifierFlags.intersection([.shift, .command, .option]).isEmpty else {
            super.keyDown(with: event)
            return
        }

        switch event.keyCode {
        case 123: // left arrow
            if trySkipAttachment(direction: .backward) { return }
        case 124: // right arrow
            if trySkipAttachment(direction: .forward) { return }
        default:
            break
        }

        super.keyDown(with: event)
    }

    // MARK: - Private helpers

    private enum Direction { case forward, backward }

    private func imageAttachment(at point: NSPoint) -> (ImageAttachment, NSRange)? {
        guard let layoutManager, let textContainer, let textStorage else { return nil }

        let containerPoint = NSPoint(x: point.x - textContainerOrigin.x,
                                     y: point.y - textContainerOrigin.y)
        guard containerPoint.x >= 0, containerPoint.y >= 0 else { return nil }

        let glyphIndex = layoutManager.glyphIndex(for: containerPoint, in: textContainer)
        let charIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
        guard charIndex < textStorage.length else { return nil }

        let glyphRange = layoutManager.glyphRange(forCharacterRange: NSRange(location: charIndex, length: 1),
                                                  actualCharacterRange: nil)
        let rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            .offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
        guard rect.insetBy(dx: -4, dy: -4).contains(point) else { return nil }

        let attachmentRange = NSRange(location: 0, length: 0)
        var effectiveRange = attachmentRange
        guard let attachment = textStorage.attribute(.attachment,
                                                     at: charIndex,
                                                     effectiveRange: &effectiveRange) as? ImageAttachment
        else { return nil }

        return (attachment, effectiveRange)
    }

    private func refreshAttachmentLayout() {
        guard let layoutManager, let textContainer else { return }
        layoutManager.invalidateLayout(forCharacterRange: NSRange(location: 0, length: textStorage?.length ?? 0),
                                       actualCharacterRange: nil)
        layoutManager.ensureLayout(for: textContainer)
        needsDisplay = true
    }

    @objc
    private func copyImageFromMenu(_ sender: NSMenuItem) {
        guard let attachment = contextMenuAttachment else { return }
        copyImageToClipboard(attachment)
    }

    @objc
    private func openOriginalImageFromMenu(_ sender: NSMenuItem) {
        guard let attachment = contextMenuAttachment else { return }
        NSWorkspace.shared.open(notesDirectory.appendingPathComponent(attachment.filename))
    }

    private func copyImageToClipboard(_ attachment: ImageAttachment) {
        let pb = NSPasteboard.general
        pb.clearContents()
        let url = notesDirectory.appendingPathComponent(attachment.filename)
        // Prefer original file bytes under the resolved UTI so receivers get the
        // exact source format. Fall back to NSImage when the extension isn't a
        // known concrete image type or the file is unreadable — writing under
        // the abstract `public.image` UTI leaves many paste targets unable to
        // decode the data.
        if let type = Self.pasteboardType(forExtension: url.pathExtension),
           let data = try? Data(contentsOf: url) {
            pb.setData(data, forType: type)
        } else if let img = attachment.image {
            pb.writeObjects([img])
        }
    }

    /// Resolves a file extension to a concrete image pasteboard type, or nil if
    /// the extension doesn't conform to `UTType.image`.
    static func pasteboardType(forExtension ext: String) -> NSPasteboard.PasteboardType? {
        guard let type = UTType(filenameExtension: ext.lowercased()),
              type.conforms(to: .image)
        else { return nil }
        return NSPasteboard.PasteboardType(type.identifier)
    }

    @objc
    private func setImageDisplaySizeFromMenu(_ sender: NSMenuItem) {
        guard let size = ImageDisplaySize(rawValue: sender.tag),
              let attachment = contextMenuAttachment else { return }
        attachment.displaySize = size
        refreshAttachmentLayout()
    }

    @discardableResult
    private func trySkipAttachment(direction: Direction) -> Bool {
        guard let ts = textStorage else { return false }
        let caret = selectedRange().location
        var skipped = false

        ts.enumerateAttribute(.attachment, in: NSRange(location: 0, length: ts.length),
                              options: []) { value, range, stop in
            guard value is ImageAttachment else { return }
            switch direction {
            case .forward:
                if range.location == caret {
                    setSelectedRange(NSRange(location: range.location + range.length, length: 0))
                    skipped = true
                    stop.pointee = true
                }
            case .backward:
                if range.location + range.length == caret {
                    setSelectedRange(NSRange(location: range.location, length: 0))
                    skipped = true
                    stop.pointee = true
                }
            }
        }
        return skipped
    }

    /// Convert `image` to PNG, write via `ImageStore`, insert an `ImageAttachment` at the caret.
    private func insertInlineImage(_ image: NSImage, filename: String?) {
        guard let noteID = currentNoteID else {
            Logger.paste.warning("insertInlineImage called with no currentNoteID — skipped")
            return
        }
        guard let pngData = image.pngRepresentation() else {
            Logger.paste.error("Could not convert image to PNG")
            return
        }
        let store = ImageStore(notesDirectory: notesDirectory)
        do {
            let name = try store.write(imageData: pngData, ext: "png", for: noteID)
            let markdown = "![](\(name))"
            let attachment = ImageAttachment(image: image, filename: name, markdownSource: markdown)
            let insertAt = selectedRange().location
            textStorage?.insert(NSAttributedString(attachment: attachment), at: insertAt)
            setSelectedRange(NSRange(location: insertAt + 1, length: 0))
            // textStorage.insert bypasses NSTextView's normal event path, so delegate
            // callbacks (textDidChange) never fire. Call didChangeText() explicitly so
            // the editor view model updates its content snapshot and marks the note dirty.
            didChangeText()
            Logger.paste.info("Inserted inline image: \(name)")
        } catch {
            Logger.paste.error("Failed to save image: \(error)")
        }
    }

    private func placeholderImage() -> NSImage {
        NSImage(systemSymbolName: "photo", accessibilityDescription: nil) ?? NSImage()
    }
}

// MARK: - NSImage helpers

extension NSImage {
    func pngRepresentation() -> Data? {
        guard let cgImage = cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        return rep.representation(using: .png, properties: [:])
    }
}
