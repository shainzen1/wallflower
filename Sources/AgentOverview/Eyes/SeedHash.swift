import Foundation

/// Deterministic 64 bit hash of a string (FNV-1a over UTF-8), plus a mixer that turns the
/// hash and a slot number into stable unit values. Swift's `hashValue` is randomised per
/// process, so it must not be used for identity.
struct SeedHash: Equatable, Hashable, Sendable {
    let value: UInt64

    init(_ seed: String) {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in seed.utf8 {
            h ^= UInt64(byte)
            h = h &* 0x0000_0100_0000_01b3
        }
        value = h
    }

    /// A stable value in [0, 1) for the given slot; different slots are independent.
    func unit(_ slot: UInt64) -> Double {
        var z = value &+ (slot &+ 1) &* 0x9e37_79b9_7f4a_7c15
        z = (z ^ (z >> 30)) &* 0xbf58_476d_1ce4_e5b9
        z = (z ^ (z >> 27)) &* 0x94d0_49bb_1331_11eb
        z ^= z >> 31
        return Double(z >> 11) / Double(1 << 53)
    }

    /// A stable index in `0..<count` for the given slot.
    func index(_ slot: UInt64, count: Int) -> Int {
        Int(unit(slot) * Double(count)) % max(count, 1)
    }

    /// A stable value inside the range for the given slot.
    func value(in range: ClosedRange<Double>, slot: UInt64) -> Double {
        range.lowerBound + (range.upperBound - range.lowerBound) * unit(slot)
    }
}
