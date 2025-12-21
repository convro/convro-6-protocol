//
//  C6PSessionState+Compat.swift
//  Convro-6-Protocol (C6P)
//
//  Compatibility layer so older SessionService code (sendCounter/recvCounter)
//  works with the newer stream-based counters (nextI2RCounter/nextR2ICounter).
//

import Foundation

extension UInt64 {
    mutating func increment() { self &+= 1 }
}

extension C6PSessionState {

    /// Legacy name used by older SessionService: "counter for local sending".
    /// Maps to stream-based counters.
    var sendCounter: UInt64 {
        get {
            switch localSendStream {
            case .i2r: return nextI2RCounter
            case .r2i: return nextR2ICounter
            }
        }
        set {
            switch localSendStream {
            case .i2r: nextI2RCounter = newValue
            case .r2i: nextR2ICounter = newValue
            }
        }
    }

    /// Legacy name used by older SessionService: "expected counter for local receiving".
    /// Maps to stream-based counters.
    var recvCounter: UInt64 {
        get {
            switch localRecvStream {
            case .i2r: return nextI2RCounter
            case .r2i: return nextR2ICounter
            }
        }
        set {
            switch localRecvStream {
            case .i2r: nextI2RCounter = newValue
            case .r2i: nextR2ICounter = newValue
            }
        }
    }
}
