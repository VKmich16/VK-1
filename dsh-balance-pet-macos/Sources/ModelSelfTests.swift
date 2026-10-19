import Foundation

/// Offline regressions exercise public behavior and count actual sound cues.
/// No wall clock, network request, credential, window, or audio device is needed.
enum ModelSelfTests {
    static func run(_ expect: (Bool, String) -> Void) {
        func reading(_ cny: Double) -> BalanceReading {
            BalanceReading(normalCny: cny, bonusCny: 0, spentCny: nil, raw: "")
        }
        func model(_ cny: Double) -> PetModel {
            let model = PetModel()
            model.apply(reading: reading(cny), snap: true)
            return model
        }
        func advance(_ model: PetModel, frames: Int = 600) {
            for _ in 0..<frames { model.tick(1.0 / 60.0) }
        }

        let queued = model(10)
        var queuedHits = 0
        queued.onHit = { queuedHits += 1 }
        queued.apply(reading: reading(9.9), snap: false)
        queued.tick(0)
        queued.apply(reading: reading(9.9), snap: false)
        advance(queued)
        expect(queued.displayedCents == 990 && queuedHits == 10,
               "repeated readings during a deduction do not replay paid cents")

        let extended = model(10)
        var extendedHits = 0
        extended.onHit = { extendedHits += 1 }
        extended.apply(reading: reading(9.95), snap: false)
        extended.tick(0)
        extended.apply(reading: reading(9.90), snap: false)
        advance(extended)
        expect(extended.displayedCents == 990 && extendedHits == 10,
               "new spending extends a partly animated queue without losing cues")

        let credit = model(10)
        var creditHits = 0
        credit.onHit = { creditHits += 1 }
        credit.apply(reading: reading(9.9), snap: false)
        credit.tick(0)
        credit.apply(reading: reading(9.92), snap: false)
        expect(credit.displayedCents == 992 && credit.topupTime > 0 &&
               credit.floating.last?.text == "+0.02",
               "a top-up below the lagging display credits the actual server delta")
        advance(credit)
        expect(creditHits == 1 && credit.displayedCents == 992,
               "top-up reconciliation cancels obsolete deduction cues")

        let demoPoll = model(20)
        var demoHits = 0
        demoPoll.onHit = { demoHits += 1 }
        demoPoll.playDemo(times: 5)
        demoPoll.tick(0)
        demoPoll.apply(reading: reading(20), snap: false)
        expect(demoPoll.displayedCents == 1999 && demoPoll.topupTime == 0,
               "an unchanged poll does not treat a demo offset as a top-up")
        advance(demoPoll)
        expect(demoHits == 5 && demoPoll.displayedCents == 2000 && demoPoll.realCents == 2000,
               "all demo cues play and restore the unchanged real balance")

        let mixed = model(20)
        var mixedHits = 0
        mixed.onHit = { mixedHits += 1 }
        mixed.apply(reading: reading(19.97), snap: false)
        mixed.playDemo(times: 5)
        mixed.tick(0)
        expect(mixed.displayedCents == 1999,
               "real spending takes priority over a queued rehearsal")
        advance(mixed)
        expect(mixedHits == 8 && mixed.displayedCents == 1997 && mixed.realCents == 1997,
               "demo completion preserves every pending real deduction")

        let midDemo = model(20)
        var midDemoHits = 0
        midDemo.onHit = { midDemoHits += 1 }
        midDemo.playDemo(times: 5)
        midDemo.tick(0)
        midDemo.apply(reading: reading(19.97), snap: false)
        advance(midDemo)
        expect(midDemoHits == 8 && midDemo.displayedCents == 1997,
               "spending received during a demo is booked independently of the offset")

        let oneHit = model(2)
        oneHit.playOneHit()
        oneHit.tick(0)
        expect(oneHit.displayedCents == 199 && oneHit.realCents == 200,
               "the final demo step remains visible for its hit animation")
        advance(oneHit)
        expect(oneHit.displayedCents == 200 && !oneHit.needsAnimationFrame,
               "a finished rehearsal restores the balance and stops redrawing")

        let unknown = PetModel()
        var unknownHits = 0
        unknown.onHit = { unknownHits += 1 }
        unknown.playDemo(times: 3)
        advance(unknown)
        expect(unknownHits == 3 && unknown.displayedCents == nil && unknown.realCents == nil &&
               unknown.displayString == "--",
               "offline demos animate without inventing a zero balance")

        let snapped = model(5)
        var snapHits = 0
        snapped.onHit = { snapHits += 1 }
        snapped.apply(reading: reading(4.9), snap: false)
        snapped.playDemo(times: 5)
        snapped.tick(0)
        snapped.apply(reading: reading(4.85), snap: true)
        advance(snapped)
        expect(snapHits == 1 && snapped.displayedCents == 485,
               "manual refresh cancels both real and demo queues")

        let cleared = model(5)
        cleared.setCredentialSource("test")
        cleared.apply(reading: BalanceReading(normalCny: 5, bonusCny: 0, spentCny: 1, raw: ""), snap: true)
        cleared.playDemo(times: 5)
        cleared.tick(0)
        cleared.setNoCredential()
        expect(cleared.realCents == nil && cleared.displayedCents == nil && cleared.spentCny == nil &&
               cleared.lastUpdate == nil && cleared.credentialSource == nil && !cleared.connected &&
               !cleared.needsAnimationFrame && cleared.statusText == "未配置",
               "removing credentials clears old-account values and animation")
        cleared.resetForCredentialChange()
        expect(cleared.statusText == "连接中…" && cleared.lastError == nil,
               "credential replacement enters a clean loading state")

        let negative = model(0)
        var negativeHits = 0
        negative.onHit = { negativeHits += 1 }
        negative.apply(reading: reading(-0.02), snap: false)
        advance(negative)
        expect(negative.displayedCents == -2 && negative.displayString == "-0.02" && negativeHits == 2,
               "a genuine negative balance is not incorrectly clamped to zero")
        expect(model(1.005).displayedCents == 101,
               "decimal half cents round consistently (1.005 becomes 1.01)")

        let boundary = model(10)
        var boundaryHits = 0
        boundary.onHit = { boundaryHits += 1 }
        boundary.apply(reading: reading(6), snap: false)
        advance(boundary, frames: 5000)
        expect(boundaryHits == 400 && boundary.displayedCents == 600,
               "the 400-cent animation limit includes exactly 400 cues")
        boundary.apply(reading: reading(1.99), snap: false)
        advance(boundary)
        expect(boundaryHits == 400 && boundary.displayedCents == 199,
               "larger deductions snap without building an unbounded sound queue")

        let invalid = model(3)
        for amount in [Double.nan, Double.infinity, -Double.infinity, Double.greatestFiniteMagnitude] {
            invalid.apply(reading: reading(amount), snap: false)
        }
        expect(invalid.realCents == 300 && invalid.displayedCents == 300 && !invalid.connected,
               "invalid or overflowing readings preserve the last known balance")
        let enormous = model(9e16)
        enormous.apply(reading: reading(-9e16), snap: false)
        expect(enormous.displayString == "-90000000000000000.00",
               "a difference overflowing Int snaps safely and formats exact cents")
        enormous.apply(reading: reading(9e16), snap: false)
        expect(enormous.displayString == "90000000000000000.00" && enormous.topupTime > 0,
               "an extreme credit cannot overflow its label calculation")

        let rhythm = model(10)
        var rhythmHits = 0
        rhythm.onHit = { rhythmHits += 1 }
        rhythm.apply(reading: reading(9), snap: false)
        rhythm.tick(0)
        advance(rhythm, frames: 120)
        expect(rhythmHits == 11 && rhythm.displayedCents == 989,
               "60 Hz ticks maintain ten 0.2-second intervals over two seconds")
        let before = rhythm.clock
        rhythm.tick(-1)
        rhythm.tick(.nan)
        rhythm.tick(.infinity)
        expect(rhythm.clock == before && rhythmHits == 11,
               "negative and nonfinite frame times cannot corrupt animation state")

        let waking = model(10)
        var wakeHits = 0
        waking.onHit = { wakeHits += 1 }
        waking.apply(reading: reading(9), snap: false)
        waking.tick(86_400)
        expect(wakeHits == 1 && waking.displayedCents == 999 && waking.clock == 0.1,
               "a long frame after sleep cannot trigger a burst of sounds")

        let repeated = model(10)
        var repeatedHits = 0
        repeated.onHit = { repeatedHits += 1 }
        repeated.playDemo(times: Int.max)
        repeated.playDemo(times: Int.max)
        advance(repeated, frames: 3000)
        expect(repeatedHits == 200 && repeated.displayedCents == 1000 && !repeated.needsAnimationFrame,
               "repeated large demo requests share a bounded queue and settle cleanly")
    }
}
