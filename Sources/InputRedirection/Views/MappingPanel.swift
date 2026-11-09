import InputCore
import SwiftUI

struct MappingPanel: View {
    @ObservedObject var client: Client

    let maximumHeight: CGFloat
    @Environment(\.dismiss) private var dismiss
    @State private var contentHeight: CGFloat?

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if #available(macOS 14.0, *) {
                    mappingScrollView.contentMargins(.top, 16, for: .scrollIndicators)
                } else {
                    mappingScrollView
                }
            }
            .frame(height: min(contentHeight ?? maximumHeight, max(0, maximumHeight - 53)))
            Divider().frame(height: 1)
            HStack {
                Button("Restore Defaults") { client.restoreDefaults() }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16)
            .frame(height: 52)
        }
        .frame(width: 640)
        .onPreferenceChange(MappingContentHeightKey.self) { contentHeight = $0 }
        .onDisappear { client.cancelMapping() }
    }

    private var mappingScrollView: some View {
        ScrollView {
            controls
                .background {
                    GeometryReader { geometry in
                        Color.clear.preference(
                            key: MappingContentHeightKey.self, value: geometry.size.height)
                    }
                }
        }
    }

    private var controls: some View {
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
            }
        }
        .padding(16)
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
        GroupBox {
            MappingMenu(client: client, target: target)
                .frame(height: 26).padding(6)
        } label: {
            Text(target.rawValue)
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

private struct MappingContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
