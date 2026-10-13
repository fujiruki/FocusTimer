import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var store: TimerStore
    @StateObject private var speech = SpeechInput()
    @State private var now = Date()
    @State private var goalText = ""
    @State private var stepText = ""
    @State private var workText = ""
    @State private var duration = 30
    @State private var selectedGoal: UUID?
    @State private var selectedStep: UUID?
    @State private var conditionText = ""
    @State private var laterText = ""
    @State private var showComplete = false
    @State private var speechTarget: SpeechTarget = .work
    private let clock = Timer.publish(every:1,on:.main,in:.common).autoconnect()
    enum SpeechTarget: String, CaseIterable {case goal = "今日のゴール", step = "工程", work = "今の作業"}

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:18) {
                    dayBar
                    if let session = store.session {runningView(session)} else {startingView}
                    voicePanel
                    goalsPanel
                }.padding()
            }
            .background(Color(uiColor:.systemGroupedBackground))
            .navigationTitle("フォーカスタイマー")
            .onReceive(clock) {now = $0}
            .onAppear {store.requestNotifications()}
            .alert("作業を終了しますか？",isPresented:$showComplete) {
                Button("タイマーだけ終了") {store.finish(markStepDone:false)}
                Button("工程も完了") {store.finish(markStepDone:true)}
                Button("戻る",role:.cancel) {}
            } message: {Text("時間切れだけでは工程は完了しません。")}
        }
    }
    private var dayBar: some View {
        VStack(alignment:.leading,spacing:10) {
            Text("今日の24時間").font(.headline)
            GeometryReader {geo in
                ZStack(alignment:.leading) {
                    RoundedRectangle(cornerRadius:6).fill(.gray.opacity(0.17))
                    let start = CGFloat(store.startMinute)/1440
                    let end = CGFloat(store.endMinute)/1440
                    RoundedRectangle(cornerRadius:5).fill(.teal.opacity(0.32)).frame(width:max(0,geo.size.width*(end-start))).offset(x:geo.size.width*start)
                    Rectangle().fill(.primary).frame(width:2).offset(x:geo.size.width*CGFloat(Calendar.current.component(.hour,from:now)*60+Calendar.current.component(.minute,from:now))/1440)
                }
            }.frame(height:25)
            HStack {Text("0時");Spacer();Text("活動 \(store.startMinute/60):\(String(format:"%02d",store.startMinute%60))〜\(store.endMinute/60):\(String(format:"%02d",store.endMinute%60))");Spacer();Text("24時")}.font(.caption).foregroundStyle(.secondary)
            Text("現在 \(now.formatted(date:.omitted,time:.shortened))　活動終了まで \(max(0,store.endMinute - (Calendar.current.component(.hour,from:now)*60 + Calendar.current.component(.minute,from:now))))分")
                .font(.subheadline)
            HStack {
                Stepper("活動開始 \(store.startMinute/60)時",value:$store.startMinute,in:0...1380,step:60)
                Stepper("終了 \(store.endMinute/60)時",value:$store.endMinute,in:60...1440,step:60)
            }.font(.caption)
            Text("活動終了までの時間は、実際の作業可能時間とは異なります。").font(.caption2).foregroundStyle(.secondary)
        }.cardStyle()
    }
    private var startingView: some View {
        VStack(alignment:.leading,spacing:12) {
            Text("今から何をする？").font(.headline)
            TextField("例：納まり検討",text:$workText).textFieldStyle(.roundedBorder)
            HStack {Text("時間");Spacer();Picker("分",selection:$duration) {ForEach([5,10,15,20,25,30,40,45,60,90],id:\.self) {Text("\($0)分").tag($0)}}.pickerStyle(.menu)}
            Button {let title = workText.trimmingCharacters(in:.whitespacesAndNewlines); if !title.isEmpty {store.start(title,minutes:duration,goal:selectedGoal,step:selectedStep);conditionText="";laterText=""}} label: {
                Label("この作業を開始",systemImage:"play.fill").frame(maxWidth:.infinity).padding(8)
            }.buttonStyle(.borderedProminent).disabled(workText.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
            Text("計画なしでも開始できます").font(.caption).foregroundStyle(.secondary)
        }.cardStyle()
    }
    private func runningView(_ s: WorkSession) -> some View {
        VStack(alignment:.leading,spacing:12) {
            Text("今の作業").font(.caption).foregroundStyle(.secondary)
            Text(s.title).font(.title2.bold())
            TextField("今回の完成条件（任意）",text:$conditionText).textFieldStyle(.roundedBorder).onSubmit {store.setCondition(conditionText)}
            if !s.finishCondition.isEmpty {Text("完成条件：\(s.finishCondition)").font(.headline)}
            let elapsed = s.elapsed(at:now)
            let remaining = s.remaining(at:now)
            Text(remaining >= 0 ? format(remaining) : "超過 \(format(-remaining))")
                .font(.system(size:42,weight:.bold,design:.rounded)).monospacedDigit()
            ProgressView(value:min(1,elapsed / max(s.originalSeconds,1))).tint(.teal).scaleEffect(x:1,y:4,anchor:.center).padding(.vertical,8)
            HStack {Text("当初 \(Int(s.originalSeconds/60))分");Spacer();Text("経過 \(format(elapsed))")}.font(.caption)
            if s.extensionSeconds > 0 {
                ProgressView(value:min(1,max(0,elapsed-s.originalSeconds)/s.extensionSeconds)).tint(.orange)
                Text("延長 +\(Int(s.extensionSeconds/60))分（当初バーは維持）").font(.caption)
            }
            HStack(spacing:8) {
                Button(s.paused ? "再開" : "中断") {s.paused ? store.resume() : store.pause()}.buttonStyle(.borderedProminent)
                Button("+5分") {store.extendFive()}.buttonStyle(.bordered)
                Button("終了") {showComplete = true}.buttonStyle(.bordered)
            }.font(.subheadline)
            TextField("あとでやること・再開メモ",text:$laterText).textFieldStyle(.roundedBorder).onSubmit {store.setLaterNote(laterText)}
            if !s.laterNote.isEmpty {Text("メモ：\(s.laterNote)").font(.subheadline)}
            if s.paused {Text("中断中：作業時間は止まっています").foregroundStyle(.orange)}
        }.cardStyle().onAppear {conditionText=s.finishCondition;laterText=s.laterNote}
    }
    private var voicePanel: some View {
        VStack(alignment:.leading,spacing:12) {
            HStack {Text("音声入力").font(.headline);Spacer();Picker("入力先",selection:$speechTarget) {ForEach(SpeechTarget.allCases,id:\.self) {Text($0.rawValue).tag($0)}}.pickerStyle(.menu)}
            Button {speech.toggle()} label: {Label(speech.listening ? "録音を止める" : "声で入力",systemImage:speech.listening ? "stop.circle.fill" : "mic.fill").frame(maxWidth:.infinity).padding(8)}.buttonStyle(.borderedProminent)
            TextField("認識結果を編集できます",text:$speech.text,axis:.vertical).textFieldStyle(.roundedBorder)
            Button("入力内容を反映") {
                let t=speech.text.trimmingCharacters(in:.whitespacesAndNewlines)
                guard !t.isEmpty else {return}
                switch speechTarget {
                case .goal:store.addGoal(t)
                case .step:if let g=selectedGoal {store.addStep(t,goalID:g)}
                case .work:workText=t
                }
                speech.text=""
            }.disabled(speech.text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || (speechTarget == .step && selectedGoal == nil))
            if let error=speech.errorMessage {Text(error).font(.caption).foregroundStyle(.red)}
            Text("最小試作：音声を文字に変換します。自然文から複数工程や時間を自動抽出する機能は未実装です。").font(.caption).foregroundStyle(.secondary)
        }.cardStyle()
    }
    private var goalsPanel: some View {
        VStack(alignment:.leading,spacing:12) {
            Text("今日のゴール → 工程").font(.headline)
            HStack {TextField("今日のゴール",text:$goalText).textFieldStyle(.roundedBorder);Button("追加") {store.addGoal(goalText);goalText=""}}
            ForEach(store.goals) {goal in
                VStack(alignment:.leading,spacing:8) {
                    Button {selectedGoal=goal.id;selectedStep=nil} label: {HStack {Image(systemName:selectedGoal == goal.id ? "largecircle.fill.circle" : "circle");Text(goal.title).font(.headline);Spacer()}}
                    ForEach(goal.steps) {step in
                        HStack {
                            Button {store.toggleStep(goal:goal.id,step:step.id)} label: {Image(systemName:step.done ? "checkmark.circle.fill" : "circle")}
                            Text(step.title).strikethrough(step.done)
                            Spacer()
                            Button("開始") {selectedGoal=goal.id;selectedStep=step.id;workText=step.title;if store.session == nil {store.start(step.title,minutes:duration,goal:goal.id,step:step.id)}}.disabled(store.session != nil || step.done)
                        }.font(.subheadline)
                    }
                    if selectedGoal == goal.id {HStack {TextField("工程を追加",text:$stepText).textFieldStyle(.roundedBorder);Button("追加") {store.addStep(stepText,goalID:goal.id);stepText=""}}}
                }.padding(10).background(.gray.opacity(0.07),in:RoundedRectangle(cornerRadius:10))
            }
        }.cardStyle()
    }
    private func format(_ seconds: TimeInterval) -> String {
        let v=Int(max(0,seconds).rounded(.up));return String(format:"%02d:%02d",v/60,v%60)
    }
}

private struct CardStyle: ViewModifier {
    func body(content:Content) -> some View {
        content.frame(maxWidth:.infinity,alignment:.leading).padding(16).background(Color(uiColor:.secondarySystemGroupedBackground),in:RoundedRectangle(cornerRadius:16))
    }
}
private extension View {func cardStyle() -> some View {modifier(CardStyle())}}
