import SwiftUI

struct SendRateControl: View {
    @Binding private var sendRate: Int
    @State private var draftRate: Int
    @State private var isDragging = false
    @FocusState private var isEditingValue: Bool

    init(sendRate: Binding<Int>) {
        _sendRate = sendRate
        _draftRate = State(initialValue: sendRate.wrappedValue)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Send Rate")
                Spacer()
                HStack(spacing: 4) {
                    TextField("Send rate", value: $draftRate, format: .number.grouping(.never))
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 50)
                        .focused($isEditingValue)
                        .onSubmit { commit() }
                        .accessibilityLabel("Send rate in hertz")
                    Text("Hz")
                }
                .monospacedDigit()
                .foregroundStyle(.secondary)
            }
            .font(.callout)

            Slider(
                value: Binding(
                    get: { Double(draftRate) },
                    set: { draftRate = Int(($0 / 5).rounded()) * 5 }
                ),
                in: 50...250,
                onEditingChanged: { editing in
                    isDragging = editing
                    if editing {
                        isEditingValue = false
                    } else {
                        commit()
                    }
                }
            )
            .labelsHidden()
            .accessibilityLabel("Send rate")
            .accessibilityValue("\(draftRate) hertz")
        }
        .controlSize(.small)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: isEditingValue) { editing in
            if !editing && !isDragging { commit() }
        }
        .onChange(of: sendRate) { value in
            if !isDragging && !isEditingValue { draftRate = value }
        }
    }

    private func commit() {
        draftRate = min(250, max(50, draftRate))
        if sendRate != draftRate { sendRate = draftRate }
    }
}
