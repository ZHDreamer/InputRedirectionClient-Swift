import InputCore
import SwiftUI

struct MappingPanel: View {
    @ObservedObject var client: Client

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                HStack(spacing: 12) {
                    ForEach([InputTarget.l, .zl, .zr, .r], id: \.self) { mappingButton($0) }
                }
                HStack(spacing: 12) {
                    stickPicker(.circlePad)
                    stickPicker(.cStick)
                }
                HStack(alignment: .top, spacing: 12) {
                    diamond("D-Pad", top: .up, left: .left, right: .right, bottom: .down)
                    diamond("Face Buttons", top: .x, left: .y, right: .a, bottom: .b)
                }
                HStack(spacing: 12) {
                    ForEach([InputTarget.home, .power, .start, .select], id: \.self) {
                        mappingButton($0)
                    }
                }
                HStack {
                    Text("Open a menu, then select an input or press it on your controller.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Restore Defaults") { client.restoreDefaults() }
                }
            }.padding(16)
        }
        .onDisappear { client.cancelMapping() }
    }

    private func mappingButton(_ target: InputTarget) -> some View {
        VStack(spacing: 5) {
            Text(target.rawValue).font(.caption).foregroundStyle(.secondary)
            MappingMenu(client: client, target: target)
                .frame(height: 26)
                .accessibilityLabel("Map \(target.rawValue)")
                .help("Choose the controller input for 3DS \(target.rawValue)")
        }
        .frame(maxWidth: .infinity)
    }

    private func stickPicker(_ target: InputTarget) -> some View {
        GroupBox(target.rawValue) {
            MappingMenu(client: client, target: target)
                .frame(height: 26).padding(6)
        }.frame(maxWidth: .infinity)
    }

    private func diamond(
        _ title: String, top: InputTarget, left: InputTarget, right: InputTarget,
        bottom: InputTarget
    ) -> some View {
        GroupBox(title) {
            HStack(spacing: 8) {
                mappingButton(left)
                VStack(spacing: 36) {
                    mappingButton(top)
                    mappingButton(bottom)
                }
                mappingButton(right)
            }.padding(8)
        }.frame(maxWidth: .infinity)
    }
}
