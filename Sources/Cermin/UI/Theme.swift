import AppKit
import SwiftUI

extension Color {
    /// oklch(0.55 0.1 195) light / oklch(0.76 0.1 195) dark — design accent "Teal".
    static let accentTeal = Color(nsColor: NSColor(name: "accentTeal") { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 0.341, green: 0.772, blue: 0.771, alpha: 1)
            : NSColor(srgbRed: 0, green: 0.514, blue: 0.516, alpha: 1)
    })
    static let orbTeal = Color(red: 0.578, green: 0.852, blue: 0.849)
    static let sand = Color(red: 0.951, green: 0.799, blue: 0.679)
    static let surface = Color(nsColor: .windowBackgroundColor)
}

extension Text {
    /// Titles use Apple's serif (New York); UI stays SF Pro.
    func serif(_ size: CGFloat, italic: Bool = false) -> Text {
        let t = font(.system(size: size, weight: .regular, design: .serif))
        return italic ? t.italic() : t
    }
}

/// Glass capsule for toolbar, pill and toast (spec: ultraThinMaterial + 0.5pt inner stroke; glassEffect on macOS 26+).
struct GlassCapsule: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content.glassEffect(.regular, in: .capsule)
        } else {
            content
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.5), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
        }
    }
}

extension View {
    func glassCapsule() -> some View { modifier(GlassCapsule()) }
}

/// Primary/secondary capsule buttons used in onboarding, prompts and empty states.
struct PillButtonStyle: ButtonStyle {
    var prominent = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 14)
            .frame(height: 26)
            .foregroundStyle(prominent ? Color.white : Color.primary)
            .background(prominent ? AnyShapeStyle(Color.accentTeal) : AnyShapeStyle(.quaternary), in: Capsule())
            .opacity(configuration.isPressed ? 0.75 : 1)
            .contentShape(Capsule())
    }
}

/// Key cap like "⌃⌥⌘P".
struct KeyCap: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .padding(.horizontal, 6)
            .frame(height: 20)
            .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.separator, lineWidth: 0.5))
    }
}

// MARK: - "Pantulan" art (design v2): horizon at 62%, subject reflected below at ~25% opacity.

struct ReflectionArt<Subject: View>: View {
    var horizon: CGFloat = 0.62
    @ViewBuilder var subject: () -> Subject
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            ZStack {
                (scheme == .dark ? Color(white: 0.13) : Color(white: 0.955))
                Circle().fill(Color.orbTeal.opacity(scheme == .dark ? 0.35 : 0.6))
                    .frame(width: w * 0.62).blur(radius: 38)
                    .position(x: w * 0.4, y: h * 0.42)
                Circle().fill(Color.sand.opacity(scheme == .dark ? 0.3 : 0.65))
                    .frame(width: w * 0.36).blur(radius: 34)
                    .position(x: w * 0.78, y: h * 0.28)
                Rectangle().fill(.black.opacity(scheme == .dark ? 0.18 : 0.035))
                    .frame(height: h * (1 - horizon))
                    .position(x: w / 2, y: h * horizon + h * (1 - horizon) / 2)
                VStack(spacing: 0) {
                    subject()
                        .frame(width: w, height: h * horizon, alignment: .bottom)
                    subject()
                        .scaleEffect(x: 1, y: -1) // bottom-aligned above, top-aligned below = mirrored at the horizon
                        .frame(width: w, height: h * (1 - horizon), alignment: .top)
                        .clipped()
                        .opacity(0.25)
                        .mask(LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .init(x: 0.5, y: 0.55)))
                }
                Rectangle()
                    .fill(LinearGradient(colors: [.clear, .white.opacity(scheme == .dark ? 0.25 : 0.9), .clear],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(height: 1)
                    .position(x: w / 2, y: h * horizon)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Simple iPhone glyph used across the art.
struct PhoneGlyph: View {
    var width: CGFloat = 52
    var filled = true
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: width * 0.2, style: .continuous)
        shape
            .fill(filled ? (scheme == .dark ? Color(white: 0.16) : .white) : .clear)
            .overlay(shape.strokeBorder(scheme == .dark ? Color.white.opacity(0.9) : Color(white: 0.12), lineWidth: 2))
            .overlay(alignment: .top) {
                Capsule().fill(scheme == .dark ? Color.white.opacity(0.9) : Color(white: 0.12))
                    .frame(width: width * 0.28, height: 3).padding(.top, width * 0.13)
            }
            .frame(width: width, height: width * 2.05)
    }
}

/// Concentric rings (connecting state, onboarding, curtain).
struct Rings: View {
    var count = 3
    var spacing: CGFloat = 34
    var color: Color = .accentTeal
    var opacity: Double = 0.45

    var body: some View {
        ZStack {
            ForEach(0..<count, id: \.self) { i in
                Circle()
                    .strokeBorder(color.opacity(opacity * (1 - Double(i) / Double(count + 1))), lineWidth: 1)
                    .frame(width: CGFloat(i + 1) * spacing * 2, height: CGFloat(i + 1) * spacing * 2)
            }
        }
    }
}

/// Plain `State` storage without the `@State` macro.
/// shortcut: Command Line Tools ship without the SwiftUIMacros plugin that the macOS 27 SDK's `@State` needs;
/// switch back to `@State` once the project is built with full Xcode.
@propertyWrapper
struct ViewState<Value>: DynamicProperty {
    private let storage: State<Value>

    init(wrappedValue: Value) { storage = State(initialValue: wrappedValue) }

    var wrappedValue: Value {
        get { storage.wrappedValue }
        nonmutating set { storage.wrappedValue = newValue }
    }

    var projectedValue: Binding<Value> { storage.projectedValue }
}
