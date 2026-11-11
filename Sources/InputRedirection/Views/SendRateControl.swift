import SwiftUI

struct SendRateControl: View {
    @Binding private var sendRate: Int
    @FocusState.Binding private var focusedField: InputFieldFocus?
    @State private var draftRate: Int
    @State private var rateText: String
    @State private var isDragging = false

    init(
        sendRate: Binding<Int>,
        focusedField: FocusState<InputFieldFocus?>.Binding
    ) {
        _sendRate = sendRate
        _focusedField = focusedField
        _draftRate = State(initialValue: sendRate.wrappedValue)
        _rateText = State(initialValue: String(sendRate.wrappedValue))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Send Rate")
                Spacer()
                HStack(spacing: 4) {
                    TextField("", text: $rateText)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 50)
                        .focused($focusedField, equals: .sendRate)
                        .onChange(of: rateText) { text in
                            let digits = text.filter { $0 >= "0" && $0 <= "9" }
                            if text != digits { rateText = digits }
                            if let value = Int(digits) { draftRate = value }
                        }
                        .onSubmit { commit() }
                        .accessibilityLabel("Send rate in hertz")
                    Text("Hz")
                }
                .monospacedDigit()
                .foregroundStyle(.primary)
            }
            .font(.callout)

            Slider(
                value: Binding(
                    get: { Double(draftRate) },
                    set: {
                        draftRate = Int(($0 / 5).rounded()) * 5
                        rateText = String(draftRate)
                    }
                ),
                in: 50...250,
                onEditingChanged: { editing in
                    isDragging = editing
                    if editing {
                        focusedField = nil
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
        .onChange(of: focusedField) { field in
            if field != .sendRate && !isDragging { commit() }
        }
        .onChange(of: sendRate) { value in
            if !isDragging && focusedField != .sendRate {
                draftRate = value
                rateText = String(value)
            }
        }
    }

    private func commit() {
        draftRate = min(250, max(50, draftRate))
        rateText = String(draftRate)
        if sendRate != draftRate { sendRate = draftRate }
    }
}
