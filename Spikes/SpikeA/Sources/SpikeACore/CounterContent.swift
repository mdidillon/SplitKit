import SwiftUI

/// Spec §6.4 proof content: the count lives in the object, "view-local taps" in `@State`.
@MainActor @Observable public final class CounterContent: SpikeContent {
    public let id: ContentID
    public var count: Int
    /// Bound to the focusable text field, so typed text is content state too.
    public var note: String
    public let responderKind = ResponderKind.firstTextField
    @ObservationIgnored public private(set) var attachmentCount = 0
    @ObservationIgnored public private(set) var makeViewCalls = 0

    public var title: String { "Counter" }

    public init(id: ContentID = ContentID(), count: Int = 0, note: String = "") {
        self.id = id
        self.count = count
        self.note = note
    }

    public func makeView() -> AnyView {
        makeViewCalls += 1
        return AnyView(CounterView(model: self))
    }

    public func didAttach(to host: HostID) {
        attachmentCount += 1
        if attachmentCount > 1 { SpikeInvariant.failure("\(id) attached twice") }
    }

    public func willDetach(from host: HostID) {
        attachmentCount -= 1
    }
}

struct CounterView: View {
    @Bindable var model: CounterContent
    @State private var viewLocalTaps = 0

    var body: some View {
        VStack(spacing: 12) {
            Text("\(model.count)")
                .font(.system(size: 48, weight: .semibold).monospacedDigit())
            Button("+1") {
                model.count += 1
                viewLocalTaps += 1
            }
            .keyboardShortcut("=", modifiers: [.command])
            TextField("Type here", text: $model.note)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 240)
            Text("view-local taps: \(viewLocalTaps) (may reset on move)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(model.id.description)
                .font(.caption.monospaced())
                .foregroundStyle(.tertiary)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
