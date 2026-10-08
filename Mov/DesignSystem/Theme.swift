import SwiftUI

enum ThemePreference: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String {
        switch self { case .system: "시스템"; case .light: "라이트"; case .dark: "다크" }
    }
    var colorScheme: ColorScheme? {
        switch self { case .system: nil; case .light: .light; case .dark: .dark }
    }
}

enum MovTokens {
    static let brandHex: UInt32 = 0x5EF76D
    static let brand = Color(red: 94 / 255.0, green: 247 / 255.0, blue: 109 / 255.0)
    static let onBrand = Color(red: 23 / 255.0, green: 26 / 255.0, blue: 24 / 255.0)
    static let background = Color("Background")
    static let surface = Color("Surface")
    static let text = Color("Text")
    static let secondary = Color("SecondaryText")
    static let radius: CGFloat = 20
    static let spacing: CGFloat = 24
}

struct MovPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 52)
            .foregroundStyle(isEnabled ? MovTokens.onBrand : MovTokens.secondary)
            .background(isEnabled ? MovTokens.brand : MovTokens.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}
