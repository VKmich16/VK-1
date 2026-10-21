import AppKit

/// Server accounting and animation are kept separate: a menu rehearsal must
/// never consume real deductions or make an unchanged poll look like a top-up.
final class PetModel {
    struct FloatLabel {
        let text: String
        let color: NSColor
        var age: Double
        var x: CGFloat
    }

    // MARK: Accounting

    private var bookedCents: Int?
    private(set) var realCents: Int?
    private(set) var spentCny: Double?
    private(set) var connected = false
    private(set) var statusText = "连接中…"
    private(set) var lastError: String?
    private(set) var credentialSource: String?
    private(set) var lastUpdate: Date?

    private(set) var heldCreditCents = 0
    var blockDeductions = false
    var hurtEffects = true
    private var feedGrace = 0.0
    private var pendingSteps = 0
    private var demoRemaining = 0
    private var demoOffset = 0
    private var demoRestoreTime: Double = 0
    private static let maxPendingSteps = 400
    private static let maxDemoSteps = 500

    var displayedCents: Int? {
        guard let booked = bookedCents else { return nil }
        // Rehearsals stop visually at zero, but a genuine negative balance is
        // preserved. The subtraction is checked even for an extreme input.
        let (value, overflow) = booked.subtractingReportingOverflow(demoOffset)
        return max(min(0, booked), overflow ? Int.min : value)
    }

    var displayString: String { displayedCents.map(Self.fenString) ?? "--" }
    var realString: String { realCents.map(Self.fenString) ?? "--" }

    // MARK: Animation

    private(set) var floating: [FloatLabel] = []
    private(set) var shakeTime: Double = 0
    private(set) var flashTime: Double = 0
    private(set) var topupTime: Double = 0
    private(set) var clock: Double = 0
    private var stepCooldown: Double = 0

    let stepInterval: Double = 0.2
    let hitDuration: Double = 0.55
    let floatLifetime: Double = 0.95

    /// Called once per animated deduction so the controller can play the sound.
    var onHit: (() -> Void)?

    var needsAnimationFrame: Bool {
        pendingSteps > 0 || demoRemaining > 0 || demoRestoreTime > 0 ||
        !floating.isEmpty || shakeTime > 0 || flashTime > 0 || topupTime > 0
    }

    /// True while a deduction cue is being played. Drives the nervous face,
    /// matching the Windows build's `cueRunning`.
    var cueRunning: Bool {
        (!blockDeductions && pendingSteps > 0 && feedGrace <= 0) || demoRemaining > 0 || shakeTime > 0 || flashTime > 0
    }

    /// Zero or negative balance shows the pout face, like the Windows build.
    var broke: Bool {
        guard let real = realCents else { return false }
        return real <= 0
    }

    func flinchForPot() { shakeTime = hitDuration }

    // MARK: Server readings

    /// `snap` discards queued animation and rehearsals (first read/manual refresh).
    func apply(reading: BalanceReading, snap: Bool) {
        guard let cents = reading.totalCents else {
            fail(.parse("余额数值超出可显示范围"))
            return
        }
        let previousReal = realCents
        realCents = cents
        spentCny = reading.spentCny.flatMap { $0.isFinite ? $0 : nil }
        connected = true
        statusText = "已连接"
        lastError = nil
        lastUpdate = Date()

        guard !snap, bookedCents != nil, let previous = previousReal else {
            forceSnapToReal()
            return
        }

        if cents > previous {
            let (credit, overflow) = cents.subtractingReportingOverflow(previous)
            if overflow {
                forceSnapToReal()
                if !suppressCreditFlourish { topupTime = 0.9; appendLabel("余额已更新", color: .systemGreen) }
                return
            }
            if suppressCreditFlourish {
                let (held, exceeded) = heldCreditCents.addingReportingOverflow(credit)
                if exceeded { forceSnapToReal(); return }
                heldCreditCents = held
                reconcileDeductions()
            } else {
                forceSnapToReal()
                topupTime = 0.9
                appendLabel("+" + Self.fenString(credit), color: .systemGreen)
            }
        } else {
            reconcileDeductions()
        }
    }

    private func reconcileDeductions() {
        guard let real = realCents, let booked = bookedCents else { return }
        let (target, overflow) = real.subtractingReportingOverflow(heldCreditCents)
        let (steps, exceeded) = booked.subtractingReportingOverflow(target)
        if overflow || exceeded { forceSnapToReal(); return }
        if steps > Self.maxPendingSteps {
            bookedCents = target
            pendingSteps = 0
        } else if steps > 0 {
            pendingSteps = steps
        } else {
            bookedCents = target
            pendingSteps = 0
        }
    }

    /// A delivered bowl releases only its own credit. Rehearsals never touch books.
    @discardableResult
    func deliverCredit(cents: Int, test: Bool) -> Int {
        guard cents > 0 else { return 0 }
        if test { showFeedCredit(Double(cents) / 100); return cents }
        let gain = min(cents, heldCreditCents)
        guard gain > 0, let booked = bookedCents else { return 0 }
        let (value, overflow) = booked.addingReportingOverflow(gain)
        if overflow { forceSnapToReal(); return 0 }
        bookedCents = value
        heldCreditCents -= gain
        reconcileDeductions()
        feedGrace = 2
        showFeedCredit(Double(gain) / 100)
        return gain
    }

