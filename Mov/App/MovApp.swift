import SwiftUI
import CoreText

@main
struct MovApp: App {
    init(){
        for name in ["MovFont0","MovFont1"] {
            if let url=Bundle.main.url(forResource:name,withExtension:"woff2",subdirectory:"Fonts") {
                CTFontManagerRegisterFontsForURL(url as CFURL,.process,nil)
            }
        }
    }
    @AppStorage("appearance") private var appearance = ThemePreference.system.rawValue
    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(ThemePreference(rawValue: appearance)?.colorScheme)
        }
    }
}
