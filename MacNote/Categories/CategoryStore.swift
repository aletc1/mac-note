import SwiftUI
import os

// MARK: - Color+Hex

extension Color {
    /// Initialise from a CSS-style hex string like `"#FF8800"` or `"FF8800"`.
    /// Returns `nil` if the string cannot be parsed.
    init?(hex: String) {
        var raw = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.hasPrefix("#") { raw = String(raw.dropFirst()) }
        guard raw.count == 6, let value = UInt64(raw, radix: 16) else { return nil }
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8)  & 0xFF) / 255
        let b = Double( value        & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }

    /// Return a 6-digit CSS hex string for this color (sRGB, no alpha).
    func toHex() -> String {
        let resolved = NSColor(self).usingColorSpace(.sRGB) ?? .blue
        let r = Int(resolved.redComponent   * 255)
        let g = Int(resolved.greenComponent * 255)
        let b = Int(resolved.blueComponent  * 255)
        return String(format: "%02X%02X%02X", r, g, b)
    }
}

// MARK: - CategoryStore

/// Observable store for the user's note categories.
/// Categories are persisted in the SQLite index (categories table).
/// For v0.1 they live in memory only; wire IndexService to persist them.
@Observable final class CategoryStore {

    // MARK: - Category model

    struct Category: Identifiable, Codable, Hashable {
        let id: String          // UUID string
        var name: String
        var colorHex: String    // e.g. "0080FF"

        /// SwiftUI Color derived from `colorHex`.
        var color: Color { Color(hex: colorHex) ?? .blue }

        init(id: String = UUID().uuidString, name: String, colorHex: String) {
            self.id       = id
            self.name     = name
            self.colorHex = colorHex
        }
    }

    // MARK: - Published state

    private(set) var categories: [Category] = []

    // MARK: - Dependencies

    var indexService: IndexService?

    // MARK: - Private

    private let logger = Logger(subsystem: "com.macnote", category: "CategoryStore")

    // MARK: - Init

    init() {}

    // MARK: - CRUD

    /// Add a new category.
    func add(name: String, color: Color) throws {
        let hex = color.toHex()
        let cat = Category(name: name, colorHex: hex)
        categories.append(cat)
        try? indexService?.upsertCategory(id: cat.id, name: cat.name, colorHex: cat.colorHex)
        logger.debug("Added category '\(name)' (\(hex))")
    }

    /// Remove a category by id.
    func remove(id: String) throws {
        categories.removeAll { $0.id == id }
        try? indexService?.deleteCategory(id: id)
        logger.debug("Removed category \(id)")
    }

    /// Update an existing category (by id).
    func update(category: Category) throws {
        guard let idx = categories.firstIndex(where: { $0.id == category.id }) else { return }
        categories[idx] = category
        try? indexService?.upsertCategory(id: category.id, name: category.name, colorHex: category.colorHex)
        logger.debug("Updated category \(category.id) -> '\(category.name)'")
    }

    /// Load categories from the IndexService categories table.
    func load() throws {
        guard let svc = indexService else {
            if categories.isEmpty { seedDefaults(using: nil) }
            return
        }
        let rows = try svc.fetchAllCategories()
        if rows.isEmpty {
            seedDefaults(using: svc)
        } else {
            categories = rows.map { Category(id: $0.id, name: $0.name, colorHex: $0.colorHex) }
        }
        logger.debug("Loaded \(self.categories.count) categories")
    }

    private func seedDefaults(using svc: IndexService?) {
        categories = [
            Category(name: "Work",     colorHex: "0A84FF"),
            Category(name: "Personal", colorHex: "30D158"),
        ]
        if let svc {
            for cat in categories {
                try? svc.upsertCategory(id: cat.id, name: cat.name, colorHex: cat.colorHex)
            }
        }
    }
}
