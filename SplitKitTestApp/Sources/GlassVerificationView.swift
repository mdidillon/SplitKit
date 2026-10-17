import SwiftUI

/// Phase 2 entry verification (Docs/Design.md §5): shows glass, materials, semantic colours and the
/// live accessibility environment so Docs/GlassAccessibility-checklist.md can be worked through.
/// Test app only; deliberately no fallback code for any accessibility setting.
struct GlassVerificationView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var expanded = false

    var body: some View {
        ZStack {
            BusyBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    environmentSection
                    glassEffectSection
                    containerSection
                    buttonStyleSection
                    materialSection
                    semanticSection
                }
                .padding(20)
            }
        }
        .frame(minWidth: 760, minHeight: 640)
    }

    // MARK: Sections

    private var environmentSection: some View {
        section("Live environment values") {
            VStack(alignment: .leading, spacing: 4) {
                valueRow("colorScheme", "\(colorScheme)")
                valueRow("colorSchemeContrast", "\(colorSchemeContrast)")
                valueRow("accessibilityReduceTransparency", "\(reduceTransparency)")
                valueRow("accessibilityReduceMotion", "\(reduceMotion)")
            }
            .padding(10)
            .background(.background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Live environment values")
        }
    }

    private var glassEffectSection: some View {
        section("glassEffect(_:in:)") {
            HStack(spacing: 16) {
                glassSample("Glass.regular", glass: .regular)
                glassSample("Glass.clear", glass: .clear)
                glassSample("Glass.regular.tint(.orange)", glass: .regular.tint(.orange))
                glassSample("Glass.regular.interactive()", glass: .regular.interactive())
            }
        }
    }

    private var containerSection: some View {
        section("GlassEffectContainer(spacing:)") {
            VStack(alignment: .leading, spacing: 12) {
                GlassEffectContainer(spacing: 4) {
                    HStack(spacing: 4) {
                        pill("Title", systemImage: "chevron.down")
                        pill("Overflow", systemImage: "ellipsis")
                        if expanded {
                            pill("Focus", systemImage: "arrow.up.left.and.arrow.down.right")
                            pill("Close", systemImage: "xmark")
                        }
                    }
                }
                Button(expanded ? "Collapse pills" : "Expand pills (morphing)") {
                    withAnimation(.smooth) { expanded.toggle() }
                }
                .accessibilityLabel(expanded ? "Collapse pills" : "Expand pills with morphing animation")
            }
        }
    }

    private var buttonStyleSection: some View {
        section("Button styles") {
            HStack(spacing: 16) {
                Button("Glass") {}
                    .buttonStyle(.glass)
                    .accessibilityLabel("Glass button style")
                Button("Glass prominent") {}
                    .buttonStyle(.glassProminent)
                    .accessibilityLabel("Glass prominent button style")
                Button("Glass, small") {}
                    .buttonStyle(.glass)
                    .controlSize(.small)
                    .accessibilityLabel("Small glass button style")
            }
        }
    }

    private var materialSection: some View {
        section(".thinMaterial over a busy background") {
            ZStack {
                BusyBackground()
                Text("Thin material overlay")
                    .padding(24)
                    .frame(maxWidth: .infinity)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .padding(40)
            }
            .frame(height: 140)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Thin material overlay over a busy background")
        }
    }

    private var semanticSection: some View {
        section("Semantic text and separator") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Primary text").foregroundStyle(.primary)
                Text("Secondary text").foregroundStyle(.secondary)
                Rectangle()
                    .fill(Color(nsColor: .separatorColor))
                    .frame(height: 1)
                    .accessibilityHidden(true)
                Text("Line above: Color(nsColor: .separatorColor)").font(.callout).foregroundStyle(.secondary)
            }
            .padding(10)
            .background(.background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    // MARK: Building blocks

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(.background, in: Capsule())
            content()
        }
    }

    private func valueRow(_ name: String, _ value: String) -> some View {
        HStack {
            Text(name).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit()
        }
    }

    private func glassSample(_ title: String, glass: Glass) -> some View {
        Text(title)
            .font(.callout)
            .multilineTextAlignment(.center)
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 70)
            .glassEffect(glass, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Glass sample: \(title)")
    }

    private func pill(_ title: String, systemImage: String) -> some View {
        Button {} label: {
            Label(title, systemImage: systemImage).labelStyle(.iconOnly)
        }
        .buttonStyle(.glass)
        .accessibilityLabel(title)
    }
}

/// Busy backdrop drawn with shapes and gradients only, so transparency effects are easy to see.
private struct BusyBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [.red, .orange, .yellow, .green, .blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
            HStack(spacing: 0) {
                ForEach(0..<24, id: \.self) { index in
                    Rectangle().fill(index.isMultiple(of: 2) ? Color.black : Color.white).opacity(0.35)
                }
            }
            Circle().fill(.white).frame(width: 120).offset(x: -140, y: 20)
            Circle().stroke(.black, lineWidth: 12).frame(width: 200).offset(x: 160, y: -10)
        }
        .accessibilityHidden(true)
    }
}
