import AppKit
import Charts
import Combine
import ClavimoQuartz
import SwiftUI

struct DiagnosticsPane: View {
    @Bindable var model: AgentController
    @State private var statistics: EventTapController.Statistics?
    @State private var inspecting = false
    @State private var events: [EventTapController.InspectedEvent] = []
    @State private var copied = false
    private let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                Card {
                    VStack(alignment: .leading, spacing: Spacing.m) {
                        SectionHeader(title: String(localized: "Input connection"),
                                      subtitle: String(localized: "How Clavimo's connection to keyboard and mouse input is doing."))
                        Grid(alignment: .leading, horizontalSpacing: Spacing.xl, verticalSpacing: Spacing.s) {
                            row(String(localized: "Status"), model.status.title)
                            row(String(localized: "Events handled"), statistics.map { "\($0.eventsSeen)" } ?? "–")
                            row(String(localized: "Interruptions by macOS"),
                                statistics.map { "\($0.tapDisabledByTimeout + $0.tapDisabledByUserInput)" } ?? "–")
                            row(String(localized: "Automatic recoveries"), statistics.map { "\($0.tapReenabled)" } ?? "–")
                            if let available = statistics?.deviceAttributionAvailable {
                                row(String(localized: "Device recognition"),
                                    available ? String(localized: "Available") : String(localized: "Unavailable (Input Monitoring needed)"))
                            }
                        }
                        if !model.isTapRunning {
                            Text(String(localized: "Turn remapping on to collect measurements.")).font(.callout).foregroundStyle(.secondary)
                        }
                    }
                }

                Card {
                    VStack(alignment: .leading, spacing: Spacing.m) {
                        SectionHeader(title: String(localized: "Processing time"),
                                      subtitle: String(localized: "Time Clavimo adds to each event, measured on this Mac. It does not include USB, Bluetooth or display latency."))
                        if let points = latencyPoints, !points.isEmpty {
                            Chart(points) { point in
                                BarMark(x: .value(String(localized: "Percentile"), point.percentile),
                                        y: .value(String(localized: "Microseconds"), point.microseconds))
                                    .foregroundStyle(by: .value(String(localized: "Events"), point.category))
                                    .position(by: .value(String(localized: "Events"), point.category))
                                    .annotation(position: .top) {
                                        Text(point.microseconds.formatted(.number.precision(.fractionLength(0...1))))
                                            .font(.caption2).foregroundStyle(.secondary)
                                    }
                            }
                            .chartForegroundStyleScale([String(localized: "Unchanged"): Brand.mint, String(localized: "Changed"): Brand.violet])
                            .chartYAxisLabel(String(localized: "µs"))
                            .frame(height: 180)
                        } else {
                            Text(String(localized: "No measurements yet.")).foregroundStyle(.secondary)
                        }
                    }
                }

                Card {
                    VStack(alignment: .leading, spacing: Spacing.m) {
                        HStack(alignment: .top) {
                            SectionHeader(title: String(localized: "Input inspector"),
                                          subtitle: String(localized: "Shows the last keys and buttons and what Clavimo did with them. Kept in memory only and cleared when you leave this page."))
                            Spacer()
                            Toggle(String(localized: "Inspect input"), isOn: $inspecting)
                                .toggleStyle(.switch)
                                .labelsHidden()
                                .accessibilityLabel(String(localized: "Inspect input"))
                                .disabled(!model.isTapRunning)
                        }
                        if inspecting {
                            if events.isEmpty {
                                Text(String(localized: "Press a key or a mouse button.")).foregroundStyle(.secondary)
                            } else {
                                VStack(alignment: .leading, spacing: 4) {
                                    ForEach(Array(events.reversed().enumerated()), id: \.offset) { _, event in
                                        InspectorRow(event: event)
                                    }
                                }
                            }
                        }
                    }
                }

