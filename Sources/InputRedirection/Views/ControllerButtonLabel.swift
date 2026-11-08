import AppKit
import InputCore
import SwiftUI

struct ControllerButtonLabel: View {
    @ObservedObject var client: Client
    let source: InputSource

    var body: some View {
        let name = client.sourceLabel(source)
        if let image = client.sourceImage(source) {
            Image(nsImage: image)
                .accessibilityLabel(Text(name))
                .help(name)
        } else {
            Text(
                name
                    + (client.currentController != nil && !client.sourceIsAvailable(source)
                        ? " (Unavailable)" : ""))
        }
    }
}

struct TargetButtonLabel: View {
    let target: InputTarget

    var body: some View {
        Group {
            if let symbol = target.defaultSymbol {
                Image(systemName: symbol)
            } else {
                Text(target.rawValue)
                    .font(.system(size: 9, weight: .medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .overlay(Capsule().strokeBorder(lineWidth: 1))
            }
        }
        .accessibilityLabel(target.rawValue)
        .help(target.rawValue)
    }
}
