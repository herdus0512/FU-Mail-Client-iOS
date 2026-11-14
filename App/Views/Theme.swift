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
