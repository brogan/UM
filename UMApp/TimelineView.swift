import SwiftUI
import UMEngine

struct TimelineView: View {
    @Environment(AppController.self) private var controller
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if controller.engine.document.timeline.isEmpty {
                Spacer()
                Text("No recorded states.")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(
                            Array(controller.engine.document.timeline.enumerated()),
                            id: \.element.id
                        ) { idx, state in
                            stateRow(index: idx, state: state)
                            if idx < controller.engine.document.timeline.count - 1 {
                                Divider()
                            }
                        }
                    }
                }
            }
        }
        .frame(width: 500, height: 420)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Text("Timeline")
                .font(.headline)
            Text("\(controller.engine.document.timeline.count) states")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
            Button("Clear All") {
                controller.clearTimeline()
                dismiss()
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.red)
            .disabled(controller.engine.document.timeline.isEmpty)
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - State row

    private func stateRow(index: Int, state: UMTimelineState) -> some View {
        let isCurrent = controller.timelinePosition == index
        return HStack(spacing: 10) {
            // Index badge
            Text("\(index + 1)")
                .font(.system(size: 11, weight: isCurrent ? .bold : .regular, design: .monospaced))
                .foregroundStyle(isCurrent ? Color.accentColor : Color.secondary)
                .frame(width: 22, alignment: .trailing)

            // Navigate button
            Button {
                controller.navigateToState(index)
            } label: {
                Image(systemName: isCurrent ? "arrow.right.circle.fill" : "arrow.right.circle")
                    .foregroundStyle(isCurrent ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .help("Load this state")

            // Sprite count
            Text("\(state.cells.filter(\.isDrawn).count) sprites")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .leading)

            // Hold time label
            Text("Hold")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)

            // Hold time slider
            Slider(value: holdBinding(for: index), in: 6...240, step: 6)
                .frame(width: 140)

            // Value display in seconds
            Text(String(format: "%.1f s", Double(state.holdFrames) / 24.0))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.primary)
                .frame(width: 38, alignment: .trailing)

            Spacer()

            // Delete
            Button {
                controller.deleteTimelineState(index)
            } label: {
                Image(systemName: "xmark.circle")
                    .foregroundStyle(Color.secondary)
            }
            .buttonStyle(.plain)
            .help("Delete this state")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(isCurrent ? Color.accentColor.opacity(0.07) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { controller.navigateToState(index) }
    }

    // MARK: - Bindings

    private func holdBinding(for index: Int) -> Binding<Double> {
        Binding(
            get: {
                index < controller.engine.document.timeline.count
                    ? Double(controller.engine.document.timeline[index].holdFrames)
                    : 48
            },
            set: {
                guard index < controller.engine.document.timeline.count else { return }
                controller.engine.document.timeline[index].holdFrames = max(6, Int($0))
            }
        )
    }
}
