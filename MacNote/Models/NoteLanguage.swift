import Foundation

enum NoteLanguage: String, CaseIterable, Codable {
    case markdown   = "md"
    case json       = "json"
    case swift      = "swift"
    case python     = "py"
    case javascript = "js"
    case typescript = "ts"
    case yaml       = "yaml"
    case bash       = "sh"
    case html       = "html"
    case plain      = "txt"

    var displayName: String {
        switch self {
        case .markdown:   return "Markdown"
        case .json:       return "JSON"
        case .swift:      return "Swift"
        case .python:     return "Python"
        case .javascript: return "JavaScript"
        case .typescript: return "TypeScript"
        case .yaml:       return "YAML"
        case .bash:       return "Bash"
        case .html:       return "HTML"
        case .plain:      return "Plain Text"
        }
    }

    var fileExtension: String { rawValue }

    /// UTType identifier for each language (used by drag-and-drop, pasteboard)
    var utTypeIdentifier: String {
        switch self {
        case .markdown:   return "net.daringfireball.markdown"
        case .json:       return "public.json"
        case .swift:      return "public.swift-source"
        case .python:     return "public.python-script"
        case .javascript: return "com.netscape.javascript-source"
        case .typescript: return "public.typescript-source"
        case .yaml:       return "public.yaml"
        case .bash:       return "public.shell-script"
        case .html:       return "public.html"
        case .plain:      return "public.plain-text"
        }
    }

    /// Guess language from a file URL extension
    static func infer(from url: URL) -> NoteLanguage {
        let ext = url.pathExtension.lowercased()
        return NoteLanguage(rawValue: ext) ?? .plain
    }
}
