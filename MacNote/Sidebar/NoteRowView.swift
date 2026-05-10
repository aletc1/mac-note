import SwiftUI

/// A richer sidebar row: title, body preview, category chip, relative date.
struct SidebarNoteRow: View {
    let note: NoteItem
    @Environment(AppModel.self) private var appModel

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            // Title
            Text(note.title.isEmpty ? "Untitled" : note.title)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.tail)

            // Body preview placeholder (avoid loading full content in list)
            Text(languageAndPreview)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.tail)

            // Footer: category chip + relative date
            HStack(spacing: 6) {
                if let cat = effectiveCategory {
                    CategoryChip(name: cat.name, color: cat.color)
                }
                Spacer()
                TimelineView(.everyMinute) { ctx in
                    Text(Self.relativeDate(note.modifiedAt, relativeTo: ctx.date))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button("No Category") {
                appModel.setCategory(nil, for: note.id)
            }
            if !appModel.categoryStore.categories.isEmpty {
                Divider()
                ForEach(appModel.categoryStore.categories) { cat in
                    Button(cat.name) {
                        appModel.setCategory(cat.id, for: note.id)
                    }
                }
            }
        }
    }

    // MARK: - Private

    private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()

    private static func relativeDate(_ date: Date, relativeTo now: Date) -> String {
        relativeDateFormatter.localizedString(for: date, relativeTo: now)
    }

    private var languageAndPreview: String {
        note.language.displayName
    }

    // Reads appModel.notes directly so this view re-renders when the note's
    // categoryID changes in-place (avoids macOS List diffing lag on @Observable arrays).
    private var effectiveCategory: CategoryStore.Category? {
        let catID = appModel.notes.first(where: { $0.id == note.id })?.categoryID
                    ?? note.categoryID
        guard let catID else { return nil }
        return appModel.categoryStore.categories.first { $0.id == catID }
    }
}
