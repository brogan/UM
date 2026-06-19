import SwiftUI
import UMEngine

struct ColorPalettePickerView: View {
    @Environment(AppController.self) private var controller
    var apply: (UMColor) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedPaletteID: UUID? = nil
    @State private var alpha: Double = 1.0

    private var activePalette: UMColorPalette? {
        let id = selectedPaletteID ?? controller.projectColorPalettes.first?.id
        return controller.projectColorPalettes.first { $0.id == id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if controller.projectColorPalettes.isEmpty {
                Text("No color palettes.\nGenerate one in the left panel under PALETTES.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
                    .frame(maxWidth: .infinity)
            } else {
                if controller.projectColorPalettes.count > 1 {
                    Picker("", selection: Binding(
                        get: { selectedPaletteID ?? controller.projectColorPalettes.first?.id },
                        set: { selectedPaletteID = $0 }
                    )) {
                        ForEach(controller.projectColorPalettes) { p in
                            Text(p.name).tag(Optional(p.id))
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .padding(.horizontal, 8)
                }

                if let palette = activePalette {
                    Text(palette.name)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 8)

                    swatchGrid(palette.colors)
                }

                Divider()

                HStack(spacing: 6) {
                    Text("Alpha")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(width: 36, alignment: .leading)
                    Slider(value: $alpha, in: 0...1)
                    Text("\(Int((alpha * 100).rounded()))%")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, alignment: .trailing)
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 4)
            }
        }
        .padding(.top, 8)
        .frame(minWidth: 196)
    }

    private func swatchGrid(_ colors: [UMColor]) -> some View {
        let swatchSize: CGFloat = 20
        let cols = 8
        return LazyVGrid(
            columns: Array(repeating: GridItem(.fixed(swatchSize), spacing: 2), count: cols),
            spacing: 2
        ) {
            ForEach(Array(colors.enumerated()), id: \.offset) { _, color in
                Rectangle()
                    .fill(Color(red: color.r, green: color.g, blue: color.b, opacity: alpha))
                    .frame(width: swatchSize, height: swatchSize)
                    .overlay(Rectangle().strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
                    .onTapGesture {
                        apply(color.withAlpha(alpha))
                        dismiss()
                    }
            }
        }
        .padding(.horizontal, 8)
    }
}
