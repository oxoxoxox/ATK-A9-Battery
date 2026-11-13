import SwiftUI

struct StatusPanelView: View {
    @ObservedObject var model: StatusModel
    let actions: AppActions

    var body: some View {
        VStack(spacing: 8) {
            header
            VStack(spacing: 2) {
                PanelRow(
                    icon: "hand.raised.fill",
                    tint: model.inputMonitoringGranted ? .green : .orange,
                    title: "输入监控",
                    detail: model.inputMonitoringGranted ? "已授权" : "去授权",
                    action: model.inputMonitoringGranted ? nil : actions.requestInputMonitoring
                ) {
                    if model.inputMonitoringGranted {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.green)
                    } else {
                        PanelChevron()
                    }
                }
                PanelRow(
                    icon: "power",
                    tint: .blue,
                    title: "开机启动",
                    action: actions.toggleLaunchAtLogin
                ) {
                    Toggle("", isOn: .constant(model.launchAtLogin))
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .labelsHidden()
                        .allowsHitTesting(false)
                }
                PanelRow(
                    icon: "antenna.radiowaves.left.and.right",
                    tint: .teal,
                    title: "AirBattery 同步",
                    detail: model.nearcastConfigured ? "已启用" : "未配置"
                )
            }
            Divider()
                .padding(.horizontal, 6)
            VStack(spacing: 2) {
                PanelRow(
                    icon: "doc.text.magnifyingglass",
                    tint: .gray,
                    title: "打开日志文件夹",
                    action: actions.openLogFolder
                ) {
                    PanelChevron()
                }
                PanelRow(
                    icon: "info.circle.fill",
                    tint: .indigo,
                    title: "关于 MouseBatteryBridge",
                    action: actions.showAbout
                ) {
                    PanelChevron()
                }
                PanelRow(
                    icon: "xmark.circle.fill",
                    tint: .red,
                    title: "退出",
                    action: actions.quit
                ) {
                    Text("⌘Q")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(10)
        .frame(width: 300)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            BatteryRingView(
                percent: model.reading?.percent,
                isCharging: model.reading?.isCharging == true,
                tone: model.ringTone
            )
            VStack(alignment: .leading, spacing: 5) {
                Text(model.deviceName)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                StatusPill(headline: model.headline)
                Text(model.detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            refreshButton
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
    }

    private var refreshButton: some View {
        Button(action: actions.refresh) {
            ZStack {
                if model.isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .medium))
                }
            }
            .frame(width: 22, height: 22)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .disabled(model.isRefreshing)
        .help("立即刷新")
        .accessibilityLabel("立即刷新")
    }
}

private struct StatusPill: View {
    let headline: StatusHeadline

    var body: some View {
        HStack(spacing: 4) {
            if let symbol = headline.symbol {
                Image(systemName: symbol)
                    .font(.system(size: 9, weight: .bold))
            }
            Text(headline.text)
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(headline.tone.color)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(headline.tone.color.opacity(0.14)))
    }
}
