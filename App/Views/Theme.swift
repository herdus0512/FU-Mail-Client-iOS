import SwiftUI
import UIKit

/// Light or dark: as the device is, or always one (Settings → Appearance; kept on this device).
enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }
    var label: String { rawValue.capitalized }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// The text a step smaller or larger than iOS's own size (Settings → Text size; kept on this device).
/// SF Mono is wider than the system font, so Smaller often reads best.
enum TextSize: String, CaseIterable, Identifiable {
    case smaller, standard, larger

    var id: String { rawValue }

    var label: String {
        switch self {
        case .smaller: "Smaller"
        case .standard: "Default"
        case .larger: "Larger"
        }
    }

    /// iOS's size moved by this one step, within the sizes there are.
    func applied(to size: DynamicTypeSize) -> DynamicTypeSize {
        let all = DynamicTypeSize.allCases
        guard let index = all.firstIndex(of: size) else { return size }
        let step = switch self {
        case .smaller: -1
        case .standard: 0
        case .larger: 1
        }
        return all[min(max(index + step, 0), all.count - 1)]
    }
}

/// Applies the Text size setting to everything under it.
struct TextSizing: ViewModifier {
    @AppStorage("textSize") private var textSize: TextSize = .standard
    @Environment(\.dynamicTypeSize) private var systemSize

    func body(content: Content) -> some View {
        content.dynamicTypeSize(textSize.applied(to: systemSize))
    }
}

/// The connection indicator's and warnings' colours: macOS's green, orange and red, light or dark
/// (the same as the Mac app and the Android app).
enum StatusColors {
    static let connected = Color(light: 0x248A3D, dark: 0x30D158)
    static let connecting = Color(light: 0xC93400, dark: 0xFF9F0A)
    static let failed = Color(light: 0xD70015, dark: 0xFF453A)
    static let warning = Color(light: 0xB25000, dark: 0xFF9F0A)
    static let bannerBackground = Color(light: 0xFFE4E1, dark: 0x4A1F1C)
    static let bannerText = Color(light: 0x7A1610, dark: 0xFFDAD6)
}

extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(rgb: dark) : UIColor(rgb: light) })
    }
}

private extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(red: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
                  blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
    }
}

/// A segmented choice in the app's own font and text size. iOS's segmented picker is a system control
/// that stays in the system font at the system size, whatever Settings → Text size says.
struct SegmentedChoice<Value: Hashable>: View {
    var options: [(value: Value, label: String)]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.value) { option in
                let selected = option.value == selection
                Button {
                    selection = option.value
                } label: {
                    Text(option.label)
                        .font(.subheadline.weight(selected ? .semibold : .regular))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background {
                            if selected {
                                Capsule().fill(Color(.systemBackground)).shadow(color: .black.opacity(0.12), radius: 2, y: 1)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Capsule().fill(Color(.tertiarySystemFill)))
    }
}

/// A warning line, as on the Mac: an orange triangle and the text.
struct WarningText: View {
    var text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: "exclamationmark.triangle")
        }
        .font(.footnote)
        .foregroundStyle(StatusColors.warning)
    }
}