                HStack {
                    Button(copied ? String(localized: "Copied") : String(localized: "Copy Diagnostic Report")) { copyReport() }
                    Text(String(localized: "The report contains versions, settings and measurements, never what you typed."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(Spacing.xl)
        }
        .navigationTitle(String(localized: "Diagnostics"))
        .onAppear(perform: refresh)
        .onReceive(timer) { _ in refresh() }
        .onChange(of: inspecting) { model.setInspectorEnabled(inspecting); events = [] }
        .onDisappear {
            inspecting = false
            model.setInspectorEnabled(false)
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        GridRow {
            Text(title).foregroundStyle(.secondary)
            Text(value).monospacedDigit()
        }
    }

    private func refresh() {
        _ = model.statistics { stats in
            Task { @MainActor in statistics = stats }
        }
        if inspecting {
            model.inspectedEvents { list in
                Task { @MainActor in events = list }
            }
        }
    }

    private struct LatencyPoint: Identifiable {
        let category: String
        let percentile: String
        let microseconds: Double
        var id: String { category + percentile }
    }

    private var latencyPoints: [LatencyPoint]? {
        guard let statistics else { return nil }
        var points: [LatencyPoint] = []
        for (category, summary) in [(String(localized: "Unchanged"), statistics.passThrough), (String(localized: "Changed"), statistics.handled)] {
            guard let summary else { continue }
            points += [("p50", summary.p50), ("p95", summary.p95), ("p99", summary.p99)].map {
                LatencyPoint(category: category, percentile: $0.0, microseconds: Double($0.1) / 1000)
            }
        }
        return points
    }

    private func copyReport() {
        let info = Bundle.main.infoDictionary
        var lines = [
            "Clavimo \(info?["CFBundleShortVersionString"] as? String ?? "dev") (\(info?["CFBundleVersion"] as? String ?? "-"))",
            "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)",
            "Architecture: \(Self.architecture)",
            "Status: \(model.status.title)",
            "Permissions: accessibility=\(model.permissions.accessibilityTrusted) inputMonitoring=\(model.permissions.listenEventAccess)",
            "Other input tools: \(model.otherRemapper ?? "none")",
            "Pointer acceleration: \(SystemChecks.pointerAccelerationEnabled ? "on" : "off")",
            "Disabled Mission Control shortcuts: \(SystemChecks.disabledShortcuts().map(\.title).joined(separator: ", "))",
            "Rules that cannot run: \(model.unsupported.count)",
        ]
        if let statistics {
            lines.append("Events: \(statistics.eventsSeen), interruptions: \(statistics.tapDisabledByTimeout)/\(statistics.tapDisabledByUserInput), recoveries: \(statistics.tapReenabled)")
            for (name, summary) in [("unchanged", statistics.passThrough), ("changed", statistics.handled)] {
                if let summary {
                    lines.append("Latency \(name): p50 \(summary.p50) ns, p95 \(summary.p95) ns, p99 \(summary.p99) ns, max \(summary.max) ns, n \(summary.count)")
                }
            }
        }
        lines.append("Devices: " + HIDDeviceCatalog.connectedDevices().map { "\($0.name) [\($0.id)] \($0.transport ?? "")" }.joined(separator: "; "))
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
        copied = true
    }

    private static var architecture: String {
        #if arch(arm64)
        "arm64"
        #else
        "x86_64"
        #endif
    }
}

private struct InspectorRow: View {
    let event: EventTapController.InspectedEvent

    var body: some View {
        HStack(spacing: Spacing.s) {
            Image(systemName: event.isDown ? "arrow.down.circle" : "arrow.up.circle")
                .foregroundStyle(.secondary)
                .accessibilityLabel(event.isDown ? String(localized: "Pressed") : String(localized: "Released"))
            switch event.kind {
            case .mouse:
                MouseButtonToken(title: KeyNames.shortButtonName(Int(event.code)))
            case .scroll:
                MouseButtonToken(title: String(localized: "Wheel"))
            case .key, .modifier:
                let cap = KeyNames.keyCap(for: event.code)
                KeyCap(label: cap.label, caption: cap.caption)
            }
            Spacer()
            StatusChip(text: outcomeText, kind: outcomeKind)
            Text("\((Double(event.callbackNanoseconds) / 1000).formatted(.number.precision(.fractionLength(1)))) µs")
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 70, alignment: .trailing)
        }
    }

    private var outcomeText: String {
        switch event.outcome {
        case .unchanged: String(localized: "Unchanged")
        case .changed: String(localized: "Changed")
        case .consumed: String(localized: "Held back")
        case .action: String(localized: "Ran action")
        }
    }

    private var outcomeKind: StatusChip.Kind {
        switch event.outcome {
        case .unchanged: .off
        case .changed: .beta
        case .consumed: .paused
        case .action: .active
        }
    }
}
