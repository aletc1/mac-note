import SwiftUI

enum CategoryChipContrast {
    static func foregroundColor(for fillColor: Color) -> Color {
        usesLightForeground(for: fillColor) ? .white : .black
    }

    static func usesLightForeground(for fillColor: Color) -> Bool {
        let luminance = relativeLuminance(for: fillColor)
        let whiteContrast = contrastRatio(foregroundLuminance: 1, backgroundLuminance: luminance)
        let blackContrast = contrastRatio(foregroundLuminance: 0, backgroundLuminance: luminance)
        return whiteContrast >= blackContrast
    }

    private static func relativeLuminance(for color: Color) -> Double {
        let resolved = NSColor(color).usingColorSpace(.sRGB) ?? .black
        let red = linearized(Double(resolved.redComponent))
        let green = linearized(Double(resolved.greenComponent))
        let blue = linearized(Double(resolved.blueComponent))
        return 0.2126 * red + 0.7152 * green + 0.0722 * blue
    }

    private static func linearized(_ component: Double) -> Double {
        if component <= 0.03928 {
            return component / 12.92
        }
        return pow((component + 0.055) / 1.055, 2.4)
    }

    private static func contrastRatio(foregroundLuminance: Double, backgroundLuminance: Double) -> Double {
        let lighter = max(foregroundLuminance, backgroundLuminance)
        let darker = min(foregroundLuminance, backgroundLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }
}

/// A small rounded-rectangle tag that displays a category name in its color.
struct CategoryChip: View {
    let name: String
    let color: Color

    var body: some View {
        let contrastColor = CategoryChipContrast.foregroundColor(for: color)

        Text(name)
            .font(.caption2)
            .fontWeight(.medium)
            .lineLimit(1)
            .foregroundStyle(contrastColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .frame(minHeight: 16, alignment: .center)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(color)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(contrastColor, lineWidth: 1)
            )
    }
}

// MARK: - Preview

#if DEBUG
#Preview("CategoryChip") {
    HStack {
        CategoryChip(name: "Work", color: .blue)
        CategoryChip(name: "Personal", color: .green)
        CategoryChip(name: "Light", color: .yellow)
        CategoryChip(name: "Dark", color: .purple)
    }
    .padding()
}
#endif
