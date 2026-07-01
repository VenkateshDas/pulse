import Foundation
import Darwin

/// Tracks cumulative network bandwidth on active physical interfaces (e.g., en0)
final class NetworkSampler {
    
    private var prevTime: TimeInterval = 0
    private var prevIn: UInt64 = 0
    private var prevOut: UInt64 = 0
    
    init() {}
    
    /// Returns inbound and outbound bytes per second since the last sample.
    func sample() -> (bytesInPerSecond: UInt64, bytesOutPerSecond: UInt64) {
        var ifaddrsPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrsPtr) == 0 else { return (0, 0) }
        defer { freeifaddrs(ifaddrsPtr) }

        var ptr = ifaddrsPtr
        var bytesIn: UInt64 = 0
        var bytesOut: UInt64 = 0

        while let current = ptr {
            defer { ptr = current.pointee.ifa_next }
            
            let flags = Int32(current.pointee.ifa_flags)
            let isUp = (flags & IFF_UP) != 0
            let isLoopback = (flags & IFF_LOOPBACK) != 0
            
            if isUp && !isLoopback, 
               let addr = current.pointee.ifa_addr,
               addr.pointee.sa_family == UInt8(AF_LINK),
               let dataPtr = current.pointee.ifa_data {
                
                let name = String(cString: current.pointee.ifa_name)
                // Filter specifically for "en" (ethernet/wifi) to exclude bridge/awdl/ipsec
                if name.starts(with: "en") {
                    let ifaData = dataPtr.assumingMemoryBound(to: if_data.self).pointee
                    bytesIn += UInt64(ifaData.ifi_ibytes)
                    bytesOut += UInt64(ifaData.ifi_obytes)
                }
            }
        }
        
        let now = ProcessInfo.processInfo.systemUptime
        let dt = now - prevTime
        let inRate = (prevTime > 0 && dt > 0 && bytesIn > prevIn) ? UInt64(Double(bytesIn - prevIn) / dt) : 0
        let outRate = (prevTime > 0 && dt > 0 && bytesOut > prevOut) ? UInt64(Double(bytesOut - prevOut) / dt) : 0
        
        prevTime = now
        prevIn = bytesIn
        prevOut = bytesOut
        
        return (inRate, outRate)
    }
}
