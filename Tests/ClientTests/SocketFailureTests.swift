import Darwin
import XCTest

@testable import InputRedirection

final class SocketFailureTests: XCTestCase {
    private func failedSocket() throws -> Int32 {
        let descriptor = try UDPSocket.make()
        var option: Int32 = 0
        var length = socklen_t(MemoryLayout<Int32>.size)
        XCTAssertEqual(getsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &option, &length), 0)
        XCTAssertEqual(option, 1, "Every sending socket must suppress SIGPIPE")
        var endpoint = sockaddr_in()
        endpoint.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        endpoint.sin_family = sa_family_t(AF_INET)
        endpoint.sin_port = UInt16(4950).bigEndian
        endpoint.sin_addr.s_addr = inet_addr("127.0.0.1")
        let result = withUnsafePointer(to: &endpoint) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard result == 0 else {
            let message = String(cString: strerror(errno))
            Darwin.close(descriptor)
            throw XCTSkip("Loopback UDP unavailable: \(message)")
        }
        // A write-shutdown socket deterministically reproduces EPIPE.
        guard Darwin.shutdown(descriptor, SHUT_WR) == 0 else {
            Darwin.close(descriptor)
            XCTFail("Unable to simulate a failed UDP send")
            throw POSIXError(.EIO)
        }
        return descriptor
    }

    func testFailedDatagramReturnsEPIPEWithoutSignal() throws {
        let descriptor = try failedSocket()
        defer { Darwin.close(descriptor) }
        var byte: UInt8 = 0
        XCTAssertEqual(Darwin.send(descriptor, &byte, 1, 0), -1)
        XCTAssertEqual(errno, EPIPE)
    }

    @MainActor func testFirstSendFailureStopsCleanlyAndAllowsRetry() throws {
        let name = "InputRedirectionSocketTests.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: name)!
        var attempts = 0
        let client = Client(
            preferences: preferences, controllerProvider: { [] },
            socketFactory: {
                attempts += 1
                return try self.failedSocket()
            })
        defer {
            client.stop()
            preferences.removePersistentDomain(forName: name)
        }
        client.address = "127.0.0.1"
        for expectedAttempts in 1...2 {
            client.start()
            XCTAssertEqual(attempts, expectedAttempts)
            XCTAssertFalse(client.sending)
            XCTAssertFalse(client.isSendTimerRunning)
            XCTAssertTrue(client.status.hasPrefix("Send failed:"), client.status)
            XCTAssertTrue(client.status.contains(String(cString: strerror(EPIPE))), client.status)
        }
    }
}
