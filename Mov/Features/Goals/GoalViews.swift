import SwiftUI

struct SessionGoalView: View {
    @Environment(\.dismiss) private var dismiss
    let store: RunStore
    @State private var draft: RunGoal
    init(store: RunStore) { self.store=store;_draft=State(initialValue:store.goal) }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:16) {
                    Text("오늘은 어떻게\n달릴까요?").font(.largeTitle.bold()).padding(.bottom,8)
                    Text("목표에 도달해도 자동으로 종료되지 않아요.").font(.footnote).foregroundStyle(MovTokens.secondary)
                    ForEach(GoalKind.allCases,id:\.self) { kind in
                        Button { draft.kind=kind } label: {
                            VStack(alignment:.leading,spacing:8) {
                                Text(kind.title).font(.headline)
                                Text(kind == .none ? "거리와 시간에 얽매이지 않아요" : kind == .distance ? "원하는 거리를 달려요" : "정한 시간만큼 달려요").font(.subheadline)
                            }.frame(maxWidth:.infinity,alignment:.leading).padding(18)
                                .foregroundStyle(draft.kind == kind ? MovTokens.onBrand:MovTokens.text)
                                .background(draft.kind == kind ? MovTokens.brand:MovTokens.surface,in:RoundedRectangle(cornerRadius:16))
                        }.accessibilityIdentifier("goal-\(kind.rawValue)").accessibilityAddTraits(draft.kind == kind ? .isSelected:[])
                    }
                    if draft.kind == .distance {
                        HStack {
                            Picker("거리",selection:$draft.kilometers) { ForEach(2...1000,id:\.self){Text(MovNumber.display(Double($0)/2)).tag(Double($0)/2)} }.pickerStyle(.wheel).frame(height:150).accessibilityIdentifier("distanceWheel")
                            Text("km").font(.title3).padding(.trailing,32)
                        }
                    } else if draft.kind == .time {
                        Picker("시간",selection:$draft.minutes) { ForEach(Array(stride(from:10,through:360,by:10)),id:\.self){Text(RunGoal.duration($0)).tag($0)} }.pickerStyle(.wheel).frame(height:150).accessibilityIdentifier("timeWheel")
                    }
                }.padding(24)
            }.background(MovTokens.background)
                .safeAreaInset(edge:.bottom) { Button("이 목표로 달리기") {store.goal=draft;store.persist();dismiss()}.buttonStyle(MovPrimaryButtonStyle()).padding(24).background(MovTokens.background) }
                .navigationTitle("이번 러닝 목표").navigationBarTitleDisplayMode(.inline)
                .toolbar {ToolbarItem(placement:.cancellationAction){Button("닫기"){dismiss()}}}
        }.foregroundStyle(MovTokens.text).tint(MovTokens.text)
    }
}
struct WeeklyGoalView: View {
    @Environment(\.dismiss) private var dismiss
    let store: RunStore
    @State private var draft: WeeklyGoal
    init(store: RunStore) {self.store=store;_draft=State(initialValue:store.weekly)}
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:22) {
                    Text("차곡차곡,\n나만의 목표로").font(.largeTitle.bold())
                    Text("거리나 시간을 선택해 보세요.\n둘 다 선택하면 각각 채워져요.").foregroundStyle(MovTokens.secondary)
                    VStack(alignment:.leading,spacing:16) {
                        toggleRow("거리 목표",enabled:$draft.distanceEnabled)
                        if draft.distanceEnabled {
                            Stepper("\(MovNumber.display(draft.kilometers)) km",value:$draft.kilometers,in:1...500).font(.title2)
                            HStack { ForEach([1,5,10],id:\.self){amount in Button("+\(amount) km"){draft.kilometers=min(500,draft.kilometers+Double(amount))}.buttonStyle(.bordered)} }
                            Text("주간 거리 · 최대 500 km").font(.caption).foregroundStyle(MovTokens.secondary)
                        }
                    }.padding(18).background(MovTokens.surface,in:RoundedRectangle(cornerRadius:16))
                    VStack(alignment:.leading,spacing:16) {
                        toggleRow("시간 목표",enabled:$draft.timeEnabled)
                        if draft.timeEnabled {
                            Stepper(RunGoal.duration(draft.minutes),value:$draft.minutes,in:30...6000,step:30).font(.title2)
                            HStack { ForEach([30,60,180],id:\.self){amount in Button("+"+RunGoal.duration(amount)){draft.minutes=min(6000,draft.minutes+amount)}.buttonStyle(.bordered)} }
                            Text("주간 시간 · 최대 100시간").font(.caption).foregroundStyle(MovTokens.secondary)
                        }
                    }.padding(18).background(MovTokens.surface,in:RoundedRectangle(cornerRadius:16))
                }.padding(24)
            }.background(MovTokens.background)
                .safeAreaInset(edge:.bottom) {Button("목표 저장"){store.weekly=draft;store.persist();dismiss()}.buttonStyle(MovPrimaryButtonStyle()).padding(24).background(MovTokens.background)}
                .navigationTitle("이번 주 목표").navigationBarTitleDisplayMode(.inline)
                .toolbar{ToolbarItem(placement:.cancellationAction){Button("닫기"){dismiss()}}}
        }.foregroundStyle(MovTokens.text).tint(MovTokens.text)
    }
    private func toggleRow(_ title:String,enabled:Binding<Bool>)->some View {
        Button{enabled.wrappedValue.toggle()}label:{HStack{Text(title).font(.headline);Spacer();Image(systemName:"checkmark").foregroundStyle(enabled.wrappedValue ? MovTokens.brand:MovTokens.secondary)}}.frame(minHeight:44).accessibilityValue(enabled.wrappedValue ? "선택됨":"선택 안 됨")
    }
}
struct WeeklySummary: View {
    let store: RunStore
    var edit: ()->Void
    var body: some View {
        VStack(alignment:.leading,spacing:18) {
            HStack {Text("이번 주").font(.headline);Spacer();Text("샘플 합계").font(.caption).foregroundStyle(MovTokens.secondary)}
            if !store.weekly.distanceEnabled && !store.weekly.timeEnabled {
                Button("주간 목표 설정 하기",action:edit).frame(minHeight:44)
            }
            if store.weekly.distanceEnabled { progress("거리 목표",value:store.weeklyDistance,target:Double(store.weekly.kilometers),unit:"km") }
            if store.weekly.timeEnabled {progress("시간 목표",value:store.weeklySeconds/60,target:Double(store.weekly.minutes),unit:"분")}
            HStack{Spacer();Button("주간 목표 변경",action:edit).font(.footnote).frame(minHeight:44)}
        }.padding(.vertical,18)
    }
    private func progress(_ title:String,value:Double,target:Double,unit:String)->some View {
        VStack(alignment:.leading,spacing:12){
            HStack{Text(title).font(.caption).foregroundStyle(MovTokens.secondary);Spacer();Text("\(Int(value / max(1,target)*100))%").font(.subheadline)}
            HStack(alignment:.firstTextBaseline){Text(MovNumber.display(value)).font(.largeTitle.weight(.semibold)).monospacedDigit();Text("/ \(Int(target)) \(unit)").font(.subheadline)}
            ProgressView(value:min(1,max(0,value/max(1,target)))).tint(MovTokens.brand)
        }
    }
}
