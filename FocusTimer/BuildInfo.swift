import Foundation

struct BuildInfo {
    static let recentWindow: TimeInterval = 300
    let number: String
    let commit: String
    let builtAt: Date?

    static let current = BuildInfo(info: Bundle.main.infoDictionary ?? [:])

    init(number: String, commit: String, builtAt: Date?) {
        self.number = number
        self.commit = commit
        self.builtAt = builtAt
    }

    init(info: [String: Any]) {
        number = info["CFBundleVersion"] as? String ?? "?"
        commit = info["FTBuildCommit"] as? String ?? "?"
        builtAt = (info["FTBuildTime"] as? String).flatMap {ISO8601DateFormatter().date(from: $0)}
    }

    func isRecent(at now: Date) -> Bool {
        guard let builtAt else {return false}
        return abs(now.timeIntervalSince(builtAt)) <= Self.recentWindow
    }

    func label(timeZone: TimeZone = .current) -> String {
        var text = "ビルド #\(number)（\(commit)）"
        if let builtAt {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "ja_JP")
            formatter.timeZone = timeZone
            formatter.dateFormat = "M/d HH:mm"
            text += "　最終更新 \(formatter.string(from: builtAt))"
        }
        return text
    }
}
