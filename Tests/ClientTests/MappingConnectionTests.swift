import Darwin
import GameController
import InputCore
import XCTest

@testable import InputRedirection

final class MappingConnectionTests: XCTestCase {
    @MainActor func testMappingKeepsConnectionAndSendsNeutralUntilRelease() async throws {
        let name = "MappingConnection.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: name)!
        let controller = GCController.withExtendedGamepad()
        let secondController = GCController.withExtendedGamepad()
        var connections = 0
        let client = Client(
            preferences: preferences, controllerProvider: { [controller, secondController] },
            socketFactory: {
                connections += 1
                return try UDPSocket.make()
            })
        defer {
            client.stop()
            preferences.removePersistentDomain(forName: name)
        }
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
        guard result == 0 else { throw XCTSkip("Loopback UDP port unavailable") }
        _ = fcntl(receiver, F_SETFL, O_NONBLOCK)
        func packets() -> [Data] {
            var buffer = [UInt8](repeating: 0, count: 64)
            var received: [Data] = []
            while true {
                let count = Darwin.recv(receiver, &buffer, buffer.count, 0)
                guard count > 0 else { return received }
                received.append(Data(buffer.prefix(count)))
            }
        }
        func waitForPacket(_ matches: (Data) -> Bool) async throws {
            let deadline = Date().addingTimeInterval(1)
            while Date() < deadline {
                if packets().contains(where: matches) { return }
                try await Task.sleep(nanoseconds: 5_000_000)
            }
            XCTFail("Expected mapping packet did not arrive")
        }
        let neutral = InputFrame().encoded()
        func checkNeutralHeartbeat() async throws {
            try await Task.sleep(nanoseconds: 80_000_000)
            let received = packets()
            XCTAssertGreaterThan(received.count, 1, "The heartbeat must continue while mapping")
            XCTAssertTrue(received.allSatisfy { $0 == neutral })
            XCTAssertTrue(client.sending)
            XCTAssertTrue(client.isSendTimerRunning)
            XCTAssertEqual(connections, 1, "Mapping must retain the existing socket")
            XCTAssertTrue(client.pressed.isEmpty)
        }
        client.address = "127.0.0.1"
        client.start()
        try await waitForPacket { $0 == neutral }
        let gamepad = controller.extendedGamepad!
        gamepad.buttonA.setValue(1)
        try await waitForPacket { $0 != neutral }

        client.beginMapping(.power)
        try await checkNeutralHeartbeat()
        gamepad.buttonB.setValue(1)
        try await checkNeutralHeartbeat()
        XCTAssertNil(client.mappingTarget)
        XCTAssertEqual(client.mapping[.power], .b)
        gamepad.buttonB.setValue(0)
        try await checkNeutralHeartbeat()  // The earlier button A is still held.
        gamepad.buttonA.setValue(0)
        try await waitForPacket { $0 == neutral }
        gamepad.buttonB.setValue(1)
        try await waitForPacket { $0.count == 20 && $0[16] == 2 }
        gamepad.buttonB.setValue(0)
        try await waitForPacket { $0 == neutral }

        client.beginMapping(.circlePad)
        gamepad.rightThumbstick.setValueForXAxis(1, yAxis: 0)
        try await checkNeutralHeartbeat()
        XCTAssertEqual(client.mapping[.circlePad], .rightStick)
        gamepad.rightThumbstick.setValueForXAxis(0, yAxis: 0)
        try await waitForPacket { $0 == neutral }
        gamepad.rightThumbstick.setValueForXAxis(0.25, yAxis: 0)
        try await waitForPacket { $0 != neutral }
        gamepad.rightThumbstick.setValueForXAxis(0, yAxis: 0)
        try await waitForPacket { $0 == neutral }

        client.beginControllerSelection()
        try await checkNeutralHeartbeat()
        secondController.extendedGamepad!.buttonA.setValue(1)
        try await checkNeutralHeartbeat()
        XCTAssertTrue(client.currentController === secondController)
        XCTAssertFalse(client.isSelectingController)
        secondController.extendedGamepad!.buttonA.setValue(0)
        try await waitForPacket { $0 == neutral }
        secondController.extendedGamepad!.buttonA.setValue(1)
        try await waitForPacket { $0 != neutral }
        secondController.extendedGamepad!.buttonA.setValue(0)
        try await waitForPacket { $0 == neutral }
        client.beginControllerSelection()
        client.selectController(controller)
        try await checkNeutralHeartbeat()

        client.beginMapping(.home)
        try await checkNeutralHeartbeat()
        client.cancelMapping()
        gamepad.buttonA.setValue(1)
        try await waitForPacket { $0 != neutral }
        XCTAssertTrue(client.sending)
        XCTAssertEqual(connections, 1)
        client.beginMapping(.home)
        client.stop()
        XCTAssertFalse(client.sending)
        XCTAssertFalse(client.isSendTimerRunning)
        XCTAssertNil(client.mappingTarget)
        gamepad.buttonA.setValue(0)
        client.start()
        gamepad.buttonB.setValue(1)
        try await waitForPacket { $0.count == 20 && $0[16] == 2 }
        XCTAssertEqual(connections, 2)
    }
}
