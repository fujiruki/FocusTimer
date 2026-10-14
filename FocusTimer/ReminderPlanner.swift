import Foundation

struct PlannedNotice: Equatable {
    let identifier: String
    let offset: TimeInterval
    let title: String
    let body: String
}

enum ReminderPlanner {
    static let maxMidNotices = 40
    static let intervalChoices = [0,5,10,15]
    static let defaultInterval = 10
    static var allIdentifiers: [String] {
        (1...maxMidNotices).map {"focus-mid-\($0)"} + ["focus-last","focus-end","focus-half"]
    }

    static func plan(remaining: TimeInterval, intervalMinutes: Int, headline: String, goalTitle: String?) -> [PlannedNotice] {
        guard remaining > 0 else {return []}
        var notices: [PlannedNotice] = []
        let lastOffset: TimeInterval? = remaining > 300 ? remaining - 300 : nil
        let anchors = [lastOffset, remaining].compactMap {$0}
        if intervalMinutes > 0 {
            let step = TimeInterval(intervalMinutes * 60)
            var k = 1
            while notices.count < maxMidNotices {
                let offset = step * TimeInterval(k)
                guard offset < remaining else {break}
                k += 1
                if anchors.contains(where: {abs($0 - offset) <= 60}) {continue}
                let minutes = Int(((remaining - offset) / 60).rounded(.up))
                var body = "残り\(minutes)分"
                if let goalTitle, !goalTitle.isEmpty {body += "／今日のゴール：\(goalTitle)"}
                notices.append(PlannedNotice(identifier: "focus-mid-\(notices.count + 1)", offset: offset, title: headline, body: body))
            }
        }
        if let lastOffset {
            notices.append(PlannedNotice(identifier: "focus-last", offset: lastOffset, title: "残り5分", body: headline))
        }
        notices.append(PlannedNotice(identifier: "focus-end", offset: remaining, title: "設定時間になりました", body: headline))
        return notices
    }
}
