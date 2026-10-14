import Foundation
import SwiftUI
#if canImport(AlarmKit)
import AlarmKit
import ActivityKit
#endif

#if canImport(AlarmKit)
@available(iOS 26.0, *)
struct FocusAlarmMetadata: AlarmMetadata {
    init() {}
}
#endif

final class AlarmKitScheduler: EndAlarmScheduling {
    private static let alarmIDKey = "focus-timer-alarm-id"
    private let defaults: UserDefaults
    private var pending: Task<Void, Never>?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var isAvailable: Bool {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            return AlarmManager.shared.authorizationState != .denied
        }
        #endif
        return false
    }

    func requestAuthorization() {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            Task {_ = try? await AlarmManager.shared.requestAuthorization()}
        }
        #endif
    }

    func schedule(_ request: EndAlarmRequest) {
        enqueue {[weak self] in
            await self?.cancelStored()
            await self?.scheduleNow(request)
        }
    }

    func cancel() {
        enqueue {[weak self] in await self?.cancelStored()}
    }

    private func enqueue(_ work: @escaping () async -> Void) {
        let previous = pending
        pending = Task {
            await previous?.value
            await work()
        }
    }

    private func cancelStored() async {
        guard let text = defaults.string(forKey: Self.alarmIDKey), let id = UUID(uuidString: text) else {return}
        defaults.removeObject(forKey: Self.alarmIDKey)
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            try? AlarmManager.shared.stop(id: id)
            try? AlarmManager.shared.cancel(id: id)
        }
        #endif
    }

    private func scheduleNow(_ request: EndAlarmRequest) async {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            let manager = AlarmManager.shared
            if manager.authorizationState == .notDetermined {
                _ = try? await manager.requestAuthorization()
            }
            guard manager.authorizationState == .authorized else {return}
            let stopButton = AlarmButton(text: "止める", textColor: .white, systemImageName: "stop.circle.fill")
            let alert = AlarmPresentation.Alert(title: LocalizedStringResource(stringLiteral: request.title), stopButton: stopButton)
            let attributes = AlarmAttributes<FocusAlarmMetadata>(presentation: AlarmPresentation(alert: alert), tintColor: .teal)
            let sound: ActivityKit.AlertConfiguration.AlertSound = request.soundFile.map {.named($0)} ?? .default
            let configuration = AlarmManager.AlarmConfiguration(
                countdownDuration: nil,
                schedule: .fixed(request.date),
                attributes: attributes,
                sound: sound
            )
            let id = UUID()
            if (try? await manager.schedule(id: id, configuration: configuration)) != nil {
                defaults.set(id.uuidString, forKey: Self.alarmIDKey)
            }
        }
        #endif
    }
}
