import Darwin
import GameController
import InputCore
import XCTest

@testable import InputRedirection

final class PowerTests: XCTestCase {
    @MainActor func testPowerButtonAndControllerMappingsSendAndRelease() async throws {
        let name = "InputRedirectionPowerTests.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: name)!
        preferences.set(["Power (Long)": "B"], forKey: "mappingOverrides")
        let controller = GCController.withExtendedGamepad()
        let client = Client(preferences: preferences, controllerProvider: { [controller] })
        defer {
            client.stop()
            preferences.removePersistentDomain(forName: name)
        }
        client.triggerPower(longPress: true)
        XCTAssertNil(
            client.powerAction, "Idle power clicks must not queue an action for the next connection"
        )
        XCTAssertFalse(client.isSendTimerRunning)
        XCTAssertEqual(client.mapping[.power], InputSource.none)
        XCTAssertNil(InputTarget(rawValue: "Power (Long)"))
        client.mapping[.power] = InputSource.a
        client.save()
        let restored = Client(preferences: preferences, controllerProvider: { [] })
        XCTAssertEqual(restored.mapping[.power], InputSource.a)

        let receiver = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard receiver >= 0 else { throw XCTSkip("UDP sockets unavailable") }
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
            throw XCTSkip("Loopback UDP port unavailable: \(String(cString: strerror(errno)))")
        }
        _ = fcntl(receiver, F_SETFL, O_NONBLOCK)
        func flags() -> [UInt32] {
            var buffer = [UInt8](repeating: 0, count: 64)
            var result: [UInt32] = []
            while Darwin.recv(receiver, &buffer, buffer.count, 0) > 0 {
                result.append(
                    (0..<4).reduce(UInt32(0)) { $0 | UInt32(buffer[16 + $1]) << ($1 * 8) })
            }
            return result
        }
        client.address = "127.0.0.1"
        client.start()
        XCTAssertTrue(client.sending)
        _ = flags()
        for longPress in [false, true] {
            client.triggerPower(longPress: longPress)
            let expected: UInt32 = longPress ? 4 : 2
            var received = flags()
            let deadline = Date().addingTimeInterval(1)
            while !received.contains(expected) && Date() < deadline {
                try await Task.sleep(nanoseconds: 5_000_000)
                received.append(contentsOf: flags())
            }
            XCTAssertTrue(received.contains(expected))
            try await Task.sleep(nanoseconds: 220_000_000)
            XCTAssertNil(client.powerAction)
            XCTAssertEqual(flags().last, 0, "The UI action must release automatically")
        }
        let gamepad = controller.extendedGamepad!
        for (button, expected) in [(gamepad.buttonA, UInt32(2)), (gamepad.buttonB, UInt32(0))] {
            button.setValue(1)
            try await Task.sleep(nanoseconds: 50_000_000)
            XCTAssertTrue(flags().contains(expected))
            button.setValue(0)
            try await Task.sleep(nanoseconds: 50_000_000)
            XCTAssertEqual(flags().last, 0)
        }
        client.triggerPower(longPress: true)
        client.stop()
        XCTAssertNil(client.powerAction)
        XCTAssertFalse(client.isSendTimerRunning)
        XCTAssertEqual(flags().last, 0)
        client.restoreDefaults()
        XCTAssertEqual(client.mapping[.power], InputSource.none)
    }
}
