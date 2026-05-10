import AppKit

/// Converts an RTF-derived `NSAttributedString` to a Markdown string.
/// Walking each attribute run:
///   bold        → **text**
///   italic      → _text_
///   link        → [text](url)
///   plain text  → text as-is
enum RTFToMarkdown {

    static func convert(_ attributedString: NSAttributedString) -> String {
        var result = ""
        let fullRange = NSRange(location: 0, length: attributedString.length)

        attributedString.enumerateAttributes(in: fullRange, options: []) { attrs, range, _ in
            let rawText = (attributedString.string as NSString).substring(with: range)
            guard !rawText.isEmpty else { return }

            // Determine traits
            let isBold   = isBoldFont(attrs[.font] as? NSFont)
            let isItalic = isItalicFont(attrs[.font] as? NSFont)
            let linkURL  = attrs[.link] as? URL ?? (attrs[.link] as? String).flatMap(URL.init(string:))

            // Build the formatted fragment
            var fragment = escapedMarkdown(rawText)

            if let url = linkURL {
                // Links take precedence: [text](url)
                // Escape link text so ] doesn't close the bracket prematurely.
                // Encode ) in the URL to prevent it from closing the link target parenthesis.
                let linkText = escapedMarkdown(rawText)
                let urlStr = url.absoluteString.replacingOccurrences(of: ")", with: "%29")
                fragment = "[\(linkText)](\(urlStr))"
            } else {
                if isBold && isItalic {
                    fragment = "***\(fragment)***"
                } else if isBold {
                    fragment = "**\(fragment)**"
                } else if isItalic {
                    fragment = "_\(fragment)_"
                }
            }

            result += fragment
        }

        return result
    }

    // MARK: - Private helpers

    /// Returns `true` if `font` has the bold symbolic trait.
    private static func isBoldFont(_ font: NSFont?) -> Bool {
        guard let font else { return false }
        let traits = NSFontManager.shared.traits(of: font)
        return traits.contains(.boldFontMask)
    }

    /// Returns `true` if `font` has the italic symbolic trait.
    private static func isItalicFont(_ font: NSFont?) -> Bool {
        guard let font else { return false }
        let traits = NSFontManager.shared.traits(of: font)
        return traits.contains(.italicFontMask)
    }

    /// Escape Markdown special characters in plain text runs.
    /// We escape: `\`, `` ` ``, `*`, `_`, `{`, `}`, `[`, `]`, `(`, `)`, `#`, `+`, `-`, `.`, `!`
    private static func escapedMarkdown(_ text: String) -> String {
        let specialChars: Set<Character> = [
            "\\", "`", "*", "_", "{", "}", "[", "]", "(", ")", "#", "+", "-", ".", "!"
        ]
        return text.map { char in
            specialChars.contains(char) ? "\\\(char)" : String(char)
        }.joined()
    }
}
