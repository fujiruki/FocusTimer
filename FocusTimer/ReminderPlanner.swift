import Foundation

struct PlannedNotice: Equatable {
    let identifier: String
    let offset: TimeInterval
    let title: String
    let body: String
    var sound: String? = ReminderPlanner.chimeFile
}

enum EndRouting: Equatable {
    case notification
    case repeatingNotifications
    case systemAlarm
}

enum ReminderPlanner {
    static let maxMidNotices = 40
    static let intervalChoices = [0,5,10,15]
    static let defaultInterval = 10
    static let chimeFile = "focus_chime.wav"
    static let repeatCount = 20
    static let repeatSpacing: TimeInterval = 30
    static var repeatIdentifiers: [String] {
        (1...repeatCount).map {"focus-end-r\($0)"}
    }
    static var allIdentifiers: [String] {
        (1...maxMidNotices).map {"focus-mid-\($0)"} + ["focus-last","focus-end","focus-half"] + repeatIdentifiers
    }

    static func plan(remaining: TimeInterval, intervalMinutes: Int, headline: String, goalTitle: String?,
                     endSound: AlarmSound = .chime, endRouting: EndRouting = .notification) -> [PlannedNotice] {
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
        switch endRouting {
        case .notification:
            notices.append(PlannedNotice(identifier: "focus-end", offset: remaining, title: "設定時間になりました", body: headline, sound: endSound.shortFile))
        case .repeatingNotifications:
            notices.append(PlannedNotice(identifier: "focus-end", offset: remaining, title: "設定時間になりました", body: headline, sound: endSound.longFile))
            for (index, identifier) in repeatIdentifiers.enumerated() {
                let offset = remaining + repeatSpacing * TimeInterval(index + 1)
                notices.append(PlannedNotice(identifier: identifier, offset: offset, title: "設定時間になりました", body: "アプリを開くと止まります／\(headline)", sound: endSound.longFile))
            }
        case .systemAlarm:
            break
        }
        return notices
    }
}
