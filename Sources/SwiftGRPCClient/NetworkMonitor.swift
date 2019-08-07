// The monitoring code below is derived from grpc-swift project.
// https://github.com/grpc/grpc-swift
// BEGIN grpc-swift derivation

#if os(iOS)
import CoreTelephony
#endif
import Dispatch
import SystemConfiguration

/// This class may be used to monitor changes on the device that can cause gRPC to silently disconnect (making
/// it seem like active calls/connections are hanging), then manually shut down / restart gRPC channels as
/// needed. The root cause of these problems is that the backing gRPC-Core doesn't get the optimizations
/// made by iOS' networking stack when changes occur on the device such as switching from wifi to cellular,
/// switching between 3G and LTE, enabling/disabling airplane mode, etc.
/// Read more: https://github.com/grpc/grpc-swift/tree/master/README.md#known-issues
/// Original issue: https://github.com/grpc/grpc-swift/issues/337
public final class NetworkMonitor {
    private let queue: DispatchQueue
    private let reachability: SCNetworkReachability
    private let notification: NotificationCenter

    #if os(iOS)
    /// Instance of network info being used for obtaining cellular technology names.
    public let cellularInfo = CTTelephonyNetworkInfo()
    /// Name of the cellular technology being used (e.g., `CTRadioAccessTechnologyLTE`).
    public private(set) var cellularName: String?
    #endif
    #if os(iOS) || os(tvOS)
    /// Whether the device is currently using wifi (versus cellular).
    public private(set) var isUsingWifi: Bool
    #endif
    /// Whether the network is currently reachable. Backed by `SCNetworkReachability`.
    public private(set) var isReachable: Bool
    /// Network state handler.
    public var stateHandler: ((State) -> Void)?

    /// Represents a state of connectivity.
    public struct State: Equatable {
        /// The most recent change that was made to the state.
        public var lastChange: Change
        /// Whether this state is currently reachable/online.
        public var isReachable: Bool

        public init(change: Change, isReachable: Bool) {
            self.lastChange = change
            self.isReachable = isReachable
        }
    }

    /// A change in network condition.
    public enum Change: Equatable {
        /// Reachability changed (online <> offline).
        case reachability(isReachable: Bool)
        /// The device switched from cellular to wifi.
        case cellularToWifi
        /// The device switched from wifi to cellular.
        case wifiToCellular
        /// The cellular technology changed (e.g., 3G <> LTE).
        case cellularTechnology(technology: String)
    }

    public init?(
        host: String = "google.com",
        queue: DispatchQueue = DispatchQueue(label: "SwiftGRPCClient.NetworkMonitor.queue"),
        notification: NotificationCenter = NotificationCenter.default,
        handler: ((State) -> Void)? = nil
        ) {
        guard let reachability = SCNetworkReachabilityCreateWithName(nil, host) else {
            return nil
        }

        self.queue = queue
        self.stateHandler = handler
        self.reachability = reachability
        self.notification = notification

        var flags = SCNetworkReachabilityFlags()
        SCNetworkReachabilityGetFlags(reachability, &flags)
        self.isReachable = flags.contains(.reachable)
        #if os(iOS) || os(tvOS)
        self.isUsingWifi = !flags.contains(.isWWAN)
        #endif
        #if os(iOS)
        self.cellularName = cellularInfo.currentRadioAccessTechnology
        startMonitoringCellular()
        #endif
        startMonitoringReachability()
    }

    deinit {
        SCNetworkReachabilitySetCallback(reachability, nil, nil)
        SCNetworkReachabilityUnscheduleFromRunLoop(reachability, CFRunLoopGetMain(),
                                                   CFRunLoopMode.commonModes.rawValue)
        notification.removeObserver(self)
    }

    #if os(iOS)
    // MARK: - Cellular

    private func startMonitoringCellular() {
        notification.addObserver(
            self,
            selector: #selector(cellularDidChange(_:)),
            name: .CTRadioAccessTechnologyDidChange,
            object: cellularInfo
        )
    }

    @objc
    private func cellularDidChange(_ notification: NSNotification) {
        queue.async {
            let newCellularName = notification.object as? String ?? self.cellularInfo.currentRadioAccessTechnology
            if let newCellularName = newCellularName, self.cellularName != newCellularName {
                self.cellularName = newCellularName
                self.stateHandler?(State(
                    change: .cellularTechnology(technology: newCellularName),
                    isReachable: self.isReachable
                ))
            }
        }
    }
    #endif

    // MARK: - Reachability

    private func startMonitoringReachability() {
        let info = Unmanaged.passUnretained(self).toOpaque()
        var context = SCNetworkReachabilityContext(version: 0, info: info, retain: nil,
                                                   release: nil, copyDescription: nil)
        let callback: SCNetworkReachabilityCallBack = { _, flags, info in
            let observer = info.map { Unmanaged<NetworkMonitor>.fromOpaque($0).takeUnretainedValue() }
            observer?.reachabilityDidChange(with: flags)
        }

        SCNetworkReachabilitySetCallback(reachability, callback, &context)
        SCNetworkReachabilityScheduleWithRunLoop(reachability, CFRunLoopGetMain(),
                                                 CFRunLoopMode.commonModes.rawValue)
    }

    private func reachabilityDidChange(with flags: SCNetworkReachabilityFlags) {
        queue.async {
            let isReachable = flags.contains(.reachable)
            let notifyForReachable = self.isReachable != isReachable
            self.isReachable = isReachable

            if notifyForReachable {
                self.stateHandler?(State(
                    change: .reachability(isReachable: isReachable),
                    isReachable: isReachable
                ))
            }

            #if os(iOS) || os(tvOS)
            let isUsingWifi = !flags.contains(.isWWAN)
            let notifyForWifi = self.isUsingWifi != isUsingWifi
            self.isUsingWifi = isUsingWifi

            if notifyForWifi {
                self.stateHandler?(State(
                    change: isUsingWifi ? .cellularToWifi : .wifiToCellular,
                    isReachable: isReachable
                ))
            }
            #endif
        }
    }
}
