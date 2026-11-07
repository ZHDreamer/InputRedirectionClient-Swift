import XCTest
import GameController
import Darwin
@testable import InputRedirection

final class HomeTests: XCTestCase {
    @MainActor func testHomeClickReleasesAndPreservesControllerHold() async throws {
        let name = "InputRedirectionHomeTests.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: name)!
        let controller = GCController.withExtendedGamepad()
        let client = Client(preferences: preferences, controllerProvider: { [controller] })
        defer { client.stop(); preferences.removePersistentDomain(forName: name) }
        client.triggerHome()
        XCTAssertFalse(client.home)
        XCTAssertFalse(client.isSendTimerRunning)
        client.mapping["Home"] = "South"
        client.sendRate = 50
        let receiver = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard receiver >= 0 else { throw XCTSkip("UDP sockets unavailable") }
        defer { Darwin.close(receiver) }
        var endpoint = sockaddr_in()
        endpoint.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        endpoint.sin_family = sa_family_t(AF_INET)
        endpoint.sin_port = UInt16(4950).bigEndian
        endpoint.sin_addr.s_addr = inet_addr("127.0.0.1")
        let result = withUnsafePointer(to: &endpoint) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(receiver, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard result == 0 else { throw XCTSkip("Loopback UDP port unavailable: \(String(cString: strerror(errno)))") }
        _ = fcntl(receiver, F_SETFL, O_NONBLOCK)
        func flags() -> [UInt32] {
            var buffer = [UInt8](repeating: 0, count: 64)
            var result: [UInt32] = []
            while Darwin.recv(receiver, &buffer, buffer.count, 0) > 0 {
                result.append((0..<4).reduce(UInt32(0)) { $0 | UInt32(buffer[16 + $1]) << ($1 * 8) })
            }
            return result
        }
        func waitForFlag(_ expected: UInt32) async throws {
            let deadline = Date().addingTimeInterval(1)
            while Date() < deadline {
                if flags().contains(expected) { return }
                try await Task.sleep(nanoseconds: 5_000_000)
            }
            XCTFail("Did not receive HOME flags \(expected)")
        }
        client.address = "127.0.0.1"
        client.start()
        XCTAssertTrue(client.sending)
        try await waitForFlag(0)
        for _ in 0..<2 {
            client.triggerHome()
            XCTAssertTrue(client.home)
            try await waitForFlag(1)
            try await waitForFlag(0)
            XCTAssertFalse(client.home)
        }

        controller.extendedGamepad!.buttonA.setValue(1)
        try await waitForFlag(1)
        client.triggerHome()
        try await Task.sleep(nanoseconds: 220_000_000)
        XCTAssertFalse(client.home)
        let held = flags()
        XCTAssertFalse(held.isEmpty)
        XCTAssertTrue(held.allSatisfy { $0 == 1 }, "UI release must preserve a mapped HOME hold")
        controller.extendedGamepad!.buttonA.setValue(0)
        try await waitForFlag(0)

        client.triggerHome()
        try await waitForFlag(1)
        client.stop()
        XCTAssertFalse(client.home)
        XCTAssertFalse(client.isSendTimerRunning)
        try await waitForFlag(0)
        client.start()
        try await Task.sleep(nanoseconds: 220_000_000)
        let restarted = flags()
        XCTAssertFalse(restarted.isEmpty)
        XCTAssertTrue(restarted.allSatisfy { $0 == 0 }, "Reconnect must not retain a HOME press")
    }
}
