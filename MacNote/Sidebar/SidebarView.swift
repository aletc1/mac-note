import SwiftUI

// NOTE: The top-level SidebarView entry point lives in MacNoteApp.swift.
// This file provides the date-grouped list body used inside SidebarView,
// exposed as SidebarNoteList so it can be dropped in without conflict.

/// Date-grouped note list for the sidebar.
/// Embed inside SidebarView to replace the flat ForEach when ready.
struct SidebarNoteList: View {

    @Environment(AppModel.self) private var appModel

    var body: some View {
        @Bindable var model = appModel
        let groups = DateSection.group(notes: appModel.filteredNotes)

        if groups.isEmpty {
            VStack {
                Spacer()
                Text("No Notes")
                    .foregroundStyle(.secondary)
                    .font(.callout)
                Spacer()
            }
        } else {
            List(selection: $model.selectedNoteID) {
                ForEach(groups, id: \.section) { group in
                    Section(group.section.rawValue) {
                        ForEach(group.notes) { note in
                            SidebarNoteRow(note: note)
                                .tag(note.id as UUID?)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
        }
    }
}

// MARK: - Category filter strip

/// Horizontal category filter for the sidebar header.
/// Uses Menu instead of Picker(.menu) because NSPopUpButton ignores SwiftUI's maxWidth proposal.
struct SidebarCategoryFilter: View {
    @Environment(AppModel.self) private var appModel

    private var selectionLabel: String {
        guard let id = appModel.selectedCategoryID,
              let cat = appModel.categoryStore.categories.first(where: { $0.id == id })
        else { return "All" }
        return cat.name
    }

    var body: some View {
        @Bindable var model = appModel
        Menu {
            Button("All") { model.selectedCategoryID = nil }
            if !appModel.categoryStore.categories.isEmpty {
                Divider()
                ForEach(appModel.categoryStore.categories) { cat in
                    Button(cat.name) { model.selectedCategoryID = cat.id }
                }
            }
        } label: {
            HStack {
                Text(selectionLabel)
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .imageScale(.small)
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }
}

// MARK: - Preview

#if DEBUG
#Preview("SidebarNoteList") {
    SidebarNoteList()
        .environment(AppModel())
        .frame(width: 260, height: 500)
}
#endif
