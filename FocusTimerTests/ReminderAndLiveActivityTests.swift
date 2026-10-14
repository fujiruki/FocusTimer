import XCTest
@testable import FocusTimer

final class ReminderPlannerTests: XCTestCase {
    func testThirtyMinutesWithTenMinuteInterval() {
        let notices = ReminderPlanner.plan(remaining:1800,intervalMinutes:10,headline:"図面3枚",goalTitle:"見積提出")
        XCTAssertEqual(notices.map(\.identifier),["focus-mid-1","focus-mid-2","focus-last","focus-end"])
        XCTAssertEqual(notices.map(\.offset),[600,1200,1500,1800])
        XCTAssertEqual(notices[0].title,"図面3枚")
        XCTAssertEqual(notices[0].body,"残り20分／今日のゴール：見積提出")
        XCTAssertEqual(notices[1].body,"残り10分／今日のゴール：見積提出")
        XCTAssertEqual(notices[2].title,"残り5分")
        XCTAssertEqual(notices[2].body,"図面3枚")
        XCTAssertEqual(notices[3].title,"設定時間になりました")
        XCTAssertEqual(notices[3].body,"図面3枚")
    }

    func testIntervalOffKeepsLastAndEnd() {
        let notices = ReminderPlanner.plan(remaining:1800,intervalMinutes:0,headline:"A",goalTitle:nil)
        XCTAssertEqual(notices.map(\.identifier),["focus-last","focus-end"])
    }

    func testShortSessionHasOnlyEnd() {
        let notices = ReminderPlanner.plan(remaining:240,intervalMinutes:5,headline:"A",goalTitle:nil)
        XCTAssertEqual(notices.map(\.identifier),["focus-end"])
        XCTAssertEqual(notices[0].offset,240)
    }

    func testMidNoticeOverlappingLastIsSkipped() {
        let notices = ReminderPlanner.plan(remaining:900,intervalMinutes:10,headline:"A",goalTitle:nil)
        XCTAssertEqual(notices.map(\.identifier),["focus-last","focus-end"])
        XCTAssertEqual(notices.map(\.offset),[600,900])
    }

    func testMidNoticesAreCapped() {
        let notices = ReminderPlanner.plan(remaining:36000,intervalMinutes:5,headline:"A",goalTitle:nil)
        XCTAssertEqual(notices.filter {$0.identifier.hasPrefix("focus-mid-")}.count,ReminderPlanner.maxMidNotices)
        XCTAssertEqual(notices.last?.identifier,"focus-end")
        XCTAssertTrue(Set(notices.map(\.identifier)).isSubset(of:Set(ReminderPlanner.allIdentifiers)))
    }

    func testNoRemainingPlansNothing() {
        XCTAssertTrue(ReminderPlanner.plan(remaining:0,intervalMinutes:10,headline:"A",goalTitle:nil).isEmpty)
        XCTAssertTrue(ReminderPlanner.plan(remaining:-60,intervalMinutes:10,headline:"A",goalTitle:nil).isEmpty)
    }

    func testBodyWithoutGoal() {
        let notices = ReminderPlanner.plan(remaining:1500,intervalMinutes:5,headline:"A",goalTitle:nil)
        XCTAssertEqual(notices[0].body,"残り20分")
    }
}

final class LiveActivityContentTests: XCTestCase {
    private let now = Date(timeIntervalSince1970:1_800_000_000)

    func testHeadlineFallsBackToTitle() {
        var session = WorkSession(title:"納まり検討",originalSeconds:1800,runStartedAt:now)
        XCTAssertEqual(LiveActivityContent.make(session:session,goals:[],now:now).headline,"納まり検討")
        XCTAssertFalse(LiveActivityContent.make(session:session,goals:[],now:now).headlineIsCondition)
        session.finishCondition = "   "
        XCTAssertEqual(LiveActivityContent.make(session:session,goals:[],now:now).headline,"納まり検討")
        XCTAssertFalse(LiveActivityContent.make(session:session,goals:[],now:now).headlineIsCondition)
        session.finishCondition = "断面図を1枚描く"
        XCTAssertEqual(LiveActivityContent.make(session:session,goals:[],now:now).headline,"断面図を1枚描く")
        XCTAssertTrue(LiveActivityContent.make(session:session,goals:[],now:now).headlineIsCondition)
    }

