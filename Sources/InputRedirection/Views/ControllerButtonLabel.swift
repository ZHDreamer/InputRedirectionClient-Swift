import AppKit
import InputCore
import SwiftUI

struct ControllerButtonLabel: View {
    @ObservedObject var client: Client
    let source: InputSource

    var body: some View {
        let name = client.sourceLabel(source)
        if let symbol = client.sourceSymbol(source),
            NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil
        {
            Image(systemName: symbol)
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
