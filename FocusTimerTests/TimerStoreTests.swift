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

    func testStartMinuteStaysBeforeEndMinute() {
        let (defaults,suiteName) = makeDefaults()
        defer {clear(suiteName)}
        let current = makeDate(2026,10,14,9,0)
        let store = TimerStore(defaults:defaults,now:{current},calendar:calendar)

        store.startMinute = store.endMinute
        XCTAssertLessThan(store.startMinute,store.endMinute)

        store.endMinute = store.startMinute
        XCTAssertLessThan(store.startMinute,store.endMinute)
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