    func testGoalLine() {
        let step = WorkStep(title:"断面図")
        let goal = DayGoal(title:"見積提出",steps:[step])
        let withStep = WorkSession(title:"x",goalID:goal.id,stepID:step.id,originalSeconds:600,runStartedAt:now)
        let goalOnly = WorkSession(title:"x",goalID:goal.id,originalSeconds:600,runStartedAt:now)
        let none = WorkSession(title:"x",originalSeconds:600,runStartedAt:now)
        let stepState = LiveActivityContent.make(session:withStep,goals:[goal],now:now)
        XCTAssertEqual(stepState.goalTitle,"見積提出")
        XCTAssertEqual(stepState.stepTitle,"断面図")
        let goalState = LiveActivityContent.make(session:goalOnly,goals:[goal],now:now)
        XCTAssertEqual(goalState.goalTitle,"見積提出")
        XCTAssertNil(goalState.stepTitle)
        let noneState = LiveActivityContent.make(session:none,goals:[goal],now:now)
        XCTAssertNil(noneState.goalTitle)
        XCTAssertNil(noneState.stepTitle)
        XCTAssertEqual(LiveActivityContent.goalLine(for:withStep,goals:[goal]),"見積提出 → 断面図")
    }

    func testRunningTimerRange() {
        let session = WorkSession(title:"x",originalSeconds:1800,extensionSeconds:300,runStartedAt:now.addingTimeInterval(-600))
        let state = LiveActivityContent.make(session:session,goals:[],now:now)
        XCTAssertEqual(state.timerEnd,now.addingTimeInterval(1500))
        XCTAssertEqual(state.timerStart,now.addingTimeInterval(-600))
        XCTAssertNil(state.pausedRemaining)
    }

    func testPausedHasRemaining() {
        let session = WorkSession(title:"x",originalSeconds:1800,elapsedBeforeRun:600,runStartedAt:nil,paused:true)
        let state = LiveActivityContent.make(session:session,goals:[],now:now)
        XCTAssertEqual(state.pausedRemaining,1200)
        XCTAssertEqual(state.timerEnd,now.addingTimeInterval(1200))
    }
}

private final class FakeNotifications: NotificationScheduling {
    var pending: [PlannedNotice] = []
    func removePending(_ identifiers: [String]) {pending.removeAll {identifiers.contains($0.identifier)}}
    func removeDelivered(_ identifiers: [String]) {}
    func add(_ notice: PlannedNotice) {pending.append(notice)}
    func requestAuthorization() {}
}

private final class FakeLiveActivity: LiveActivityControlling {
    var states: [FocusActivityAttributes.ContentState?] = []
    func sync(_ state: FocusActivityAttributes.ContentState?) {states.append(state)}
}

@MainActor
final class TimerStoreIntegrationTests: XCTestCase {
    private var current = Date(timeIntervalSince1970:1_800_000_000)
    private var suiteName = ""
    private var defaults: UserDefaults!
    private var notifications: FakeNotifications!
    private var live: FakeLiveActivity!

    override func setUp() {
        suiteName = "FocusTimerIntegration-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName:suiteName)!
        notifications = FakeNotifications()
        live = FakeLiveActivity()
    }
    override func tearDown() {
        defaults.removePersistentDomain(forName:suiteName)
    }
    private func makeStore() -> TimerStore {
        TimerStore(defaults:defaults,now:{[unowned self] in current},calendar:Calendar(identifier:.gregorian),notifications:notifications,liveActivity:live)
    }

