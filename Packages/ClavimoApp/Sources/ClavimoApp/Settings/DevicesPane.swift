import AppKit
import ClavimoQuartz
import SwiftUI

struct DevicesPane: View {
    let navigation: SettingsNavigation
    @State private var devices: [HIDDeviceInfo] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                HStack(alignment: .top) {
                    SectionHeader(title: String(localized: "Connected devices"),
                                  subtitle: String(localized: "Rules can be limited to one of these devices."))
                    Spacer()
                    Button { refresh() } label: { Label(String(localized: "Refresh"), systemImage: "arrow.clockwise") }
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: Spacing.m, alignment: .top)], spacing: Spacing.m) {
                    ForEach(devices) { device in DeviceCard(device: device, navigation: navigation) }
                }
                WarningCard(symbol: "flask", color: Brand.violet,
                            title: String(localized: "How device rules work"),
                            message: String(localized: "macOS does not say which device a key press came from. When a rule is limited to a device, Clavimo asks the connected devices which one is holding the key. If two devices report it, or none does, the rule does not apply. Two devices of the same model share an ID."))
            }
            .padding(Spacing.xl)
        }
        .navigationTitle(String(localized: "Devices"))
        .onAppear(perform: refresh)
    }

    private func refresh() {
        devices = HIDDeviceCatalog.connectedDevices()
        for device in devices { DeviceNames.cache[device.id.description] = device.name }
    }
}

private struct DeviceCard: View {
    let device: HIDDeviceInfo
    let navigation: SettingsNavigation

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.s) {
                HStack(spacing: Spacing.m) {
                    Image(systemName: isMouse ? "computermouse" : device.isPointer ? "keyboard.badge.ellipsis" : "keyboard")
                        .font(.title2)
                        .foregroundStyle(isMouse ? Brand.mint : Brand.violet)
                        .frame(width: 32)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(device.name).font(.headline).lineLimit(2)
                        Text(kinds).font(.caption).foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: Spacing.s) {
                    StatusChip(text: connection, kind: .info)
                    Text(device.id.description).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                    Spacer()
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(device.id.description, forType: .string)
                    } label: { Image(systemName: "doc.on.doc") }
                    .buttonStyle(.borderless)
                    .help(String(localized: "Copy device ID"))
                    .accessibilityLabel(String(localized: "Copy device ID"))
                }
                if device.isKeyboard && !isMouse {
                    Button(String(localized: "Create a Rule for This Keyboard")) {
                        var draft = RuleDraft()
                        draft.devices = [device.id.description]
                        navigation.createRule(draft)
                    }
                    .buttonStyle(.link)
                }
            }
        }
    }

    private var isMouse: Bool { device.looksLikeMouse }

    private var kinds: String {
        if isMouse { return String(localized: "Mouse") }
        return [device.isKeyboard ? String(localized: "Keyboard") : nil, device.isPointer ? String(localized: "Pointing device") : nil]
            .compactMap { $0 }.joined(separator: ", ")
    }

    private var connection: String {
        switch device.transport?.lowercased() {
        case "usb": "USB"
        case "bluetooth", "bluetooth low energy": "Bluetooth"
        case "spi", "fifo": String(localized: "Built-in")
        case let other?: other.uppercased()
        case nil: String(localized: "Unknown")
        }
    }
}
