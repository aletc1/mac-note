import AppKit
import os

/// Manages syntax highlighting for the note editor.
/// In production this will delegate to Neon + TreeSitter grammar packages.
/// Until those SPM dependencies are wired, a regex-based pass covers Markdown.
final class HighlighterController {

    // MARK: - State

    private(set) var currentLanguage: NoteLanguage = .plain
    private weak var textView: NSTextView?

    // TODO: wire SPM dep — import Neon
    // TODO: wire SPM dep — import TreeSitter + language grammar packages
    // private var highlighter: Highlighter?

    // MARK: - API

    func configure(for language: NoteLanguage, textView: NSTextView) {
        self.currentLanguage = language
        self.textView = textView
        Logger.editor.debug("HighlighterController configured for language: \(language.displayName)")
        buildHighlighter(for: language, textView: textView)
    }

    func invalidateAll() {
        guard let textView else { return }
        buildHighlighter(for: currentLanguage, textView: textView)
    }

    /// Re-highlight after an edit. Full pass until Neon incremental is wired.
    func invalidateRange(_ range: NSRange) {
        invalidateAll()
    }

    // MARK: - Private

    private static let monoRegular = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
    private static let monoBold    = NSFont.monospacedSystemFont(ofSize: 14, weight: .bold)

    private struct Rule {
        let regex: NSRegularExpression
        let attrs: [NSAttributedString.Key: Any]
        init(_ pattern: String, _ options: NSRegularExpression.Options = [], _ attrs: [NSAttributedString.Key: Any]) {
            // Patterns are compile-time constants; crash on bad pattern is intentional.
            self.regex = try! NSRegularExpression(pattern: pattern, options: options)
            self.attrs = attrs
        }
    }

