import Darwin
import Foundation

enum UDPSocket {
    static func make() throws -> Int32 {
        let descriptor = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard descriptor >= 0 else { throw error() }
        // Darwin may raise SIGPIPE on a failed UDP send, including when local
        // network access is denied. Apply to the socket before connect or send,
        // including the best-effort neutral packets used during cleanup.
        var enabled: Int32 = 1
        guard
            setsockopt(
                descriptor, SOL_SOCKET, SO_NOSIGPIPE, &enabled,
                socklen_t(MemoryLayout<Int32>.size)) == 0
        else {
            let failure = error()
            Darwin.close(descriptor)
            throw failure
        }
        guard fcntl(descriptor, F_SETFL, O_NONBLOCK) >= 0 else {
            let failure = error()
            Darwin.close(descriptor)
            throw failure
        }
        return descriptor
    }

    private static func error() -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}
