import SwiftUI

/// Temporary component check screen; not the product home screen.
struct DevelopmentView: View {
    @AppStorage("appearance") private var appearance = ThemePreference.system.rawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var didTap = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MovTokens.spacing) {
                HStack {
                    Text("모브").font(.system(.largeTitle, design: .rounded, weight: .bold))
                    Spacer()
                    Text("DEVELOPMENT").font(.caption2.weight(.bold))
                        .padding(10).background(MovTokens.surface, in: Capsule())
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text("작은 시작,\n나만의 움직임.").font(.largeTitle.bold())
                    Text("개발 확인 화면").font(.headline)
                    Text("테마와 기본 컴포넌트를 확인하는 임시 화면입니다.")
                        .font(.subheadline).foregroundStyle(MovTokens.secondary)
                }
                VStack(alignment: .leading, spacing: 16) {
                    Label("화면 테마", systemImage: "circle.lefthalf.filled").font(.headline)
                    Picker("화면 테마", selection: $appearance) {
                        ForEach(ThemePreference.allCases) { theme in
                            Text(theme.title).tag(theme.rawValue)
                        }
                    }.pickerStyle(.segmented).accessibilityIdentifier("themePicker")
                    Text("선택한 테마는 이 기기에 저장됩니다.")
                        .font(.footnote).foregroundStyle(MovTokens.secondary)
                    Text(colorScheme == .dark ? "현재 화면: 다크" : "현재 화면: 라이트")
                        .font(.footnote).accessibilityIdentifier("activeTheme")
                }.padding(20).background(MovTokens.surface, in: RoundedRectangle(cornerRadius: MovTokens.radius))
                VStack(alignment: .leading, spacing: 12) {
                    Text("기본 컴포넌트").font(.title3.bold())
                    Text("본문은 읽기 편한 중립 색상을 사용합니다.")
                    Text("보조 설명과 상태 메시지").font(.subheadline).foregroundStyle(MovTokens.secondary)
                    Button(didTap ? "확인 완료" : "버튼 동작 확인") {
                        if reduceMotion { didTap = true }
                        else { withAnimation(.easeOut(duration: 0.15)) { didTap = true } }
                    }.buttonStyle(MovPrimaryButtonStyle()).accessibilityIdentifier("primaryButton")
                    Button("아직 사용할 수 없어요") {}.buttonStyle(MovPrimaryButtonStyle()).disabled(true)
                    Text(didTap ? "버튼이 정상적으로 동작합니다." : "위 버튼을 눌러 동작을 확인하세요.")
                        .font(.footnote).foregroundStyle(MovTokens.secondary)
                        .accessibilityIdentifier("buttonStatus")
                }
                Text("실제 서비스 화면은 다음 단계에서 구성합니다.")
                    .font(.caption).foregroundStyle(MovTokens.secondary)
            }.padding(24).frame(maxWidth: 600).frame(maxWidth: .infinity)
        }.background(MovTokens.background).foregroundStyle(MovTokens.text)
    }
}

#Preview("Light") { DevelopmentView().preferredColorScheme(.light) }
#Preview("Dark") { DevelopmentView().preferredColorScheme(.dark) }
