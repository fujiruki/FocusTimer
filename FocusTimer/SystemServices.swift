import Foundation
import UserNotifications
import ActivityKit

protocol NotificationScheduling {
    func removePending(_ identifiers: [String])
    func removeDelivered(_ identifiers: [String])
    func add(_ notice: PlannedNotice)
    func requestAuthorization()
}

protocol LiveActivityControlling {
    func sync(_ state: FocusActivityAttributes.ContentState?)
}

struct UserNotificationScheduler: NotificationScheduling {
    func removePending(_ identifiers: [String]) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
    }
    func removeDelivered(_ identifiers: [String]) {
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: identifiers)
    }
    func add(_ notice: PlannedNotice) {
        let content = UNMutableNotificationContent()
        content.title = notice.title
        content.body = notice.body
        content.sound = notice.sound.map {UNNotificationSound(named: UNNotificationSoundName($0))} ?? .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, notice.offset), repeats: false)
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: notice.identifier, content: content, trigger: trigger))
    }
    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert,.sound,.badge]) { _,_ in }
    }
}

final class ForegroundNotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = ForegroundNotificationPresenter()

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }
}

final class ActivityKitController: LiveActivityControlling {
    private var pending: Task<Void, Never>?

    func sync(_ state: FocusActivityAttributes.ContentState?) {
        let previous = pending
        pending = Task {
            await previous?.value
            await Self.apply(state)
        }
    }

    private static func apply(_ state: FocusActivityAttributes.ContentState?) async {
        let activities = Activity<FocusActivityAttributes>.activities
        guard let state else {
            for activity in activities {await activity.end(nil, dismissalPolicy: .immediate)}
            return
        }
        let content = ActivityContent(state: state, staleDate: state.pausedRemaining == nil ? state.timerEnd : nil)
        if let first = activities.first {
            await first.update(content)
            for extra in activities.dropFirst() {await extra.end(nil, dismissalPolicy: .immediate)}
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {return}
        _ = try? Activity.request(attributes: FocusActivityAttributes(), content: content, pushType: nil)
    }
}
