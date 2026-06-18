import SwiftUI
import AppKit

// MARK: - InspectorSection

struct InspectorSection<Content: View>: View {
    let title: String
    private let content: Content
    private let collapseState: Binding<Bool>?

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title        = title
        self.content      = content()
        self.collapseState = nil
    }

    init(_ title: String, isCollapsed: Binding<Bool>, @ViewBuilder content: () -> Content) {
        self.title        = title
        self.content      = content()
        self.collapseState = isCollapsed
    }

    private var collapsed: Bool { collapseState?.wrappedValue ?? false }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let binding = collapseState {
                HStack(spacing: 5) {
                    Image(systemName: binding.wrappedValue ? "chevron.right" : "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 10)
                    Text(title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 4)
                .contentShape(Rectangle())
                .onTapGesture { binding.wrappedValue.toggle() }
            } else {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                    .padding(.bottom, 4)
            }
            if !collapsed { content }
            Divider().padding(.top, collapsed ? 0 : 4)
        }
    }
}

// MARK: - InspectorField

struct InspectorField<Content: View>: View {
    let label: String
    private let content: Content

    init(_ label: String, @ViewBuilder content: () -> Content) {
        self.label   = label
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
            content
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 2)
    }
}

// MARK: - InspectorRow

struct InspectorRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 3)
    }
}

// MARK: - FloatEntryField
//
// Buffers edits locally; commits to the model only on Return or focus loss.
// This avoids TextField(value:format:) reverting on every keystroke that
// doesn't fully parse (e.g. the leading "-" of a negative number).

struct FloatEntryField: View {
    @Binding var value: Double
    var width: CGFloat
    var fractionDigits: Int = 3
    var fontSize: CGFloat = 12

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("", text: $text)
            .textFieldStyle(.squareBorder)
            .font(.system(size: fontSize, design: .monospaced))
            .frame(width: width)
            .focused($focused)
            .onAppear { text = formatted(value) }
            .onChange(of: value) { _, newVal in
                if !focused { text = formatted(newVal) }
            }
            .onChange(of: focused) { _, isFocused in
                if !isFocused { commit() }
            }
            .onSubmit { commit() }
    }

    private func commit() {
        guard let d = Double(text) else { return }
        value = d
        text = formatted(value)
    }

    private func formatted(_ d: Double) -> String {
        d.formatted(.number.precision(.fractionLength(0...fractionDigits)))
    }
}

// MARK: - ResettableSlider
//
// Standard NSSlider with double-click-to-reset behaviour.
// Uses NSViewRepresentable + NSClickGestureRecognizer because SwiftUI's
// simultaneousGesture(TapGesture(count:2)) is consumed by NSSlider's own
// mouse-tracking loop and never fires reliably on macOS.

struct ResettableSlider: NSViewRepresentable {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var defaultValue: Double

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSSlider {
        let slider = NSSlider(
            value: value,
            minValue: range.lowerBound,
            maxValue: range.upperBound,
            target: context.coordinator,
            action: #selector(Coordinator.sliderChanged(_:))
        )
        slider.isContinuous = true
        let dbl = NSClickGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.doubleClicked(_:))
        )
        dbl.numberOfClicksRequired = 2
        slider.addGestureRecognizer(dbl)
        return slider
    }

    func updateNSView(_ nsView: NSSlider, context: Context) {
        nsView.doubleValue = value
        nsView.minValue    = range.lowerBound
        nsView.maxValue    = range.upperBound
    }

    @MainActor
    class Coordinator: NSObject {
        var parent: ResettableSlider
        init(_ parent: ResettableSlider) { self.parent = parent }

        @objc func sliderChanged(_ sender: NSSlider) {
            parent.value = sender.doubleValue
        }

        @objc func doubleClicked(_ sender: NSClickGestureRecognizer) {
            parent.value = parent.defaultValue
        }
    }
}

// MARK: - ColorWell

/// NSColorWell wrapped as a SwiftUI view.
/// Replaces SwiftUI's ColorPicker, which hosts the system colour panel via an
/// XPC remote view controller (TUINSRemoteViewController). That process can
/// crash and freeze the window while the engine keeps running. NSColorWell
/// opens NSColorPanel directly with no XPC indirection.
struct ColorWell: NSViewRepresentable {
    @Binding var color: Color
    var supportsOpacity: Bool = true

    func makeNSView(context: Context) -> NSColorWell {
        let well = NSColorWell()
        well.target = context.coordinator
        well.action = #selector(Coordinator.colorChanged(_:))
        return well
    }

    func updateNSView(_ nsView: NSColorWell, context: Context) {
        context.coordinator.skipCallback = true
        nsView.color = NSColor(color)
        context.coordinator.skipCallback = false
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    @MainActor
    final class Coordinator: NSObject {
        var parent: ColorWell
        var skipCallback = false

        init(_ parent: ColorWell) { self.parent = parent }

        @objc func colorChanged(_ sender: NSColorWell) {
            guard !skipCallback else { return }
            let c = sender.color
            parent.color = Color(parent.supportsOpacity ? c : c.withAlphaComponent(1))
        }
    }
}
