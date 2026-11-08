import InputCore
import SwiftUI

struct ContentView: View {
    @ObservedObject var client: Client
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Image(systemName: "gamecontroller.fill").font(.largeTitle).foregroundStyle(.tint)
                VStack(alignment: .leading) {
                    Text("Input Redirection").font(.title.bold())
                    Text("macOS → Nintendo 3DS").foregroundStyle(.secondary)
                }
                Spacer()
                Text(client.sending ? "Sending" : "Idle").font(.caption.bold())
                    .padding(8).background(
                        client.sending ? Color.green.opacity(0.15) : Color.gray.opacity(0.15),
                        in: Capsule())
            }
            GroupBox("3DS Network") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        TextField("3DS IPv4 address", text: $client.address).textFieldStyle(
                            .roundedBorder
                        ).disabled(client.sending)
                        Button(client.sending ? "Stop" : "Start Sending") {
                            client.sending ? client.stop() : client.start()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    Text(client.status).font(.callout).textSelection(.enabled)
                    Text("UDP has no connection acknowledgment. Verify input on your 3DS.").font(
                        .caption
                    ).foregroundStyle(.secondary)
                }.padding(6)
            }
            HStack {
                Picker("Controller", selection: $client.selected) {
                    if client.controllers.isEmpty {
                        Text("Connect a controller via Bluetooth or USB").tag(0)
                    }
                    ForEach(Array(client.controllers.enumerated()), id: \.offset) {
                        index, controller in
                        Text("\(controller.vendorName ?? "Game Controller") #\(index + 1)").tag(
                            index)
                    }
                }
                Button {
                    client.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }.help("Refresh controllers")
            }
            TabView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Touch Screen · 320 × 240").font(.headline)
                    HStack(alignment: .top, spacing: 24) {
                        TouchSurface(client: client).frame(width: 320, height: 240)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        VStack(alignment: .leading, spacing: 14) {
                            Text(
                                "Click and drag to use the stylus.\nNo 3DS video is displayed here."
                            ).foregroundStyle(.secondary)
                            Text("Controller Input").font(.headline)
                            ScrollView(.horizontal) {
                                HStack(spacing: 8) {
                                    if client.pressedSources.isEmpty { Text("—") }
                                    ForEach(
                                        InputSource.allCases.filter {
                                            client.pressedSources.contains($0)
                                        }, id: \.self
                                    ) { source in
                                        ControllerButtonLabel(client: client, source: source)
                                    }
                                }
                            }.frame(height: 24)
                            Text("3DS Output").font(.headline)
                            let output = InputTarget.allCases.filter { client.pressed.contains($0) }
                                .map(\.rawValue).joined(separator: " · ")
                            Text(output.isEmpty ? "—" : output)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            HStack(spacing: 10) {
                                Button(InputTarget.home.rawValue) { client.triggerHome() }
                                    .help("Send a HOME press")
                                    .disabled(!client.sending || client.home)
                                Button(InputTarget.power.rawValue) {
                                    client.triggerPower(longPress: false)
                                }
                                .help("Send a power press")
                                .disabled(!client.sending || client.powerAction != nil)
                                Button("Power (Long)") { client.triggerPower(longPress: true) }
                                    .help("Send a long power press")
                                    .disabled(!client.sending || client.powerAction != nil)
                            }
                        }
                    }
                }.padding().tabItem { Label("Input", systemImage: "hand.draw") }
                MappingPanel(client: client)
                    .tabItem { Label("Button Mapping", systemImage: "switch.2") }
                Form {
                    HStack {
                        Text("Send Rate")
                        Spacer()
                        Text("\(client.sendRate) Hz").monospacedDigit()
                    }
                    Slider(
                        value: Binding(
                            get: { Double(client.sendRate) },
                            set: { client.sendRate = Int($0.rounded()) }
                        ), in: 50...250, step: 1
                    ) {
                        Text("Send Rate")
                    } minimumValueLabel: {
                        Text("50 Hz")
                    } maximumValueLabel: {
                        Text("250 Hz")
                    }
                    Text("Changes apply immediately and are saved automatically.")
                        .font(.caption).foregroundStyle(.secondary)
                    Toggle("Invert Y axis for both sticks", isOn: $client.invertY)
                    Text(
                        "Choose stick assignments in Button Mapping.\nZL / ZR and C-Stick require a New 3DS."
                    ).foregroundStyle(.secondary)
                }.padding().tabItem { Label("Settings", systemImage: "slider.horizontal.3") }
            }
            Text(
                "Enable InputRedirection in Rosalina → Miscellaneous options. Connect your Mac and 3DS to the same LAN."
            )
            .font(.caption).foregroundStyle(.secondary)
        }.padding(24).frame(minWidth: 720, minHeight: 620)
            .onChange(of: client.invertY) { _ in client.save() }
    }
}
