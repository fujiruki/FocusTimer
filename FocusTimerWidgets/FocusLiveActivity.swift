import ActivityKit
import SwiftUI
import WidgetKit

@main
struct FocusTimerWidgetsBundle: WidgetBundle {
    var body: some Widget {
        FocusLiveActivityWidget()
    }
}

struct FocusLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FocusActivityAttributes.self) { context in
            FocusActivityView(state: context.state)
                .activityBackgroundTint(Color.black.opacity(0.75))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.headline).font(.headline).lineLimit(2)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    RemainingText(state: context.state).font(.title3.bold())
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if let line = context.state.goalLine {
                        Text(line).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            } compactLeading: {
                Text(context.state.headline).font(.caption2).lineLimit(1).frame(maxWidth: 90)
            } compactTrailing: {
                RemainingText(state: context.state, compact: true).font(.caption2).frame(width: 44)
            } minimal: {
                RemainingText(state: context.state, compact: true).font(.caption2).frame(width: 40)
            }
        }
        .supplementalActivityFamilies([.small, .medium])
    }
}

struct FocusActivityView: View {
    @Environment(\.activityFamily) private var family
    let state: FocusActivityAttributes.ContentState

    var body: some View {
        if family == .small {
            VStack(alignment: .leading, spacing: 2) {
                Text(state.headline).font(.headline).lineLimit(2)
                RemainingText(state: state).font(.title3.bold())
            }
            .padding(8)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top) {
                    Text(state.headline).font(.headline).lineLimit(2)
                    Spacer(minLength: 8)
                    RemainingText(state: state).font(.title2.bold())
                }
                if let line = state.goalLine {
                    Text(line).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                if state.pausedRemaining == nil {
                    ProgressView(timerInterval: state.timerRange, countsDown: false, label: {EmptyView()}, currentValueLabel: {EmptyView()})
                        .tint(.teal)
                }
            }
            .padding()
            .foregroundStyle(.white)
        }
    }
}

struct RemainingText: View {
    let state: FocusActivityAttributes.ContentState
    var compact = false

    var body: some View {
        if let paused = state.pausedRemaining {
            Text(compact ? Self.format(paused) : "中断中 \(Self.format(paused))").monospacedDigit()
        } else {
            Text(timerInterval: state.timerRange, countsDown: true).monospacedDigit().multilineTextAlignment(.trailing)
        }
    }

    static func format(_ seconds: TimeInterval) -> String {
        let value = Int(max(0, seconds).rounded(.up))
        return String(format: "%02d:%02d", value / 60, value % 60)
    }
}

extension FocusActivityAttributes.ContentState {
    var timerRange: ClosedRange<Date> {
        min(timerStart, timerEnd)...timerEnd
    }
}
