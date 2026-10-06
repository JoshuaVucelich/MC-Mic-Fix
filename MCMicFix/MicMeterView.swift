import SwiftUI

struct MicMeterView: View {
    @Bindable var meter: MicLevelMeter

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(meter.isRunning ? "Listening…" : "Mic unavailable")
                .font(.caption)
                .foregroundStyle(.secondary)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.2))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.accentColor)
                        .frame(width: max(4, geo.size.width * CGFloat(meter.level)))
                }
            }
            .frame(height: 12)
        }
    }
}