    func testStartSchedulesAndStartsLiveActivity() {
        let store = makeStore()
        XCTAssertEqual(store.reminderIntervalMinutes,10)
        XCTAssertEqual(live.states.count,1)
        XCTAssertNil(live.states.last!)
        store.start("作業",minutes:30)
        XCTAssertEqual(notifications.pending.map(\.identifier),["focus-mid-1","focus-mid-2","focus-last","focus-end"])
        XCTAssertEqual(live.states.last??.headline,"作業")
    }

    func testPauseClearsAndShowsPausedState() {
        let store = makeStore()
        store.start("作業",minutes:30)
        current = current.addingTimeInterval(600)
        store.pause()
        XCTAssertTrue(notifications.pending.isEmpty)
        XCTAssertEqual(live.states.last??.pausedRemaining,1200)
        store.resume()
        XCTAssertEqual(notifications.pending.last?.offset,1200)
        XCTAssertNil(live.states.last??.pausedRemaining)
    }

    func testFinishEndsLiveActivity() {
        let store = makeStore()
        store.start("作業",minutes:30)
        store.finish(markStepDone:false)
        XCTAssertTrue(notifications.pending.isEmpty)
        XCTAssertNil(live.states.last!)
    }

    func testConditionUpdatesHeadlineAndNotices() {
        let store = makeStore()
        store.start("作業",minutes:30)
        store.setCondition("断面図を1枚")
        XCTAssertEqual(live.states.last??.headline,"断面図を1枚")
        XCTAssertEqual(notifications.pending.first?.title,"断面図を1枚")
    }

    func testIntervalChangeReschedulesAndPersists() {
        let store = makeStore()
        store.start("作業",minutes:30)
        store.reminderIntervalMinutes = 0
        XCTAssertEqual(notifications.pending.map(\.identifier),["focus-last","focus-end"])
        XCTAssertEqual(defaults.integer(forKey:TimerStore.intervalKey),0)
        store.reminderIntervalMinutes = 7
        XCTAssertEqual(store.reminderIntervalMinutes,10)
        XCTAssertEqual(makeStore().reminderIntervalMinutes,10)
        store.reminderIntervalMinutes = 15
        XCTAssertEqual(makeStore().reminderIntervalMinutes,15)
    }

    func testIntervalSurvivesDayChange() throws {
        defaults.set(5,forKey:TimerStore.intervalKey)
        let yesterday = current.addingTimeInterval(-86400)
        let saved = SavedPlan(date:yesterday,goals:[DayGoal(title:"old")],session:nil,startMinute:540,endMinute:1080)
        defaults.set(try JSONEncoder().encode(saved),forKey:TimerStore.storageKey)
        let store = makeStore()
        XCTAssertTrue(store.goals.isEmpty)
        XCTAssertEqual(store.reminderIntervalMinutes,5)
    }

    func testRestoredSessionSyncsLiveActivityOnLaunch() throws {
        let saved = SavedPlan(date:current,goals:[],session:WorkSession(title:"続き",originalSeconds:1800,runStartedAt:current),startMinute:540,endMinute:1080)
        defaults.set(try JSONEncoder().encode(saved),forKey:TimerStore.storageKey)
        _ = makeStore()
        XCTAssertEqual(live.states.count,1)
        XCTAssertEqual(live.states.last??.headline,"続き")
    }
}

@MainActor
final class SessionGoalAndBuildInfoTests: XCTestCase {
    func testSetSessionGoalLinksGoalAndClearsStep() {
        let suite = "FocusTimerGoal-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName:suite)!
        defer {defaults.removePersistentDomain(forName:suite)}
        let live = FakeLiveActivity()
        let notifications = FakeNotifications()
        let now = Date(timeIntervalSince1970:1_800_000_000)
        let store = TimerStore(defaults:defaults,now:{now},notifications:notifications,liveActivity:live)
        store.addGoal("見積提出")
        store.addGoal("自宅に帰る")
        store.start("片付け",minutes:30)
        XCTAssertNil(live.states.last??.goalTitle)

        store.setSessionGoal(store.goals[1].id)

        XCTAssertEqual(store.session?.goalID,store.goals[1].id)
        XCTAssertNil(store.session?.stepID)
        XCTAssertEqual(live.states.last??.goalTitle,"自宅に帰る")
        XCTAssertEqual(notifications.pending.first?.body,"残り20分／今日のゴール：自宅に帰る")
    }

