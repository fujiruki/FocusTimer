import Foundation

enum LiveActivityContent {
    static func condition(for session: WorkSession) -> String {
        session.finishCondition.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func headline(for session: WorkSession) -> String {
        let condition = condition(for: session)
        return condition.isEmpty ? session.title : condition
    }

    static func goalLine(for session: WorkSession, goals: [DayGoal]) -> String? {
        guard let goalID = session.goalID, let goal = goals.first(where: {$0.id == goalID}) else {return nil}
        if let stepID = session.stepID, let step = goal.steps.first(where: {$0.id == stepID}) {
            return "\(goal.title) → \(step.title)"
        }
        return goal.title
    }

    static func goalTitle(for session: WorkSession, goals: [DayGoal]) -> String? {
        guard let goalID = session.goalID else {return nil}
        return goals.first(where: {$0.id == goalID})?.title
    }

    static func stepTitle(for session: WorkSession, goals: [DayGoal]) -> String? {
        guard let goalID = session.goalID, let stepID = session.stepID else {return nil}
        return goals.first(where: {$0.id == goalID})?.steps.first(where: {$0.id == stepID})?.title
    }

    static func make(session: WorkSession, goals: [DayGoal], now: Date) -> FocusActivityAttributes.ContentState {
        let remaining = session.remaining(at: now)
        let end = now.addingTimeInterval(remaining)
        return FocusActivityAttributes.ContentState(
            headline: headline(for: session),
            headlineIsCondition: !condition(for: session).isEmpty,
            goalTitle: goalTitle(for: session, goals: goals),
            stepTitle: stepTitle(for: session, goals: goals),
            timerStart: end.addingTimeInterval(-(session.originalSeconds + session.extensionSeconds)),
            timerEnd: end,
            pausedRemaining: session.paused ? max(0, remaining) : nil
        )
    }
}
