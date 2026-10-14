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
        session.finishCondition = "   "
        XCTAssertEqual(LiveActivityContent.make(session:session,goals:[],now:now).headline,"納まり検討")
        session.finishCondition = "断面図を1枚描く"
        XCTAssertEqual(LiveActivityContent.make(session:session,goals:[],now:now).headline,"断面図を1枚描く")
    }

    func testGoalLine() {
        let step = WorkStep(title:"断面図")
        let goal = DayGoal(title:"見積提出",steps:[step])
        let withStep = WorkSession(title:"x",goalID:goal.id,stepID:step.id,originalSeconds:600,runStartedAt:now)
        let goalOnly = WorkSession(title:"x",goalID:goal.id,originalSeconds:600,runStartedAt:now)
        let none = WorkSession(title:"x",originalSeconds:600,runStartedAt:now)
        XCTAssertEqual(LiveActivityContent.make(session:withStep,goals:[goal],now:now).goalLine,"見積提出 → 断面図")
        XCTAssertEqual(LiveActivityContent.make(session:goalOnly,goals:[goal],now:now).goalLine,"見積提出")
        XCTAssertNil(LiveActivityContent.make(session:none,goals:[goal],now:now).goalLine)
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
