import InputCore
import SwiftUI

struct ContentView: View {
    @ObservedObject var client: Client
    @State private var showingMapping = false

    var body: some View {
        inputPage
            .background {
                GeometryReader { geometry in
                    Color.clear
                        .sheet(isPresented: $showingMapping) {
                            if #available(macOS 15.0, *) {
                                MappingPanel(
                                    client: client,
                                    maximumHeight: geometry.size.height - 48,
                                )
                                .presentationSizing(.fitted)
                            } else {
                                MappingPanel(
                                    client: client,
                                    maximumHeight: geometry.size.height - 48,
                                )
                            }
                        }
                }
            }
            .alert(
                "Unable to Identify Controller",
                isPresented: Binding(
                    get: { client.identificationError != nil },
                    set: { if !$0 { client.identificationError = nil } }
                )
            ) {
                Button("OK", role: .cancel) { client.identificationError = nil }
            } message: {
                Text(client.identificationError ?? "")
            }
    }

    private var inputPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 12) {
                Text("3DS Network").font(.headline)
                GroupBox {
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
                        SendRateControl(sendRate: $client.sendRate)
                        Text(client.status).font(.callout).textSelection(.enabled)
                    }.padding(6)
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                Text("Controller").font(.headline)
                HStack {
                    ControllerMenu(client: client)
                        .frame(maxWidth: .infinity)
                        .frame(height: 26)
                    Button {
                        showingMapping = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .help("Button Mapping")
                    .accessibilityLabel("Button Mapping")
                    Button("Identify") { client.identifyController() }
                        .disabled(!client.canIdentifyController)
                        .help(
                            client.canIdentifyController
                                ? "Vibrate the selected controller"
                                : "The selected controller does not support vibration")
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                Text("Touch Screen").font(.headline)
                HStack(alignment: .top, spacing: 24) {
                    TouchSurface(client: client).frame(width: 320, height: 240)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 14) {
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
                        ScrollView(.horizontal) {
                            HStack(spacing: 8) {
                                if output.isEmpty { Text("—") }
                                ForEach(output, id: \.self) { target in
                                    TargetButtonLabel(target: target)
                                }
                            }
                        }.frame(height: 24)
                        HStack(spacing: 10) {
                            Button(InputTarget.home.rawValue) { client.triggerHome() }
                                .disabled(!client.sending || client.home)
                            Button(InputTarget.power.rawValue) {
                                client.triggerPower(longPress: false)
                            }
                            .disabled(!client.sending || client.powerAction != nil)
                            Button("Power (Long)") { client.triggerPower(longPress: true) }
                                .disabled(!client.sending || client.powerAction != nil)
                        }
                    }
                }
            }
        }
        .padding(24)
    }
}
