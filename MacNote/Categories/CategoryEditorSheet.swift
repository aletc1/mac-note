import SwiftUI

/// Sheet for managing the user's category list: add, edit name/color, delete.
struct CategoryEditorSheet: View {

    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    @State private var newName: String  = ""
    @State private var newColor: Color  = .blue
    @State private var editingCategory: CategoryStore.Category? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ── Header ────────────────────────────────────────────────────
            HStack {
                Text("Categories")
                    .font(.title3)
                    .fontWeight(.semibold)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()

            Divider()

            // ── Existing categories list ──────────────────────────────────
            List {
                ForEach(appModel.categoryStore.categories) { cat in
                    CategoryRow(
                        category: cat,
                        onEdit:   { editingCategory = cat },
                        onDelete: { tryRemove(id: cat.id) }
                    )
                }
            }
            .listStyle(.bordered)

            Divider()

            // ── Add new category ──────────────────────────────────────────
            VStack(alignment: .leading, spacing: 10) {
                Text("New Category")
                    .font(.headline)

                HStack(spacing: 12) {
                    ColorPicker("", selection: $newColor, supportsOpacity: false)
                        .labelsHidden()
                        .frame(width: 30)

                    TextField("Name", text: $newName)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { addCategory() }

                    Button("Add") { addCategory() }
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding()
        }
        .frame(minWidth: 340, minHeight: 400)
        .sheet(item: $editingCategory) { cat in
            CategoryEditDetailSheet(category: cat) { updated in
                tryUpdate(updated)
            }
        }
    }

    // MARK: - Actions

    private func addCategory() {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        try? appModel.categoryStore.add(name: trimmed, color: newColor)
        newName  = ""
        newColor = .blue
    }

    private func tryRemove(id: String) {
        try? appModel.categoryStore.remove(id: id)
    }

    private func tryUpdate(_ category: CategoryStore.Category) {
        try? appModel.categoryStore.update(category: category)
    }
}

// MARK: - CategoryRow

private struct CategoryRow: View {
    let category: CategoryStore.Category
    let onEdit:   () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(category.color)
                .frame(width: 12, height: 12)

            Text(category.name)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onEdit) {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - CategoryEditDetailSheet

private struct CategoryEditDetailSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var color: Color
    private let original: CategoryStore.Category
    private let onSave: (CategoryStore.Category) -> Void

    init(category: CategoryStore.Category, onSave: @escaping (CategoryStore.Category) -> Void) {
        self.original = category
        self.onSave   = onSave
        _name  = State(initialValue: category.name)
        _color = State(initialValue: category.color)
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Edit Category")
                .font(.headline)

            HStack(spacing: 12) {
                ColorPicker("Color", selection: $color, supportsOpacity: false)
                TextField("Name", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") {
                    let hex = color.toHex()
                    let updated = CategoryStore.Category(
                        id: original.id,
                        name: name.trimmingCharacters(in: .whitespaces),
                        colorHex: hex
                    )
                    onSave(updated)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
        .frame(width: 300)
    }
}

// MARK: - Preview

#if DEBUG
#Preview("CategoryEditorSheet") {
    CategoryEditorSheet()
        .environment(AppModel())
}
#endif
