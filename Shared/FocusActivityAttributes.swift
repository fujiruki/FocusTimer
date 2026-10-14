import Foundation
import ActivityKit

struct FocusActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var headline: String
        var headlineIsCondition: Bool
        var goalTitle: String?
        var stepTitle: String?
        var timerStart: Date
        var timerEnd: Date
        var pausedRemaining: TimeInterval?
    }
}
