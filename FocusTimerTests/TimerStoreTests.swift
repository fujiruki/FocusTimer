import XCTest
@testable import FocusTimer

@MainActor
final class TimerStoreTests: XCTestCase {
    func testFinishMarkStepDoneKeepsCompletedStepDone() {
        let (defaults,suiteName) = makeDefaults()
        defer {clear(suiteName)}
        let current = makeDate(2026,10,14,9,0)
        let goalID = UUID()
        let stepID = UUID()
        let store = TimerStore(defaults:defaults,now:{current},calendar:calendar)
        store.goals = [DayGoal(id:goalID,title:"Goal",steps:[WorkStep(id:stepID,title:"Step",done:true)])]
        store.session = WorkSession(title:"Step",goalID:goalID,stepID:stepID,originalSeconds:600,runStartedAt:current)

        store.finish(markStepDone:true)

        XCTAssertNil(store.session)
        XCTAssertEqual(store.goals[0].steps[0].done,true)
    }

    func testStartAndEndMinutesKeepAtLeastOneHourApart() {
        let (defaults,suiteName) = makeDefaults()
        defer {clear(suiteName)}
        let current = makeDate(2026,10,14,9,0)
        let store = TimerStore(defaults:defaults,now:{current},calendar:calendar)

        store.startMinute = store.endMinute
        XCTAssertGreaterThanOrEqual(store.endMinute - store.startMinute,60)
        XCTAssertGreaterThanOrEqual(store.startMinute,0)
        XCTAssertLessThanOrEqual(store.startMinute,1380)
        XCTAssertGreaterThanOrEqual(store.endMinute,60)
        XCTAssertLessThanOrEqual(store.endMinute,1440)

        store.endMinute = store.startMinute
        XCTAssertGreaterThanOrEqual(store.endMinute - store.startMinute,60)
        XCTAssertGreaterThanOrEqual(store.startMinute,0)
        XCTAssertLessThanOrEqual(store.startMinute,1380)
        XCTAssertGreaterThanOrEqual(store.endMinute,60)
        XCTAssertLessThanOrEqual(store.endMinute,1440)
    }

    func testStartAndEndMinutesClampToHomeViewBounds() {
        let (defaults,suiteName) = makeDefaults()
        defer {clear(suiteName)}
        let current = makeDate(2026,10,14,9,0)
        let store = TimerStore(defaults:defaults,now:{current},calendar:calendar)

        store.endMinute = 1440
        store.startMinute = 24*60
        XCTAssertEqual(store.startMinute,1380)
        XCTAssertEqual(store.endMinute,1440)

        store.startMinute = 0
        store.endMinute = 0
        XCTAssertEqual(store.startMinute,0)
        XCTAssertEqual(store.endMinute,60)
        XCTAssertGreaterThanOrEqual(store.endMinute - store.startMinute,60)
        XCTAssertGreaterThanOrEqual(store.startMinute,0)
        XCTAssertLessThanOrEqual(store.startMinute,1380)
        XCTAssertGreaterThanOrEqual(store.endMinute,60)
        XCTAssertLessThanOrEqual(store.endMinute,1440)
    }

    func testLoadingEqualStartAndEndMinutesExpandsToOneHour() throws {
        let (defaults,suiteName) = makeDefaults()
        defer {clear(suiteName)}
        let current = makeDate(2026,10,14,9,0)
        let saved = SavedPlan(
            date:current,
            goals:[],
            session:nil,
            startMinute:18*60,
            endMinute:18*60
        )
        defaults.set(try JSONEncoder().encode(saved),forKey:TimerStore.storageKey)

        let store = TimerStore(defaults:defaults,now:{current},calendar:calendar)

        XCTAssertEqual(store.startMinute,18*60)
        XCTAssertEqual(store.endMinute,19*60)
        XCTAssertEqual(store.endMinute - store.startMinute,60)
    }

    func testLoadingPreviousDayClearsGoalsAndSession() throws {
        let (defaults,suiteName) = makeDefaults()
        defer {clear(suiteName)}
        let today = makeDate(2026,10,14,9,0)
        let yesterday = makeDate(2026,10,13,22,0)
        let saved = SavedPlan(
            date:yesterday,
            goals:[DayGoal(title:"Old goal")],
            session:WorkSession(title:"Old session",goalID:nil,stepID:nil,originalSeconds:900,runStartedAt:yesterday),
            startMinute:8*60,
            endMinute:17*60
        )
        defaults.set(try JSONEncoder().encode(saved),forKey:TimerStore.storageKey)

        let store = TimerStore(defaults:defaults,now:{today},calendar:calendar)

        XCTAssertTrue(store.goals.isEmpty)
        XCTAssertNil(store.session)
        XCTAssertEqual(store.startMinute,8*60)
        XCTAssertEqual(store.endMinute,17*60)
    }

    func testPauseResumeAndExtendFiveCalculateElapsedAndRemainingTime() {
        let (defaults,suiteName) = makeDefaults()
        defer {clear(suiteName)}
        var current = makeDate(2026,10,14,9,0)
        let store = TimerStore(defaults:defaults,now:{current},calendar:calendar)

        store.start("Deep work",minutes:30)
        current = current.addingTimeInterval(600)
        XCTAssertEqual(store.session!.elapsed(at:current),600,accuracy:0.001)

        store.pause()
        XCTAssertEqual(store.session!.elapsedBeforeRun,600,accuracy:0.001)
        XCTAssertTrue(store.session!.paused)

        current = current.addingTimeInterval(600)
        XCTAssertEqual(store.session!.elapsed(at:current),600,accuracy:0.001)

        store.resume()
        current = current.addingTimeInterval(300)
        XCTAssertEqual(store.session!.elapsed(at:current),900,accuracy:0.001)
        XCTAssertEqual(store.session!.remaining(at:current),900,accuracy:0.001)

        store.extendFive()
        XCTAssertEqual(store.session!.extensionSeconds,300,accuracy:0.001)
        XCTAssertEqual(store.session!.remaining(at:current),1200,accuracy:0.001)
    }

    private var calendar: Calendar {
        var value = Calendar(identifier:.gregorian)
        value.timeZone = TimeZone(secondsFromGMT:0)!
        return value
    }
    private func makeDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        calendar.date(from:DateComponents(timeZone:calendar.timeZone,year:year,month:month,day:day,hour:hour,minute:minute))!
    }
    private func makeDefaults() -> (UserDefaults,String) {
        let name = "FocusTimerTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName:name)!
        defaults.removePersistentDomain(forName:name)
        return (defaults,name)
    }
    private func clear(_ suiteName: String) {
        UserDefaults(suiteName:suiteName)?.removePersistentDomain(forName:suiteName)
    }
}
