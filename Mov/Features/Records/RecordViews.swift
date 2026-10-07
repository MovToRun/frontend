import SwiftUI

struct RecordRow: View {
    let record:RunRecord
    var showChevron=false
    var body: some View {
        HStack(spacing:14) {
            SampleMap(route:record.isValid).frame(width:68,height:68).clipShape(RoundedRectangle(cornerRadius:12)).accessibilityHidden(true)
            VStack(alignment:.leading,spacing:6){
                Text(record.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                Text(record.isValid ? "\(MovNumber.display(record.kilometers)) km":"비유효 러닝").font(.headline)
                Text(record.date.formatted(date:.abbreviated,time:.omitted)).font(.caption).foregroundStyle(MovTokens.secondary)
                Text("\(RunRecord.clock(record.seconds)) · \(record.pace)/km · 샘플").font(.caption2).foregroundStyle(MovTokens.secondary)
            }
            Spacer(minLength:0);if showChevron {Image(systemName:"chevron.right").font(.caption).foregroundStyle(MovTokens.secondary)}
        }.padding(.vertical,12).foregroundStyle(MovTokens.text)
    }
}
struct RecordsView: View {
    let store:RunStore
    var body: some View {
        List {
            Section {Text("기기에 저장한 샘플 기록").font(.caption).foregroundStyle(MovTokens.secondary).listRowSeparator(.hidden)}
            if store.records.isEmpty {ContentUnavailableView("아직 기록이 없어요",systemImage:"figure.run",description:Text("첫 샘플 러닝을 시작해 보세요.")).listRowSeparator(.hidden)}
            ForEach(store.records) {record in
                NavigationLink {RecordDetailView(store:store,record:record)} label:{RecordRow(record:record)}.accessibilityIdentifier("recordRow").listRowBackground(MovTokens.background).listRowInsets(EdgeInsets(top:0,leading:24,bottom:0,trailing:24))
            }
        }.listStyle(.plain).scrollContentBackground(.hidden).background(MovTokens.background)
    }
}
struct RecordDetailView: View {
    let store:RunStore
    let record:RunRecord
    @Environment(\.dismiss) private var dismiss
    @State private var editing=false
    @State private var deleting=false
    private var current:RunRecord {store.records.first{$0.id==record.id} ?? record}
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:24) {
                Text(current.title).font(.title.bold()).fixedSize(horizontal:false,vertical:true).accessibilityIdentifier("recordTitle")
                Text(current.date.formatted(date:.abbreviated,time:.shortened)).font(.subheadline).foregroundStyle(MovTokens.secondary)
                DemoCaption()
                if !current.isValid {Text("비유효 러닝 · 샘플 거리가 0 km인 기록입니다.").font(.subheadline).padding(14).background(MovTokens.surface,in:RoundedRectangle(cornerRadius:12))}
                MetricView(record:current)
                SampleMap(route:current.isValid).frame(height:220).clipShape(RoundedRectangle(cornerRadius:16))
                Text("샘플 경로 · 실제 이동 경로가 아닙니다.").font(.caption).foregroundStyle(MovTokens.secondary)
                if !current.memo.isEmpty {Text("메모").font(.headline);Text(current.memo).accessibilityIdentifier("recordMemo").frame(maxWidth:.infinity,alignment:.leading).fixedSize(horizontal:false,vertical:true)}
                Button("이 러닝 기록 삭제",role:.destructive){deleting=true}.frame(maxWidth:.infinity,minHeight:48)
            }.padding(24)
        }.background(MovTokens.background).foregroundStyle(MovTokens.text)
            .navigationTitle("러닝 기록").navigationBarTitleDisplayMode(.inline).toolbar(.visible,for:.navigationBar)
            .toolbar{ToolbarItem(placement:.topBarTrailing){Button{editing=true}label:{Image(systemName:"pencil")}.accessibilityLabel("제목과 메모 편집")}}
            .sheet(isPresented:$editing){RecordEditView(store:store,record:current)}
            .confirmationDialog("이 샘플 기록을 삭제할까요?",isPresented:$deleting,titleVisibility:.visible){Button("이 러닝 기록 삭제",role:.destructive){store.delete(current.id);dismiss()}.accessibilityIdentifier("confirmDeleteRecord");Button("취소",role:.cancel){}}
    }
}
struct RecordEditView:View {
    let store:RunStore
    @State var record:RunRecord
    @Environment(\.dismiss) private var dismiss
    private enum Field:Hashable {case title,memo}
    @FocusState private var focus:Field?
    var body:some View {
        NavigationStack {
            Form {
                Section("제목"){TextField("러닝 제목",text:$record.title).focused($focus,equals:.title).overlay(alignment:.bottom){Rectangle().fill(focus == .title ? MovTokens.brand:.clear).frame(height:1)}}
                Section("메모"){TextField("샘플 러닝 메모",text:$record.memo,axis:.vertical).accessibilityIdentifier("recordMemoInput").lineLimit(3...8).focused($focus,equals:.memo).overlay(alignment:.bottom){Rectangle().fill(focus == .memo ? MovTokens.brand:.clear).frame(height:1)}}
                Section {Text("제목과 메모만 수정할 수 있어요. 샘플 측정값은 유지됩니다.").font(.caption)}
            }.navigationTitle("기록 편집").navigationBarTitleDisplayMode(.inline)
                .toolbar{ToolbarItem(placement:.cancellationAction){Button("취소"){dismiss()}};ToolbarItem(placement:.confirmationAction){Button("저장"){record.title=record.title.trimmingCharacters(in:.whitespacesAndNewlines);store.update(record);dismiss()}.disabled(record.title.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)}}
        }.tint(MovTokens.text)
    }
}
struct ProfileView:View {
    let store:RunStore
    @State private var showRules=false
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:24) {
                Text("나의 러닝 카드").font(.headline)
                VStack(alignment:.leading,spacing:24) {
                    HStack{Text("샘플 러닝 프로필").font(.caption).foregroundStyle(MovTokens.secondary);Spacer();BrandMark()}
                    HStack(spacing:16){Image(systemName:"person.fill").font(.title).frame(width:56,height:56).background(MovTokens.surface,in:Circle());VStack(alignment:.leading,spacing:8){Text(store.tier).font(.caption);Text("샘플 러너").font(.title.bold());Text("조금씩, 멀리 가는 중").font(.subheadline).foregroundStyle(MovTokens.secondary)}}
                    Divider()
                    HStack(alignment:.top){VStack(alignment:.leading,spacing:10){Text("활동일").font(.caption).foregroundStyle(MovTokens.secondary);Text("\(store.activityDays)일").font(.title2.bold())};Spacer();VStack(alignment:.leading,spacing:10){Text("최근 1달 평균 러닝당 거리").font(.caption).foregroundStyle(MovTokens.secondary);Text("\(MovNumber.display(store.averageDistance)) km").font(.title2.bold())}}
                }.padding(24).background(RoundedRectangle(cornerRadius:20).stroke(Color(.separator),lineWidth:1))
                DemoCaption()
                DisclosureGroup("등급 기준",isExpanded:$showRules){Text("시작: 첫 유효 샘플 기록\n새싹: 10 km · 7일\n열정: 30 km · 10일\n도전: 100 km · 20일\n마스터: 300 km · 50일\n\n활동일은 하루 합계 1 km 이상, 4분 이상인 날짜입니다. 거리와 활동일 조건을 모두 충족해야 합니다.").font(.subheadline).frame(maxWidth:.infinity,alignment:.leading).padding(.top,12)}
                NavigationLink("샘플 러닝 기록 보기"){RecordsView(store:store).navigationTitle("러닝 기록")}.frame(minHeight:44)
            }.padding(24)
        }.background(MovTokens.background).foregroundStyle(MovTokens.text)
    }
}
