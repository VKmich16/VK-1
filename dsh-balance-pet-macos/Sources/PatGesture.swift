import AppKit

/// Hover strokes, never presses: the same 24 pt / 500 ms gate as Windows.
struct PatGesture {
    private(set) var active = false
    private(set) var clock = 0.0
    private var last: CGPoint?
    private var distance: CGFloat = 0
    private var sustained = 0.0
    private var idle = 0.0
    private var settle = 0.0
    private var waitingForPot = false

    mutating func tick(_ dt: Double, point: CGPoint, onPet: Bool, button: Bool, movingPet: Bool,
                       enabled: Bool, hasPot: Bool, knock: () -> Void) {
        guard dt.isFinite, dt >= 0 else { return }
        let step = min(dt, 0.1)
        let delta = last.map { hypot(point.x-$0.x, point.y-$0.y) } ?? 0
        last = point
        guard enabled, !button, !movingPet else {
            active = false; clock = 0; distance = 0; sustained = 0; waitingForPot = false
            if movingPet || button { settle = 1 }
            return
        }
        if settle > 0 { settle = max(0, settle-step); return }
        if waitingForPot {
            if !onPet { waitingForPot = false; return }
            if hasPot { knock(); return }
            waitingForPot = false; active = true; clock = 0; idle = 0
        }
        let moving = onPet && delta > 0 && delta <= 120
        if active {
            idle = moving ? 0 : idle+step
            if idle >= 0.15 { active = false; clock = 0; distance = 0; sustained = 0; return }
            clock = (clock+step).truncatingRemainder(dividingBy: 0.2)
        } else if moving {
            distance = min(96, distance+delta)
            if distance >= 24 { sustained += step }
            if sustained >= 0.5 {
                distance = 0; sustained = 0; idle = 0
                if hasPot { waitingForPot = true; knock() }
                else { active = true; clock = 0 }
            }
        } else if !onPet { distance = 0; sustained = 0 }
        else { distance = max(0, distance-CGFloat(step)*120); sustained = 0 }
    }

    var phase: CGFloat { CGFloat(Int(clock/0.04) % 5) }
}
