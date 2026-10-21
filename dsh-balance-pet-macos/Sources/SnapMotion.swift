import Foundation

/// Deterministic 160 ms easing. NSWindow's animator does not animate setFrameOrigin reliably.
struct SnapMotion {
    let from: CGPoint
    let to: CGPoint
    private(set) var elapsed = 0.0
    let duration = 0.16
    var finished: Bool { elapsed >= duration }
    mutating func advance(_ dt: Double) -> CGPoint {
        guard dt.isFinite, dt >= 0 else { return from }
        elapsed = min(duration, elapsed+dt)
        let t = elapsed/duration
        let eased = 1-pow(1-t, 3)
        return CGPoint(x: from.x+(to.x-from.x)*eased, y: from.y+(to.y-from.y)*eased)
    }
}
