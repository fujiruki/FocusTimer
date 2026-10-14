import SwiftUI
import UserNotifications

@main
struct FocusTimerApp: App {
    @StateObject private var store = TimerStore()
    init() {
        UNUserNotificationCenter.current().delegate = ForegroundNotificationPresenter.shared
    }
    var body: some Scene {
        WindowGroup {
            HomeView().environmentObject(store)
        }
    }
}
