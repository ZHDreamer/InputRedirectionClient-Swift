import Combine
import Darwin
import GameController
import InputCore
import XCTest

@testable import InputRedirection

final class ClientTests: XCTestCase {
    @MainActor private func withClient(_ body: (Client) throws -> Void) rethrows {
        let name = "InputRedirectionTests.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: name)!
        let client = Client(preferences: preferences, controllerProvider: { [] })
        defer {
            client.stop()
            preferences.removePersistentDomain(forName: name)
        }
        try body(client)
    }

    @MainActor func testAppleMetadataIgnoresLegacyLabelChoiceAndKeepsMappings() {
        let name = "InputRedirectionMetadataTests.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: name)!
        preferences.set("Nintendo", forKey: "layoutChoice")
        let controller = GCController.withExtendedGamepad()
        ControllerProfileStore(preferences: preferences).save(
            ControllerProfile(mappingOverrides: [.home: .a]),
            for: ControllerProfileStore.key(for: controller))
        controller.extendedGamepad!.buttonA.localizedName = "System Button Name"
        controller.extendedGamepad!.buttonA.sfSymbolsName = "b.circle"
        let client = Client(preferences: preferences, controllerProvider: { [controller] })
        defer {
            client.stop()
            preferences.removePersistentDomain(forName: name)
        }
        XCTAssertEqual(client.sourceLabel(InputSource.a), "System Button Name")
        assertSourceImage(client, InputSource.a, named: "b.circle")
        XCTAssertEqual(
            client.defaultMapping[.a], InputSource.b,
            "Display metadata must not change the brand defaults")
        XCTAssertEqual(client.mapping[.home], InputSource.a)
        controller.extendedGamepad!.buttonA.sfSymbolsName = nil
        client.refresh()
        assertSourceImage(client, .a, named: "a.circle")
        XCTAssertEqual(client.sourceLabel(InputSource.a), "System Button Name")
    }

    func testIdleDoesNotPollOrPublishRepeatedly() async {
        await MainActor.run {
            withClient { client in
                XCTAssertFalse(client.isSendTimerRunning)
                client.sendRate = 250
                XCTAssertFalse(client.isSendTimerRunning)
                var changes = 0
                let subscription = client.objectWillChange.sink { changes += 1 }
                RunLoop.main.run(until: Date().addingTimeInterval(0.15))
                XCTAssertEqual(
                    changes, 0, "Idle must not invalidate the SwiftUI view at the send rate")
                withExtendedLifetime(subscription) {}
            }
        }
    }

    @MainActor func testIdleButtonPreviewUsesEvents() async {
        let name = "InputRedirectionTests.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: name)!
        let controller = GCController.withExtendedGamepad()
        let client = Client(preferences: preferences, controllerProvider: { [controller] })
        defer {
            client.stop()
            preferences.removePersistentDomain(forName: name)
        }
        controller.extendedGamepad!.buttonA.setValue(1)
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertTrue(client.pressedSources.contains(InputSource.a))
        XCTAssertTrue(client.pressed.contains(.b))
        XCTAssertFalse(client.isSendTimerRunning)
        controller.extendedGamepad!.buttonA.setValue(0)
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertTrue(client.pressedSources.isEmpty)
        XCTAssertTrue(client.pressed.isEmpty)
    }

    func testSendingContinuesWithoutRepeatedUIUpdatesAndStopsTimer() async throws {
        try await MainActor.run {
            try withClient { client in
                let receiver = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
                guard receiver >= 0 else {
                    throw XCTSkip("UDP sockets unavailable in this environment")
                }
                defer { Darwin.close(receiver) }
                var endpoint = sockaddr_in()
                endpoint.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
                endpoint.sin_family = sa_family_t(AF_INET)
                endpoint.sin_port = UInt16(4950).bigEndian
                endpoint.sin_addr.s_addr = inet_addr("127.0.0.1")
                let result = withUnsafePointer(to: &endpoint) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        Darwin.bind(receiver, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
                guard result == 0 else {
                    throw XCTSkip(
                        "Loopback UDP port unavailable: \(String(cString: strerror(errno)))")
                }
                _ = fcntl(receiver, F_SETFL, O_NONBLOCK)
                client.address = "127.0.0.1"
                client.start()
                XCTAssertTrue(client.sending)
                XCTAssertTrue(client.isSendTimerRunning)
                var changes = 0
                let subscription = client.objectWillChange.sink { changes += 1 }
                RunLoop.main.run(until: Date().addingTimeInterval(0.1))
                XCTAssertEqual(changes, 0, "Repeated neutral packets must not redraw the UI")
                var buffer = [UInt8](repeating: 0, count: 64)
                var packets = 0
                while Darwin.recv(receiver, &buffer, buffer.count, 0) > 0 { packets += 1 }
                XCTAssertGreaterThan(
                    packets, 1, "The network heartbeat must continue even with unchanged input")
                client.stop()
                XCTAssertFalse(client.isSendTimerRunning)
                client.sendRate = 250
                XCTAssertFalse(client.isSendTimerRunning)
                withExtendedLifetime(subscription) {}
            }
        }
    }
}
