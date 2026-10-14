import Foundation
import ActivityKit

struct FocusActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var headline: String
        var goalLine: String?
        var timerStart: Date
        var timerEnd: Date
        var pausedRemaining: TimeInterval?
    }
}