    func testBuildInfoRecentWithinFiveMinutes() {
        let built = Date(timeIntervalSince1970:1_800_000_000)
        let info = BuildInfo(info:["CFBundleVersion":"12","FTBuildCommit":"abc1234","FTBuildTime":"2027-01-15T08:00:00Z"])
        XCTAssertEqual(info.builtAt,built)
        XCTAssertTrue(info.isRecent(at:built.addingTimeInterval(300)))
        XCTAssertFalse(info.isRecent(at:built.addingTimeInterval(301)))
        XCTAssertEqual(info.label(timeZone:TimeZone(identifier:"Asia/Tokyo")!),"ビルド #12（abc1234）　最終更新 1/15 17:00")
    }

    func testBuildInfoWithoutTime() {
        let info = BuildInfo(info:["CFBundleVersion":"1","FTBuildCommit":"local","FTBuildTime":""])
        XCTAssertNil(info.builtAt)
        XCTAssertFalse(info.isRecent(at:Date()))
        XCTAssertEqual(info.label(),"ビルド #1（local）")
    }
}

private final class FakeEndAlarm: EndAlarmScheduling {
    var isAvailable: Bool
    var scheduled: [EndAlarmRequest] = []
    var cancelCount = 0
    var authorizationRequests = 0
    init(available: Bool) {isAvailable = available}
    func requestAuthorization() {authorizationRequests += 1}
    func schedule(_ request: EndAlarmRequest) {scheduled.append(request)}
    func cancel() {cancelCount += 1}
}

final class EndRoutingPlannerTests: XCTestCase {
    func testOnceUsesShortSelectedSound() {
        let notices = ReminderPlanner.plan(remaining:600,intervalMinutes:0,headline:"A",goalTitle:nil,endSound:.bell,endRouting:.notification)
        XCTAssertEqual(notices.map(\.identifier),["focus-last","focus-end"])
        XCTAssertEqual(notices[0].sound,"focus_chime.wav")
        XCTAssertEqual(notices[1].sound,"alarm_bell.wav")
    }

    func testRepeatingAddsTwentyFollowUpsEveryThirtySeconds() {
        let notices = ReminderPlanner.plan(remaining:600,intervalMinutes:0,headline:"A",goalTitle:nil,endSound:.marimba,endRouting:.repeatingNotifications)
        let repeats = notices.filter {$0.identifier.hasPrefix("focus-end-r")}
        XCTAssertEqual(repeats.count,20)
        XCTAssertEqual(repeats.first?.offset,630)
        XCTAssertEqual(repeats.last?.offset,1200)
        XCTAssertTrue(notices.filter {$0.identifier.hasPrefix("focus-end")}.allSatisfy {$0.sound == "alarm_marimba_long.wav"})
        XCTAssertTrue(Set(notices.map(\.identifier)).isSubset(of:Set(ReminderPlanner.allIdentifiers)))
    }

    func testSystemAlarmOmitsEndNotification() {
        let notices = ReminderPlanner.plan(remaining:600,intervalMinutes:0,headline:"A",goalTitle:nil,endRouting:.systemAlarm)
        XCTAssertEqual(notices.map(\.identifier),["focus-last"])
    }

    func testSystemSoundUsesDefault() {
        let notices = ReminderPlanner.plan(remaining:600,intervalMinutes:0,headline:"A",goalTitle:nil,endSound:.system)
        XCTAssertNil(notices.last?.sound)
    }

    func testPendingLimitStaysWithinSixtyFour() {
        let notices = ReminderPlanner.plan(remaining:36000,intervalMinutes:5,headline:"A",goalTitle:nil,endRouting:.repeatingNotifications)
        XCTAssertLessThanOrEqual(notices.count,64)
    }
}

