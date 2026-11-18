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

/// Every text a little smaller or larger than iOS's own size (Settings → Text size; kept on this
/// device): each size times one factor, the same as the Android app's, so chat text, cards, titles
/// and labels all change together and keep their proportions. SF Mono is wide, so Smaller often
/// reads best.
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

    /// As Android's (Theme.kt).
    var factor: CGFloat {
        switch self {
        case .smaller: 0.88
        case .standard: 1
        case .larger: 1.15
        }
    }

    /// The setting, for code outside views (the navigation bar's titles).
    static var current: TextSize {
        UserDefaults.standard.string(forKey: "textSize").flatMap(TextSize.init(rawValue:)) ?? .standard
    }
}

/// The app's sizes: iOS's size for a text style at the reader's own text size (Dynamic Type), times
/// the Text size factor.
enum AppFont {
    static func size(_ style: UIFont.TextStyle, _ dynamicTypeSize: DynamicTypeSize, _ textSize: TextSize) -> CGFloat {
        let traits = UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(dynamicTypeSize))
        return UIFont.preferredFont(forTextStyle: style, compatibleWith: traits).pointSize * textSize.factor
    }

    static func uiStyle(_ style: Font.TextStyle) -> UIFont.TextStyle {
        switch style {
        case .largeTitle: .largeTitle
        case .title: .title1
        case .title2: .title2
        case .title3: .title3
        case .headline: .headline
        case .subheadline: .subheadline
        case .callout: .callout
        case .footnote: .footnote
        case .caption: .caption1
        case .caption2: .caption2
        default: .body
        }
    }
}

extension View {
    /// `.appFont(.subheadline)`, at the app's size (see `TextSize`). The design (SF Mono, or the system
    /// font where a view asks for it) comes from around it, as with `.font`.
    func appFont(_ style: Font.TextStyle, weight: Font.Weight? = nil) -> some View {
        modifier(AppFontModifier(style: style, weight: weight))
    }
}

private struct AppFontModifier: ViewModifier {
    var style: Font.TextStyle
    var weight: Font.Weight?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage("textSize") private var textSize: TextSize = .standard

    func body(content: Content) -> some View {
        let size = AppFont.size(AppFont.uiStyle(style), dynamicTypeSize, textSize)
        content.font(.system(size: size, weight: weight ?? (style == .headline ? .semibold : .regular)))
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
                        .appFont(.subheadline, weight: selected ? .semibold : .regular)
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
        .appFont(.footnote)
        .foregroundStyle(StatusColors.warning)
    }
}
