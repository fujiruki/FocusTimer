import Foundation
import UserNotifications

struct WorkStep: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var done = false
}
struct DayGoal: Identifiable, Codable {
    var id = UUID()
    var title: String
    var steps: [WorkStep] = []
}
struct WorkSession: Codable {
    var title: String
    var goalID: UUID?
    var stepID: UUID?
    var finishCondition: String = ""
    var originalSeconds: TimeInterval
    var extensionSeconds: TimeInterval = 0
    var elapsedBeforeRun: TimeInterval = 0
    var runStartedAt: Date?
    var paused: Bool = false
    var laterNote: String = ""

    func elapsed(at date: Date) -> TimeInterval {
        max(0, elapsedBeforeRun + (runStartedAt.map { max(0, date.timeIntervalSince($0)) } ?? 0))
    }
    func remaining(at date: Date) -> TimeInterval {
        originalSeconds + extensionSeconds - elapsed(at: date)
    }
}
struct SavedPlan: Codable {
    var date: Date
    var goals: [DayGoal]
    var session: WorkSession?
    var startMinute: Int
    var endMinute: Int
}

@MainActor
final class TimerStore: ObservableObject {
    @Published var goals: [DayGoal] = [] { didSet { save() } }
    @Published var session: WorkSession? { didSet { save() } }
    @Published var startMinute: Int = 9*60 { didSet { save() } }
    @Published var endMinute: Int = 18*60 { didSet { save() } }
    private let key = "focus-timer-daily-v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let value = try? JSONDecoder().decode(SavedPlan.self, from: data) {
            goals = Calendar.current.isDateInToday(value.date) ? value.goals : []
            session = value.session
            startMinute = value.startMinute
            endMinute = value.endMinute
        }
    }
    private func save() {
        let data = SavedPlan(date: .now, goals: goals, session: session, startMinute: startMinute, endMinute: endMinute)
        if let encoded = try? JSONEncoder().encode(data) { UserDefaults.standard.set(encoded, forKey: key) }
    }
    func addGoal(_ title: String) {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        goals.append(DayGoal(title: t))
    }
    func addStep(_ title: String, goalID: UUID) {
        guard let index = goals.firstIndex(where: {$0.id == goalID}) else { return }
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { goals[index].steps.append(WorkStep(title: t)) }
    }
    func toggleStep(goal: UUID, step: UUID) {
        guard let gi = goals.firstIndex(where: {$0.id == goal}), let si = goals[gi].steps.firstIndex(where: {$0.id == step}) else {return}
        goals[gi].steps[si].done.toggle()
    }
    func start(_ title: String, minutes: Int, goal: UUID? = nil, step: UUID? = nil) {
        guard session == nil, minutes > 0 else { return }
        session = WorkSession(title: title, goalID: goal, stepID: step, originalSeconds: TimeInterval(minutes*60), runStartedAt: .now)
        scheduleNotices()
    }
    func pause() {
        guard var s = session, !s.paused else { return }
        s.elapsedBeforeRun = s.elapsed(at: .now)
        s.runStartedAt = nil
        s.paused = true
        session = s
        clearNotices()
    }
    func resume() {
        guard var s = session, s.paused else { return }
        s.runStartedAt = .now
        s.paused = false
        session = s
        scheduleNotices()
    }
    func extendFive() {
        guard var s = session else { return }
        s.extensionSeconds += 300
        session = s
        scheduleNotices()
    }
    func setCondition(_ text: String) {
        guard var s = session else {return}
        s.finishCondition = text
        session = s
    }
    func setLaterNote(_ text: String) {
        guard var s = session else {return}
        s.laterNote = text
        session = s
    }
    func finish(markStepDone: Bool) {
        guard let s = session else {return}
        if markStepDone, let g = s.goalID, let step = s.stepID { toggleStep(goal:g, step:step) }
        clearNotices()
        session = nil
    }
    private func clearNotices() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["focus-half","focus-end","focus-last"])
    }
    func scheduleNotices() {
        clearNotices()
        guard let s = session, !s.paused else { return }
        let remaining = s.remaining(at: .now)
        let content = UNMutableNotificationContent()
        content.title = "作業の確認"
        content.body = s.finishCondition.isEmpty ? s.title : s.finishCondition
        content.sound = .default
        // 応答操作は必須にしない。残り時間の範囲で中間と終了を通知。
        for (identifier, offset) in [("focus-half",remaining/2),("focus-last",remaining-300),("focus-end",remaining)] {
            guard offset > 1 else {continue}
            let c = content.mutableCopy() as! UNMutableNotificationContent
            if identifier == "focus-end" {c.title = "設定時間になりました"}
            let request = UNNotificationRequest(identifier:identifier,content:c,trigger:UNTimeIntervalNotificationTrigger(timeInterval:offset,repeats:false))
            UNUserNotificationCenter.current().add(request)
        }
    }
    func requestNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert,.sound,.badge]) { _,_ in }
    }
}
