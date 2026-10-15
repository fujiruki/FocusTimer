import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var store: TimerStore
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var speech = SpeechInput()
    @StateObject private var fieldSpeech = SpeechInput()
    @State private var dictatingField: DictationField?
    @State private var composer = DictationComposer()
    @State private var now = Date()
    @State private var goalText = ""
    @State private var stepText = ""
    @State private var workText = ""
    @State private var duration = 30
    @State private var selectedGoal: UUID?
    @State private var selectedStep: UUID?
    @State private var startWithoutGoal = false
    @State private var conditionText = ""
    @State private var laterText = ""
    @State private var showComplete = false
    @State private var highlightStart = false
    @State private var speechTarget: SpeechTarget = .work
    private let clock = Timer.publish(every:1,on:.main,in:.common).autoconnect()
    enum SpeechTarget: String, CaseIterable {case goal = "今日のゴール", step = "工程", work = "今の作業"}
    enum DictationField {case work, goal, step, condition, later}

    var body: some View {
        NavigationStack {
            ScrollViewReader {proxy in
                ScrollView {
                    VStack(alignment:.leading,spacing:24) {
                        dayBar
                        if let session = store.session {runningView(session)} else {startingView.id(Self.startCardID)}
                        goalsPanel(proxy)
                        voicePanel
                        Text(BuildInfo.current.label()).font(.caption2)
                            .foregroundStyle(BuildInfo.current.isRecent(at:now) ? Color.red : Color.secondary)
                            .frame(maxWidth:.infinity)
                        Link("AKERU LAB がつくりました",destination:URL(string:"https://akerulab.com/")!)
                            .font(.caption2).foregroundStyle(.secondary)
                            .frame(maxWidth:.infinity)
                    }.padding()
                }
            }
            .background(Color(uiColor:.systemGroupedBackground))
            .navigationTitle("フォーカスタイマー")
            .onReceive(clock) {now = $0}
            .onAppear {store.requestNotifications()}
            .onChange(of:scenePhase) {_,phase in if phase == .active {store.acknowledgeAlarm()}}
            .onChange(of:fieldSpeech.text) {_,recognized in
                guard let field = dictatingField, !recognized.isEmpty else {return}
                fieldText(field).wrappedValue = composer.compose(recognized)
            }
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
                Stepper("活動開始 \(store.startMinute/60)時",value:$store.startMinute,in:0...max(0,store.endMinute-60),step:60)
                Stepper("終了 \(store.endMinute/60)時",value:$store.endMinute,in:min(1440,store.startMinute+60)...1440,step:60)
            }.font(.caption)
            Text("活動終了までの時間は、実際の作業可能時間とは異なります。").font(.caption2).foregroundStyle(.secondary)
        }.cardStyle()
    }
    private static let startCardID = "startCard"
    private var preparedStep: WorkStep? {
        let title = workText.trimmingCharacters(in:.whitespacesAndNewlines)
        guard let goal = startGoalBinding.wrappedValue else {return nil}
        return store.goals.first(where: {$0.id == goal})?.steps.first(where: {$0.id == selectedStep && $0.title == title})
    }
    private func prepare(goal: DayGoal, step: WorkStep, proxy: ScrollViewProxy) {
        selectedGoal = goal.id
        selectedStep = step.id
        startWithoutGoal = false
        workText = step.title
        withAnimation(.easeInOut(duration:0.45)) {proxy.scrollTo(Self.startCardID,anchor:.top)}
        withAnimation(.easeOut(duration:0.2)) {highlightStart = true}
        DispatchQueue.main.asyncAfter(deadline:.now()+1.4) {withAnimation(.easeIn(duration:0.6)) {highlightStart = false}}
    }
    private var startingView: some View {
        VStack(alignment:.leading,spacing:12) {
            VStack(alignment:.leading,spacing:2) {
                Text("今から何をする？").font(.headline)
                if let step = preparedStep {Text("工程「\(step.title)」をこの設定で開始します").font(.caption).foregroundStyle(Color.accentColor)}
            }
            HStack {TextField("例：納まり検討",text:$workText).textFieldStyle(.roundedBorder);micButton(.work)}
            HStack {Text("時間");Spacer();Picker("分",selection:$duration) {ForEach([5,10,15,20,25,30,40,45,60,90],id:\.self) {Text("\($0)分").tag($0)}}.pickerStyle(.menu)}
            if !store.goals.isEmpty {
                HStack {Text("どのゴールのため？");Spacer();goalPicker(selection:startGoalBinding)}
            }
            Button {
                let title = workText.trimmingCharacters(in:.whitespacesAndNewlines)
                guard !title.isEmpty else {return}
                let goal = startGoalBinding.wrappedValue
                let goalSteps: [WorkStep] = store.goals.first(where: {$0.id == goal})?.steps ?? []
                let step: UUID? = goalSteps.first(where: {$0.id == selectedStep && $0.title == title})?.id
                store.start(title,minutes:duration,goal:goal,step:step);conditionText="";laterText=""
            } label: {
                Label("この作業を開始",systemImage:"play.fill").frame(maxWidth:.infinity).padding(8)
            }.buttonStyle(.borderedProminent).disabled(workText.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
            VStack(alignment:.leading,spacing:4) {
                Text("知らせ方").font(.caption).foregroundStyle(.secondary)
                HStack {Text("途中通知");Spacer();Picker("途中通知",selection:$store.reminderIntervalMinutes) {ForEach(ReminderPlanner.intervalChoices,id:\.self) {Text($0 == 0 ? "オフ" : "\($0)分ごと").tag($0)}}.pickerStyle(.menu)}
                HStack {Text("終了時");Spacer();Picker("終了時",selection:$store.endAlertMode) {ForEach(EndAlertMode.allCases,id:\.self) {Text($0.label).tag($0)}}.pickerStyle(.menu)}
                HStack {
                    Text("アラーム音");Spacer()
                    Picker("アラーム音",selection:$store.alarmSound) {ForEach(AlarmSound.allCases,id:\.self) {Text($0.label).tag($0)}}.pickerStyle(.menu)
                    Button {SoundPreview.shared.play(store.alarmSound)} label: {Image(systemName:"play.circle")}.buttonStyle(.borderless).disabled(store.alarmSound == .system).accessibilityLabel("試し聞き")
                }
                if store.endAlertMode == .untilNoticed {
                    Text(store.endRouting == .systemAlarm ? "止めるボタンを押すまで鳴ります（消音モード中も鳴ります）" : "30秒おきに最大10分鳴らし直します。アプリを開くと止まります（消音モード中は鳴りません）")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.padding(.top,8)
            Text("計画なしでも開始できます").font(.caption).foregroundStyle(.secondary)
        }.cardStyle()
        .overlay(RoundedRectangle(cornerRadius:16).stroke(Color.accentColor,lineWidth:3).opacity(highlightStart ? 1 : 0))
    }
    private func runningView(_ s: WorkSession) -> some View {
        VStack(alignment:.leading,spacing:22) {
            if let goal = LiveActivityContent.goalTitle(for:s,goals:store.goals) {
                group("今日のゴール") {
                    Text(goal).font(.headline)
                    if let step = LiveActivityContent.stepTitle(for:s,goals:store.goals) {Text("工程：\(step)").font(.subheadline).foregroundStyle(.secondary)}
                }
            } else if !store.goals.isEmpty {
                group("今日のゴール（未設定）") {
                    goalPicker(selection:Binding(get:{s.goalID},set:{store.setSessionGoal($0)}))
                }
            }
            group("今回の完成条件") {
                Text(s.title).font(.title2.bold())
                HStack {TextField("どこまでやれば完成？（任意）",text:$conditionText).textFieldStyle(.roundedBorder).onSubmit {store.setCondition(conditionText)};micButton(.condition)}
                if !s.finishCondition.isEmpty {Text(s.finishCondition).font(.headline)}
            }
            let elapsed = s.elapsed(at:now)
            let remaining = s.remaining(at:now)
            group(s.paused ? "中断中（作業時間は止まっています）" : "残り時間") {
                Text(remaining >= 0 ? format(remaining) : "超過 \(format(-remaining))")
                    .font(.system(size:42,weight:.bold,design:.rounded)).monospacedDigit()
                    .foregroundStyle(s.paused ? .orange : .primary)
                ProgressView(value:min(1,elapsed / max(s.originalSeconds,1))).tint(.teal).scaleEffect(x:1,y:4,anchor:.center).padding(.vertical,6)
                HStack {Text("当初 \(Int(s.originalSeconds/60))分");Spacer();Text("経過 \(format(elapsed))")}.font(.caption).foregroundStyle(.secondary)
                if s.extensionSeconds > 0 {
                    ProgressView(value:min(1,max(0,elapsed-s.originalSeconds)/s.extensionSeconds)).tint(.orange).padding(.top,6)
                    Text("延長 +\(Int(s.extensionSeconds/60))分（当初バーは維持）").font(.caption).foregroundStyle(.secondary)
                }
            }
            if remaining <= 0 && store.endAlertMode == .untilNoticed && !store.alarmAcknowledged {
                Button {store.acknowledgeAlarm()} label: {Label("アラームを止める",systemImage:"bell.slash.fill").frame(maxWidth:.infinity).padding(6)}
                    .buttonStyle(.borderedProminent).tint(.red)
            }
            HStack(spacing:8) {
                Button(s.paused ? "再開" : "中断") {s.paused ? store.resume() : store.pause()}.buttonStyle(.borderedProminent)
                Button("+5分") {store.extendFive()}.buttonStyle(.bordered)
                Button("終了") {showComplete = true}.buttonStyle(.bordered)
            }.font(.subheadline)
            group("あとでやること") {
                HStack {TextField("思いついたことをメモ",text:$laterText).textFieldStyle(.roundedBorder).onSubmit {store.setLaterNote(laterText)};micButton(.later)}
                if !s.laterNote.isEmpty {Text(s.laterNote).font(.subheadline)}
            }
        }.cardStyle().onAppear {conditionText=s.finishCondition;laterText=s.laterNote}
    }
    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment:.leading,spacing:4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            content()
        }
    }
    private var voicePanel: some View {
        VStack(alignment:.leading,spacing:12) {
            HStack {Text("音声入力").font(.headline);Spacer();Picker("入力先",selection:$speechTarget) {ForEach(SpeechTarget.allCases,id:\.self) {Text($0.rawValue).tag($0)}}.pickerStyle(.menu)}
            Button {fieldSpeech.stop();speech.toggle()} label: {Label(speech.listening ? "録音を止める" : "声で入力",systemImage:speech.listening ? "stop.circle.fill" : "mic.fill").frame(maxWidth:.infinity).padding(8)}.buttonStyle(.borderedProminent)
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
            Text("各入力欄の横のマイクでも直接入力できます。").font(.caption).foregroundStyle(.secondary)
            Text("最小試作：音声を文字に変換します。自然文から複数工程や時間を自動抽出する機能は未実装です。").font(.caption).foregroundStyle(.secondary)
        }.cardStyle()
    }
    private func goalsPanel(_ proxy: ScrollViewProxy) -> some View {
        VStack(alignment:.leading,spacing:12) {
            Text("今日のゴール → 工程").font(.headline)
            HStack {TextField("今日のゴール",text:$goalText).textFieldStyle(.roundedBorder);micButton(.goal);Button("追加") {store.addGoal(goalText);goalText="";commitDictation(.goal)}}
            ForEach(store.goals) {goal in
                VStack(alignment:.leading,spacing:8) {
                    Button {selectedGoal=goal.id;selectedStep=nil;startWithoutGoal=false} label: {HStack {Image(systemName:selectedGoal == goal.id ? "largecircle.fill.circle" : "circle");Text(goal.title).font(.headline);Spacer()}}
                    ForEach(goal.steps) {step in
                        HStack {
                            Button {store.toggleStep(goal:goal.id,step:step.id)} label: {Image(systemName:step.done ? "checkmark.circle.fill" : "circle")}
                            Text(step.title).strikethrough(step.done)
                            Spacer()
                            Button("開始") {prepare(goal:goal,step:step,proxy:proxy)}.disabled(store.session != nil || step.done)
                        }.font(.subheadline)
                    }
                    if selectedGoal == goal.id {HStack {TextField("工程を追加",text:$stepText).textFieldStyle(.roundedBorder);micButton(.step);Button("追加") {store.addStep(stepText,goalID:goal.id);stepText="";commitDictation(.step)}}}
                }.padding(10).background(.gray.opacity(0.07),in:RoundedRectangle(cornerRadius:10))
            }
        }.cardStyle()
    }
    private var startGoalBinding: Binding<UUID?> {
        Binding(
            get: {
                if startWithoutGoal {return nil}
                if let selectedGoal, store.goals.contains(where: {$0.id == selectedGoal}) {return selectedGoal}
                return (store.goals.first {$0.steps.isEmpty || $0.steps.contains {!$0.done}} ?? store.goals.first)?.id
            },
            set: {startWithoutGoal = $0 == nil; selectedGoal = $0; selectedStep = nil}
        )
    }
    private func fieldText(_ field: DictationField) -> Binding<String> {
        switch field {
        case .work:return $workText
        case .goal:return $goalText
        case .step:return $stepText
        case .condition:return $conditionText
        case .later:return $laterText
        }
    }
    private func finishDictation(_ field: DictationField) {
        if dictatingField == field {dictatingField = nil}
        switch field {
        case .condition:store.setCondition(conditionText)
        case .later:store.setLaterNote(laterText)
        default:break
        }
    }
    private func commitDictation(_ field: DictationField) {
        guard dictatingField == field, fieldSpeech.listening else {return}
        composer.commit(recognized:fieldSpeech.text)
    }
    private func micButton(_ field: DictationField) -> some View {
        let active = dictatingField == field && fieldSpeech.listening
        return Button {
            if active {fieldSpeech.stop();return}
            speech.stop()
            fieldSpeech.stop()
            composer.begin(current:fieldText(field).wrappedValue)
            fieldSpeech.text = ""
            dictatingField = field
            fieldSpeech.onFinish = {finishDictation(field)}
            fieldSpeech.toggle()
        } label: {
            Image(systemName:active ? "stop.circle.fill" : "mic.fill").foregroundStyle(active ? Color.red : Color.accentColor)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(active ? "音声入力を止める" : "声で入力")
    }
    private func goalPicker(selection: Binding<UUID?>) -> some View {
        Picker("今日のゴール",selection:selection) {
            Text("なし").tag(UUID?.none)
            ForEach(store.goals) {Text($0.title).tag(Optional($0.id))}
        }.pickerStyle(.menu)
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