@MainActor
final class EndAlarmStoreTests: XCTestCase {
    private let now = Date(timeIntervalSince1970:1_800_000_000)

    private func makeStore(_ defaults: UserDefaults, _ notifications: FakeNotifications, _ alarm: FakeEndAlarm, at date: Date? = nil) -> TimerStore {
        let fixed = date ?? now
        return TimerStore(defaults:defaults,now:{fixed},notifications:notifications,liveActivity:FakeLiveActivity(),endAlarm:alarm)
    }
    private func withDefaults(_ body: (UserDefaults) throws -> Void) rethrows {
        let suite = "FocusTimerAlarm-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName:suite)!
        defer {defaults.removePersistentDomain(forName:suite)}
        try body(defaults)
    }

    func testUntilNoticedUsesSystemAlarmWhenAvailable() {
        withDefaults {defaults in
            let notifications = FakeNotifications()
            let alarm = FakeEndAlarm(available:true)
            let store = makeStore(defaults,notifications,alarm)
            store.alarmSound = .bell
            store.endAlertMode = .untilNoticed
            XCTAssertEqual(alarm.authorizationRequests,1)
            store.start("作業",minutes:30)
            XCTAssertEqual(alarm.scheduled.last,EndAlarmRequest(date:now.addingTimeInterval(1800),title:"作業",soundFile:"alarm_bell_long.wav"))
            XCTAssertFalse(notifications.pending.contains {$0.identifier.hasPrefix("focus-end")})
            let cancelsBeforePause = alarm.cancelCount
            store.pause()
            XCTAssertGreaterThan(alarm.cancelCount,cancelsBeforePause)
        }
    }

    func testUntilNoticedFallsBackToRepeatingNotifications() {
        withDefaults {defaults in
            let notifications = FakeNotifications()
            let alarm = FakeEndAlarm(available:false)
            let store = makeStore(defaults,notifications,alarm)
            store.endAlertMode = .untilNoticed
            store.start("作業",minutes:30)
            XCTAssertTrue(alarm.scheduled.isEmpty)
            XCTAssertEqual(notifications.pending.filter {$0.identifier.hasPrefix("focus-end-r")}.count,20)
        }
    }

    func testAcknowledgeAfterTimeUpRemovesRepeats() throws {
        try withDefaults {defaults in
            let notifications = FakeNotifications()
            let alarm = FakeEndAlarm(available:false)
            let store = makeStore(defaults,notifications,alarm)
            store.endAlertMode = .untilNoticed
            store.start("作業",minutes:30)
            let later = makeStore(defaults,notifications,alarm,at:now.addingTimeInterval(1900))
            XCTAssertNotNil(later.session)
            XCTAssertFalse(later.alarmAcknowledged)
            later.acknowledgeAlarm()
            XCTAssertFalse(notifications.pending.contains {$0.identifier.hasPrefix("focus-end-r")})
            XCTAssertTrue(later.alarmAcknowledged)
        }
    }

    func testAcknowledgeBeforeTimeUpKeepsSchedule() {
        withDefaults {defaults in
            let notifications = FakeNotifications()
            let alarm = FakeEndAlarm(available:false)
            let store = makeStore(defaults,notifications,alarm)
            store.endAlertMode = .untilNoticed
            store.start("作業",minutes:30)
            store.acknowledgeAlarm()
            XCTAssertEqual(notifications.pending.filter {$0.identifier.hasPrefix("focus-end-r")}.count,20)
        }
    }

    func testSettingsPersist() {
        withDefaults {defaults in
            let store = makeStore(defaults,FakeNotifications(),FakeEndAlarm(available:true))
            store.endAlertMode = .untilNoticed
            store.alarmSound = .beep
            let reloaded = makeStore(defaults,FakeNotifications(),FakeEndAlarm(available:true))
            XCTAssertEqual(reloaded.endAlertMode,.untilNoticed)
            XCTAssertEqual(reloaded.alarmSound,.beep)
        }
    }
}
