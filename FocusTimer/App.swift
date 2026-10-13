import SwiftUI

@main
struct FocusTimerApp: App {
    @StateObject private var store = TimerStore()
    var body: some Scene {
        WindowGroup {
            HomeView().environmentObject(store)
        }
    }
}