    func fail(_ error: FetchError) {
        connected = false
        lastError = error.describe
        statusText = "离线"
        Log.write("poll failed: \(error.describe)")
    }

    /// Invalidate the old account before asynchronously reading a new credential.
    func resetForCredentialChange() {
        heldCreditCents = 0
        feedGrace = 0
        bookedCents = nil
        realCents = nil
        spentCny = nil
        connected = false
        statusText = "连接中…"
        lastError = nil
        credentialSource = nil
        lastUpdate = nil
        clearQueue()
        floating.removeAll()
        shakeTime = 0
        flashTime = 0
        topupTime = 0
    }

    func setNoCredential() {
        resetForCredentialChange()
        lastError = "找不到凭证"
        statusText = "未配置"
    }

    func setCredentialSource(_ source: String?) { credentialSource = source }

    /// When the bowl animation owns the credit, the poll should not also flash a
    /// "+x.xx": the floater appears when she is actually fed.
    var suppressCreditFlourish = false

    /// Celebration shown when a rice bowl is delivered to her.
    func showFeedCredit(_ amount: Double) {
        topupTime = 0.9
        let text = amount > 0 ? String(format: "+%.2f", amount) : "喂饱啦"
        appendLabel(text, color: .systemGreen)
        appendLabel("♥", color: .systemPink, x: 0.24)
        appendLabel("♥", color: .systemPink, x: 0.76)
    }

    func forceSnapToReal() {
        heldCreditCents = 0
        bookedCents = realCents
        clearQueue()
    }

    private func clearQueue() {
        pendingSteps = 0
        demoRemaining = 0
        demoOffset = 0
        demoRestoreTime = 0
        stepCooldown = 0
    }

    func playOneHit() { playDemo(times: 1) }

    func playDemo(times: Int) {
        let count = max(1, min(times, Self.maxDemoSteps))
        // Bound the total queue, including repeated menu clicks. Preserve the
        // existing cooldown so repeated clicks cannot bypass the 0.2 s rhythm.
        demoRemaining = min(Self.maxDemoSteps, demoRemaining + count)
        demoRestoreTime = 0
    }

    // MARK: Frame tick

    func tick(_ dt: Double) {
        guard dt.isFinite, dt >= 0 else { return }
        // A wake from sleep should not produce a burst of hundreds of sounds.
        // The controller uses the same limit for its frame clock.
        let elapsed = min(dt, 0.1)
        clock += elapsed
        feedGrace = max(0, feedGrace - elapsed)
        shakeTime = max(0, shakeTime - elapsed)
        flashTime = max(0, flashTime - elapsed)
        topupTime = max(0, topupTime - elapsed)

        for i in floating.indices { floating[i].age += elapsed }
        floating.removeAll { $0.age >= floatLifetime }

        if demoRestoreTime > 0 {
            demoRestoreTime = max(0, demoRestoreTime - elapsed)
            if demoRestoreTime == 0 { demoOffset = 0 }
        }

        guard ((!blockDeductions && feedGrace <= 0) && pendingSteps > 0) || demoRemaining > 0 else {
            stepCooldown = max(0, stepCooldown - elapsed)
            return
        }

        stepCooldown -= elapsed
        guard stepCooldown <= 1e-9 else { return }
        // Keep the fractional frame remainder. Resetting to exactly 0.2 here
        // silently stretches each cue to 13 frames on a 60 Hz display.
        stepCooldown = max(0, stepCooldown + stepInterval)
        if !blockDeductions, feedGrace <= 0, pendingSteps > 0, let booked = bookedCents {
            bookedCents = booked - 1 // Safe because booked is strictly above real.
            pendingSteps -= 1
        } else if demoRemaining > 0 {
            demoRemaining -= 1
            if demoOffset < Int.max { demoOffset += 1 }
            if demoRemaining == 0 { demoRestoreTime = hitDuration }
        } else {
            pendingSteps = 0
            return
        }

        if hurtEffects {
            shakeTime = hitDuration
            flashTime = hitDuration
            appendLabel("-0.01", color: .systemRed)
            onHit?()
        }
    }

    private func appendLabel(_ text: String, color: NSColor, x: CGFloat = 0.5) {
        floating.append(FloatLabel(text: text, color: color, age: 0, x: x))
        if floating.count > 60 { floating.removeFirst(floating.count - 60) }
    }

    // MARK: View helpers

    var impact: Double {
        guard shakeTime > 0 else { return 0 }
        let elapsed = hitDuration - shakeTime
        if elapsed < 0.08 { return min(1, elapsed / 0.08) }
        return max(0, 1 - (elapsed - 0.08) / (hitDuration - 0.08))
    }

    /// Integer formatting preserves cents even above Double's exact range and
    /// handles Int.min without trying to negate it.
    private static func fenString(_ fen: Int) -> String {
        let magnitude = fen.magnitude
        let fraction = magnitude % 100
        return "\(fen < 0 ? "-" : "")\(magnitude / 100).\(fraction < 10 ? "0" : "")\(fraction)"
    }
}
