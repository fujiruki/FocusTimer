import Foundation

enum EndAlertMode: String, CaseIterable, Codable {
    case once
    case untilNoticed

    var label: String {
        switch self {
        case .once: return "1回鳴らす"
        case .untilNoticed: return "気づくまで鳴らす"
        }
    }
}

enum AlarmSound: String, CaseIterable, Codable {
    case chime, bell, marimba, beep, system

    var label: String {
        switch self {
        case .chime: return "チャイム"
        case .bell: return "ベル"
        case .marimba: return "木琴"
        case .beep: return "電子音"
        case .system: return "iPhone標準"
        }
    }

    var shortFile: String? {self == .system ? nil : "alarm_\(rawValue).wav"}
    var longFile: String? {self == .system ? nil : "alarm_\(rawValue)_long.wav"}
}

struct EndAlarmRequest: Equatable {
    let date: Date
    let title: String
    let soundFile: String?
}

protocol EndAlarmScheduling {
    var isAvailable: Bool {get}
    func requestAuthorization()
    func schedule(_ request: EndAlarmRequest)
    func cancel()
}
