import Foundation
import Combine

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
    @Published var goals: [DayGoal] = [] { didSet { save(); if session != nil {syncLiveActivity()} } }
    @Published var session: WorkSession? { didSet { save() } }
    @Published var reminderIntervalMinutes: Int = ReminderPlanner.defaultInterval {
        didSet {
            guard !loading else {return}
            if !ReminderPlanner.intervalChoices.contains(reminderIntervalMinutes) {reminderIntervalMinutes = ReminderPlanner.defaultInterval}
            defaults.set(reminderIntervalMinutes, forKey: Self.intervalKey)
            scheduleNotices()
        }
    }
    @Published var endAlertMode: EndAlertMode = .untilNoticed {
        didSet {
            guard !loading else {return}
            defaults.set(endAlertMode.rawValue, forKey: Self.endModeKey)
            if endAlertMode == .untilNoticed {endAlarm.requestAuthorization()}
            scheduleNotices()
        }
    }
    @Published var alarmSound: AlarmSound = .chime {
        didSet {
            guard !loading else {return}
            defaults.set(alarmSound.rawValue, forKey: Self.alarmSoundKey)
            scheduleNotices()
        }
    }
    @Published private(set) var alarmAcknowledged = false
    @Published var startMinute: Int = 9*60 { didSet { normalizeMinutes(changed:.start) } }
    @Published var endMinute: Int = 18*60 { didSet { normalizeMinutes(changed:.end) } }
    static let storageKey = "focus-timer-daily-v1"
    static let intervalKey = "focus-timer-reminder-interval"
    static let endModeKey = "focus-timer-end-mode"
    static let alarmSoundKey = "focus-timer-alarm-sound"
    private enum MinuteChange {case start,end}
    private let defaults: UserDefaults
    private let now: () -> Date
    private var normalizingMinutes = false
    private var loading = true
    private let notifications: NotificationScheduling
    private let liveActivity: LiveActivityControlling
    private let endAlarm: EndAlarmScheduling

    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = {Date()}, calendar: Calendar = .current,
         notifications: NotificationScheduling = UserNotificationScheduler(), liveActivity: LiveActivityControlling = ActivityKitController(),
         endAlarm: EndAlarmScheduling? = nil) {
        self.defaults = defaults
        self.now = now
        self.notifications = notifications
        self.liveActivity = liveActivity
        self.endAlarm = endAlarm ?? AlarmKitScheduler(defaults: defaults)
        if let raw = defaults.string(forKey: Self.endModeKey), let mode = EndAlertMode(rawValue: raw) {endAlertMode = mode}
        if let raw = defaults.string(forKey: Self.alarmSoundKey), let sound = AlarmSound(rawValue: raw) {alarmSound = sound}
        if let saved = defaults.object(forKey: Self.intervalKey) as? Int, ReminderPlanner.intervalChoices.contains(saved) {
            reminderIntervalMinutes = saved
        }
        if let data = defaults.data(forKey: Self.storageKey),
           let value = try? JSONDecoder().decode(SavedPlan.self, from: data) {
            let sameDay = calendar.isDate(value.date, inSameDayAs: now())
            goals = sameDay ? value.goals : []
            session = sameDay ? value.session : nil
            normalizingMinutes = true
            startMinute = value.startMinute
            endMinute = value.endMinute
            normalizingMinutes = false
            normalizeMinutes(changed:nil, saveAfter:false)
            if !sameDay { clearNotices() }
            save()
        }
        loading = false
        syncLiveActivity()
    }
    private func save() {
        let data = SavedPlan(date: now(), goals: goals, session: session, startMinute: startMinute, endMinute: endMinute)
        if let encoded = try? JSONEncoder().encode(data) { defaults.set(encoded, forKey: Self.storageKey) }
    }
    private func normalizeMinutes(changed: MinuteChange?, saveAfter: Bool = true) {
        guard !normalizingMinutes else {return}
        normalizingMinutes = true
        startMinute = min(max(startMinute,0),1380)
        endMinute = min(max(endMinute,60),1440)
        if startMinute + 60 > endMinute {
            switch changed {
            case .start:startMinute = max(0,endMinute-60)
            case .end:endMinute = min(1440,startMinute+60)
            case nil:
                endMinute = min(1440,startMinute+60)
                if startMinute + 60 > endMinute {startMinute = max(0,endMinute-60)}
            }
        }
        normalizingMinutes = false
        if saveAfter {save()}
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
    func setStepDone(goal: UUID, step: UUID, done: Bool = true) {
        guard let gi = goals.firstIndex(where: {$0.id == goal}), let si = goals[gi].steps.firstIndex(where: {$0.id == step}) else {return}
        goals[gi].steps[si].done = done
    }
    func start(_ title: String, minutes: Int, goal: UUID? = nil, step: UUID? = nil) {
        guard session == nil, minutes > 0 else { return }
        session = WorkSession(title: title, goalID: goal, stepID: step, originalSeconds: TimeInterval(minutes*60), runStartedAt: now())
        scheduleNotices()
        syncLiveActivity()
    }
    func pause() {
        guard var s = session, !s.paused else { return }
        s.elapsedBeforeRun = s.elapsed(at: now())
        s.runStartedAt = nil
        s.paused = true
        session = s
        clearNotices()
        syncLiveActivity()
    }
    func resume() {
        guard var s = session, s.paused else { return }
        s.runStartedAt = now()
        s.paused = false
        session = s
        scheduleNotices()
        syncLiveActivity()
    }
    func extendFive() {
        guard var s = session else { return }
        s.extensionSeconds += 300
        session = s
        scheduleNotices()
        syncLiveActivity()
    }
    func setCondition(_ text: String) {
        guard var s = session else {return}
        s.finishCondition = text
        session = s
        scheduleNotices()
        syncLiveActivity()
    }
    func setSessionGoal(_ goalID: UUID?) {
        guard var s = session, s.goalID != goalID else {return}
        s.goalID = goalID
        s.stepID = nil
        session = s
        scheduleNotices()
        syncLiveActivity()
    }
    func setLaterNote(_ text: String) {
        guard var s = session else {return}
        s.laterNote = text
        session = s
    }
    func finish(markStepDone: Bool) {
        guard let s = session else {return}
        if markStepDone, let g = s.goalID, let step = s.stepID { setStepDone(goal:g, step:step) }
        clearNotices()
        session = nil
        syncLiveActivity()
    }
    private func syncLiveActivity() {
        guard !loading else {return}
        liveActivity.sync(session.map {LiveActivityContent.make(session: $0, goals: goals, now: now())})
    }
    private func clearNotices() {
        notifications.removePending(ReminderPlanner.allIdentifiers)
        endAlarm.cancel()
    }
    var endRouting: EndRouting {
        switch endAlertMode {
        case .once: return .notification
        case .untilNoticed: return endAlarm.isAvailable ? .systemAlarm : .repeatingNotifications
        }
    }
    func acknowledgeAlarm() {
        guard let s = session, s.remaining(at: now()) <= 0 else {return}
        notifications.removePending(ReminderPlanner.repeatIdentifiers)
        notifications.removeDelivered(["focus-end"] + ReminderPlanner.repeatIdentifiers)
        endAlarm.cancel()
        alarmAcknowledged = true
    }
    func scheduleNotices() {
        guard !loading else {return}
        clearNotices()
        alarmAcknowledged = false
        guard let s = session, !s.paused else { return }
        let remaining = s.remaining(at: now())
        let headline = LiveActivityContent.headline(for: s)
        let routing = endRouting
        let notices = ReminderPlanner.plan(remaining: remaining, intervalMinutes: reminderIntervalMinutes,
                                           headline: headline, goalTitle: LiveActivityContent.goalTitle(for: s, goals: goals),
                                           endSound: alarmSound, endRouting: routing)
        for notice in notices {notifications.add(notice)}
        if routing == .systemAlarm, remaining > 0 {
            endAlarm.schedule(EndAlarmRequest(date: now().addingTimeInterval(remaining), title: headline, soundFile: alarmSound.longFile))
        }
    }
    func requestNotifications() {
        notifications.requestAuthorization()
    }
}
