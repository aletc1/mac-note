import SwiftUI

/// A small rounded-rectangle tag that displays a category name in its color.
struct CategoryChip: View {
    let name: String
    let color: Color

    var body: some View {
        Text(name)
            .font(.caption2)
            .fontWeight(.medium)
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(color.opacity(0.15))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(color.opacity(0.35), lineWidth: 0.5)
            )
            .lineLimit(1)
    }
}

// MARK: - Preview

#if DEBUG
#Preview("CategoryChip") {
    HStack {
        CategoryChip(name: "Work", color: .blue)
        CategoryChip(name: "Personal", color: .green)
        CategoryChip(name: "Archived", color: .gray)
    }
    .padding()
}
#endif
