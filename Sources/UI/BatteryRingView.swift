import SwiftUI

struct BatteryRingView: View {
    let percent: Int?
    let isCharging: Bool
    let tone: StatusTone

    private var fraction: Double {
        Double(min(max(percent ?? 0, 0), 100)) / 100
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.08), lineWidth: 6)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(tone.color.gradient, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.6), value: fraction)
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(percent.map { "\($0)" } ?? "--")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                if percent != nil {
                    Text("%")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: 68, height: 68)
        .overlay(alignment: .bottom) {
            if isCharging {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(3)
                    .background(Circle().fill(StatusTone.good.color.gradient))
                    .offset(y: 4)
            }
        }
    }
}