    // Rules are applied in order; later rules overwrite earlier ones for the same attribute.
    private static let markdownRules: [Rule] = [
        // ATX headings: # H1 … ###### H6
        Rule("^#{1,6}[ \\t].+$", [.anchorsMatchLines],
             [.foregroundColor: NSColor.systemBlue,
              .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .bold)]),
        // Blockquotes: > text
        Rule("^>[ \\t]?.*$", [.anchorsMatchLines],
             [.foregroundColor: NSColor.secondaryLabelColor]),
        // Fenced code blocks: ```…``` or ~~~…~~~
        Rule("(`{3,}|~{3,})[^\\n]*\\n[\\s\\S]*?\\1", [],
             [.foregroundColor: NSColor.secondaryLabelColor]),
        // Bold: **text** or __text__
        Rule("(\\*{2}|_{2}).+?\\1", [],
             [.font: NSFont.monospacedSystemFont(ofSize: 14, weight: .bold)]),
        // Inline code: `code`
        Rule("`[^`\\n]+`", [],
             [.foregroundColor: NSColor.systemGreen]),
        // Links: [text](url)
        Rule("\\[.+?\\]\\([^)]*\\)", [],
             [.foregroundColor: NSColor.linkColor]),
        // List markers: - / * / + / 1.
        Rule("^[ \\t]*([-*+]|\\d{1,9}\\.)[ \\t]", [.anchorsMatchLines],
             [.foregroundColor: NSColor.systemOrange]),
    ]

    private static let jsonRules: [Rule] = [
        // All string literals (keys and values) — green baseline
        Rule(#""[^"\\]*(?:\\.[^"\\]*)*""#, [],
             [.foregroundColor: NSColor.systemGreen]),
        // Numbers (integer and float)
        Rule(#"-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?"#, [],
             [.foregroundColor: NSColor.systemOrange]),
        // Keywords
        Rule(#"\b(?:true|false|null)\b"#, [],
             [.foregroundColor: NSColor.systemOrange]),
        // Property keys: string immediately before a colon — overrides green above
        Rule(#""[^"\\]*(?:\\.[^"\\]*)*"(?=\s*:)"#, [],
             [.foregroundColor: NSColor.systemBlue]),
    ]

    private static let pythonRules: [Rule] = [
        // Decorators
        Rule(#"@[\w.]+"#, [],
             [.foregroundColor: NSColor.systemOrange]),
        // Numbers
        Rule(#"-?\b\d+(?:\.\d+)?(?:[eE][+-]?\d+)?\b"#, [],
             [.foregroundColor: NSColor.systemOrange]),
        // Keywords
        Rule(#"\b(?:def|class|import|from|return|if|elif|else|for|while|try|except|finally|with|as|pass|break|continue|raise|yield|lambda|and|or|not|in|is|True|False|None|async|await|global|nonlocal|del|assert)\b"#, [],
             [.foregroundColor: NSColor.systemBlue]),
        // Comments — applied after keywords so # in non-string context wins
        Rule(#"#.*$"#, [.anchorsMatchLines],
             [.foregroundColor: NSColor.secondaryLabelColor]),
        // Triple-quoted strings (before single to take priority)
        Rule(#"\"\"\"[\s\S]*?\"\"\"|'''[\s\S]*?'''"#, [],
             [.foregroundColor: NSColor.systemGreen]),
        // Single-line strings — applied last so strings beat comment coloring
        Rule(#""[^"\\\n]*(?:\\.[^"\\\n]*)*"|'[^'\\\n]*(?:\\.[^'\\\n]*)*'"#, [],
             [.foregroundColor: NSColor.systemGreen]),
    ]

    private static let swiftRules: [Rule] = [
        // Numbers
        Rule(#"-?\b\d+(?:\.\d+)?(?:[eE][+-]?\d+)?\b"#, [],
             [.foregroundColor: NSColor.systemOrange]),
        // Attributes/annotations
        Rule(#"@\w+"#, [],
             [.foregroundColor: NSColor.systemOrange]),
        // Keywords
        Rule(#"\b(?:func|class|struct|enum|let|var|if|else|for|while|return|import|protocol|extension|init|override|public|private|internal|fileprivate|open|guard|switch|case|default|throw|throws|try|catch|async|await|actor|where|in|is|as|nil|true|false|self|Self|super|weak|unowned|lazy|static|final|mutating|nonmutating|consuming|borrowing|nonisolated|some|any|inout|typealias|associatedtype|defer|do|repeat|operator|precedencegroup|subscript)\b"#, [],
             [.foregroundColor: NSColor.systemBlue]),
        // Block comments
        Rule(#"/\*[\s\S]*?\*/"#, [],
             [.foregroundColor: NSColor.secondaryLabelColor]),
        // Line comments
        Rule(#"//.*$"#, [.anchorsMatchLines],
             [.foregroundColor: NSColor.secondaryLabelColor]),
        // Strings — last so they win over comment coloring
        Rule(#""[^"\\]*(?:\\.[^"\\]*)*""#, [],
             [.foregroundColor: NSColor.systemGreen]),
    ]

    private static let javascriptRules: [Rule] = [
        // Numbers
        Rule(#"-?\b\d+(?:\.\d+)?(?:[eE][+-]?\d+)?\b"#, [],
             [.foregroundColor: NSColor.systemOrange]),
        // Keywords
        Rule(#"\b(?:function|const|let|var|if|else|for|while|do|return|import|export|default|class|extends|new|this|async|await|typeof|instanceof|null|undefined|true|false|switch|case|break|continue|try|catch|finally|throw|of|in|from|yield|static|get|set)\b"#, [],
             [.foregroundColor: NSColor.systemBlue]),
        // Block comments
        Rule(#"/\*[\s\S]*?\*/"#, [],
             [.foregroundColor: NSColor.secondaryLabelColor]),
        // Line comments
        Rule(#"//.*$"#, [.anchorsMatchLines],
             [.foregroundColor: NSColor.secondaryLabelColor]),
        // Template literals
        Rule(#"`[^`\\]*(?:\\.[^`\\]*)*`"#, [],
             [.foregroundColor: NSColor.systemGreen]),
        // Strings
        Rule(#""[^"\\]*(?:\\.[^"\\]*)*"|'[^'\\]*(?:\\.[^'\\]*)*'"#, [],
             [.foregroundColor: NSColor.systemGreen]),
    ]

    private static let typescriptRules: [Rule] = [
        // Numbers
        Rule(#"-?\b\d+(?:\.\d+)?(?:[eE][+-]?\d+)?\b"#, [],
             [.foregroundColor: NSColor.systemOrange]),
        // Keywords (JS + TS additions)
        Rule(#"\b(?:function|const|let|var|if|else|for|while|do|return|import|export|default|class|extends|new|this|async|await|typeof|instanceof|null|undefined|true|false|switch|case|break|continue|try|catch|finally|throw|of|in|from|yield|static|get|set|type|interface|namespace|declare|abstract|implements|readonly|override|never|unknown|any|void|string|number|boolean|object|symbol|enum|keyof|infer|is)\b"#, [],
             [.foregroundColor: NSColor.systemBlue]),
        // Block comments
        Rule(#"/\*[\s\S]*?\*/"#, [],
             [.foregroundColor: NSColor.secondaryLabelColor]),
        // Line comments
        Rule(#"//.*$"#, [.anchorsMatchLines],
             [.foregroundColor: NSColor.secondaryLabelColor]),
        // Template literals
        Rule(#"`[^`\\]*(?:\\.[^`\\]*)*`"#, [],
             [.foregroundColor: NSColor.systemGreen]),
        // Strings
        Rule(#""[^"\\]*(?:\\.[^"\\]*)*"|'[^'\\]*(?:\\.[^'\\]*)*'"#, [],
             [.foregroundColor: NSColor.systemGreen]),
    ]

    private static let yamlRules: [Rule] = [
        // Numbers
        Rule(#"-?\b\d+(?:\.\d+)?(?:[eE][+-]?\d+)?\b"#, [],
             [.foregroundColor: NSColor.systemOrange]),
        // Boolean/null values
        Rule(#"\b(?:true|false|yes|no|null|~|True|False|Yes|No|Null|TRUE|FALSE|YES|NO|NULL)\b"#, [],
             [.foregroundColor: NSColor.systemOrange]),
        // Document markers
        Rule(#"^---$|^\.\.\.$"#, [.anchorsMatchLines],
             [.foregroundColor: NSColor.secondaryLabelColor]),
        // Keys: unquoted identifier before a colon
        Rule(#"^\s*[\w./-]+(?=\s*:)"#, [.anchorsMatchLines],
             [.foregroundColor: NSColor.systemBlue]),
        // Comments
        Rule(#"#.*$"#, [.anchorsMatchLines],
             [.foregroundColor: NSColor.secondaryLabelColor]),
        // Strings — last so they win
        Rule(#""[^"\\]*(?:\\.[^"\\]*)*"|'[^']*'"#, [],
             [.foregroundColor: NSColor.systemGreen]),
    ]

    private static let bashRules: [Rule] = [
        // Numbers
        Rule(#"-?\b\d+(?:\.\d+)?\b"#, [],
             [.foregroundColor: NSColor.systemOrange]),
        // Variable references
        Rule(#"\$\{?[\w_]+\}?"#, [],
             [.foregroundColor: NSColor.systemOrange]),
        // Keywords
        Rule(#"\b(?:if|then|else|elif|fi|for|while|do|done|case|esac|function|return|export|local|in|until|select|time|break|continue|exit|shift|source|echo|printf|read|set|unset)\b"#, [],
             [.foregroundColor: NSColor.systemBlue]),
        // Comments
        Rule(#"#.*$"#, [.anchorsMatchLines],
             [.foregroundColor: NSColor.secondaryLabelColor]),
        // Strings — last so they win
        Rule(#""[^"\\]*(?:\\.[^"\\]*)*"|'[^']*'"#, [],
             [.foregroundColor: NSColor.systemGreen]),
    ]

    private static let htmlRules: [Rule] = [
        // Tags: color entire <...> blue first
        Rule(#"<[^>]+>"#, [],
             [.foregroundColor: NSColor.systemBlue]),
        // Comments (override tag coloring)
        Rule(#"<!--[\s\S]*?-->"#, [],
             [.foregroundColor: NSColor.secondaryLabelColor]),
        // Attribute values inside tags — override blue with green
        Rule(#""[^"]*"|'[^']*'"#, [],
             [.foregroundColor: NSColor.systemGreen]),
        // Entity references
        Rule(#"&[\w#]+;"#, [],
             [.foregroundColor: NSColor.systemOrange]),
    ]

    private func buildHighlighter(for language: NoteLanguage, textView: NSTextView) {
        guard let storage = textView.textStorage else { return }
        let length = storage.length
        guard length > 0 else { return }
        let full = NSRange(location: 0, length: length)

        storage.beginEditing()
        // Reset to plain text
        storage.addAttribute(.foregroundColor, value: NSColor.textColor, range: full)
        storage.addAttribute(.font, value: Self.monoRegular, range: full)

        let rules: [Rule]
        switch language {
        case .markdown:   rules = Self.markdownRules
        case .json:       rules = Self.jsonRules
        case .python:     rules = Self.pythonRules
        case .swift:      rules = Self.swiftRules
        case .javascript: rules = Self.javascriptRules
        case .typescript: rules = Self.typescriptRules
        case .yaml:       rules = Self.yamlRules
        case .bash:       rules = Self.bashRules
        case .html:       rules = Self.htmlRules
        case .plain:      rules = []
        }

        let str = storage.string
        for rule in rules {
            rule.regex.enumerateMatches(in: str, range: full) { match, _, _ in
                guard let r = match?.range, r.length > 0 else { return }
                for (key, value) in rule.attrs {
                    storage.addAttribute(key, value: value, range: r)
                }
            }
        }

        storage.endEditing()
    }
}
