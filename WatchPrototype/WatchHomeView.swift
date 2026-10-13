// watchOS targetをXcode上で作成した場合のUI試作。
// iPhoneとの同期・通知は未実装。iOSのターゲットには含めていません。
import SwiftUI

struct WatchHomeView: View {
    @State private var minutes = 30
    @State private var started: Date?
    @State private var pausedElapsed: TimeInterval = 0
    @State private var running = false
    var body: some View {
        TimelineView(.periodic(from:.now,by:1)) {timeline in
            let elapsed = pausedElapsed + (running ? max(0,timeline.date.timeIntervalSince(started ?? timeline.date)) : 0)
            VStack(spacing:8) {
                Text("今の作業").font(.caption)
                Text("図面作成").font(.headline)
                Text(String(format:"%02d:%02d",max(0,Int(Double(minutes*60)-elapsed))/60,max(0,Int(Double(minutes*60)-elapsed))%60)).font(.title2.monospacedDigit())
                ProgressView(value:min(1,elapsed/Double(minutes*60)))
                HStack {
                    Button(running ? "中断" : "開始") {
                        if running {pausedElapsed=elapsed;running=false}
                        else {started = .now;running=true}
                    }
                    Button("+5分") {minutes += 5}
                }.font(.caption2)
            }.padding(6)
        }
    }
}
