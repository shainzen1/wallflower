import Foundation
import Testing
@testable import AgentOverview

@Suite("Row entrance")
@MainActor
struct RowEntranceTests {
    // MARK: Spring

    @Test func springPhysicsMatchResponseAndBounce() {
        let spring = EntranceSpring(response: 0.42, bounce: 0.25)
        #expect(abs(spring.dampingRatio - 0.75) < 1e-9)
        #expect(abs(spring.stiffness - pow(2 * .pi / 0.42, 2)) < 1e-6)
        #expect(abs(spring.damping - 2 * 0.75 * 2 * .pi / 0.42) < 1e-6)
    }

    @Test func springLandsThenOvershootsSlightly() {
        let spring = Theme.rowEnterSpring
        let landing = spring.landingTime
        #expect(abs(spring.progress(at: landing) - 1) < 1e-6, "the landing is where the spring first reaches its target")
        #expect(spring.progress(at: landing * 0.9) < 1)
        #expect(spring.progress(at: landing * 1.1) > 1, "then it overshoots")
        #expect(spring.overshoot > 0.01 && spring.overshoot < 0.1, "a visible but small overshoot")
        let settle = spring.settleTime(tolerance: Theme.rowEnterSettleTolerance)
        #expect(settle > landing)
        for t in stride(from: settle, through: settle + 1, by: 0.01) {
            #expect(abs(spring.progress(at: t) - 1) <= Theme.rowEnterSettleTolerance + 1e-9)
        }
    }

    // MARK: Delays and stagger

    @Test func singleArrivalPopsAfterTheSlotOpenedLessTheOverlap() {
        let delay = RowEntrance.faceDelay(order: 0, slotOpens: true, reduceMotion: false)
        #expect(abs(delay - (Theme.rowOpenDuration - Theme.rowEnterOverlap)) < 1e-9)
        #expect(delay > 0 && delay < Theme.rowOpenDuration, "the pop overlaps the end of the opening")
    }

    @Test func staggerStepsTopToBottomAndIsCapped() {
        let base = RowEntrance.faceDelay(order: 0, slotOpens: true, reduceMotion: false)
        for order in 0...Theme.rowEnterStaggerCap {
            let delay = RowEntrance.faceDelay(order: order, slotOpens: true, reduceMotion: false)
            #expect(abs(delay - base - Double(order) * Theme.rowEnterStagger) < 1e-9)
        }
        let capped = RowEntrance.faceDelay(order: Theme.rowEnterStaggerCap, slotOpens: true, reduceMotion: false)
        #expect(RowEntrance.faceDelay(order: Theme.rowEnterStaggerCap + 5, slotOpens: true, reduceMotion: false) == capped)
    }

    @Test func onlyNewFacesArriveAndTheDividerTakesNoStep() {
        let delays = RowEntrance.faceDelays(previous: ["s1", "s2"], current: ["s1", "s3", "s2", "s4", "divider", "aX"], reduceMotion: false)
        #expect(Set(delays.keys) == ["s3", "s4", "aX"])
        let base = RowEntrance.faceDelay(order: 0, slotOpens: true, reduceMotion: false)
        #expect(delays["s3"] == base)
        #expect(delays["s4"] == base + Theme.rowEnterStagger)
        #expect(delays["aX"] == base + 2 * Theme.rowEnterStagger)
    }

    @Test func firstLayoutOpensNoSlotsTheFacesOnlyStagger() {
        let delays = RowEntrance.faceDelays(previous: nil, current: ["s1", "s2", "s3"], reduceMotion: false)
        #expect(delays["s1"] == 0)
        #expect(delays["s2"] == Theme.rowEnterStagger)
        #expect(delays["s3"] == 2 * Theme.rowEnterStagger)
    }

    @Test func reorderArrivesNothing() {
        #expect(RowEntrance.faceDelays(previous: ["s1", "s2"], current: ["s2", "s1"], reduceMotion: false).isEmpty)
    }

    // MARK: Face timing

    @Test func popLandsSquashesThenOpensTheEyes() {
        let timing = RowEntrance.FaceTiming(delay: 0.16, reduceMotion: false)
        #expect(timing.fromScale == Double(Theme.rowEnterScale))
        #expect(timing.fromScale > 0 && timing.fromScale < 1, "never from 0")
        #expect(abs(timing.landing - (0.16 + Theme.rowEnterSpring.landingTime)) < 1e-9)
        #expect(abs(timing.landingEnd - timing.landing - Theme.hopSquashDuration) < 1e-9)
        #expect(timing.eyesOpen > timing.landing, "the lids open after the body settled")
        #expect(abs(timing.end - timing.eyesOpen - Theme.blobBlinkOpen) < 1e-9)
    }

    @Test func eyesStayClosedUntilTheyOpen() {
        let open = BlobEyePose()
        let track = BlobTrack.openingEyes(key: "oneshot.enterEyes", open: open, opensAt: 0.5)
        #expect(!track.repeats)
        #expect(abs(track.duration - (0.5 + Theme.blobBlinkOpen)) < 1e-9)
        #expect(track.samples.first?.pose.lid == Theme.blobClosedLid)
        #expect(track.samples.first { $0.time == 0.5 }?.pose.lid == Theme.blobClosedLid)
        #expect(track.samples.last?.pose == open)
    }

    // MARK: Departure

    @Test func departureIsFasterThanTheArrival() {
        let arrival = Theme.rowOpenDuration - Theme.rowEnterOverlap + Theme.rowEnterSpring.settleTime(tolerance: Theme.rowEnterSettleTolerance)
        #expect(RowEntrance.departureEnd(reduceMotion: false) < arrival)
        #expect(Theme.rowLeaveDuration < Theme.rowOpenDuration)
        #expect(RowEntrance.departureEnd(reduceMotion: false) <= Theme.closeSpringSettleTime, "the window shrinks only after the slot closed")
    }

    @Test func faceLeavesFirstThenTheSlotCloses() {
        let start = RowEntrance.departure(elapsed: 0, reduceMotion: false)
        #expect(start.scale == 1 && start.opacity == 1 && start.slot == 1)
        let mid = RowEntrance.departure(elapsed: Theme.rowLeaveDuration / 2, reduceMotion: false)
        #expect(mid.scale < 1 && mid.opacity < 1)
        #expect(mid.slot == 1, "the slot stays open while the face leaves")
        let left = RowEntrance.departure(elapsed: Theme.rowLeaveDuration, reduceMotion: false)
        #expect(abs(left.scale - Double(Theme.rowExitScale)) < 1e-6)
        #expect(left.opacity < 1e-6)
        #expect(left.slot == 1)
        let closing = RowEntrance.departure(elapsed: Theme.rowLeaveDuration + Theme.rowCloseDuration / 2, reduceMotion: false)
        #expect(closing.slot > 0 && closing.slot < 1)
        let end = RowEntrance.departure(elapsed: RowEntrance.departureEnd(reduceMotion: false), reduceMotion: false)
        #expect(end.slot < 1e-6)
    }

    // MARK: Reduce Motion

    @Test func reduceMotionFadesOnly() {
        let timing = RowEntrance.FaceTiming(delay: 0, reduceMotion: true)
        #expect(timing.fromScale == 1, "no scale")
        #expect(timing.fadeDuration == Theme.reduceMotionFadeDuration)
        #expect(timing.eyesOpen == timing.delay, "no closed-lid entrance")
        #expect(RowEntrance.slotOpenAnimation(reduceMotion: true) == nil, "slots open at once")
        #expect(RowEntrance.faceDelay(order: 0, slotOpens: true, reduceMotion: true) == 0, "no slot to wait for")
        #expect(RowEntrance.faceDelay(order: 2, slotOpens: true, reduceMotion: true) == 2 * Theme.rowEnterStagger)
        let mid = RowEntrance.departure(elapsed: Theme.rowLeaveDuration / 2, reduceMotion: true)
        #expect(mid.scale == 1 && mid.opacity < 1 && mid.slot == 1)
        let end = RowEntrance.departure(elapsed: Theme.rowLeaveDuration, reduceMotion: true)
        #expect(end.opacity < 1e-6 && end.slot == 0, "the slot snaps shut once the fade is over")
    }

    // MARK: Model

    @Test func modelPlansArrivalsAgainstTheLastLayoutAndAnimatesTheGooOnTheSlotCurve() {
        let store = SessionStore(folder: URL(filePath: "/nonexistent"), entrypoints: nil)
        defer { store.stop() }
        let model = PanelModel(store: store)
        #expect(model.entranceDelays(stackIDs: ["s1"], reduceMotion: false) == ["s1": 0], "the first layout only staggers")
        model.layoutDidChange(rows: 1, actions: 0, stackIDs: ["s1"])
        let delays = model.entranceDelays(stackIDs: ["s1", "s2"], reduceMotion: false)
        #expect(delays == ["s2": RowEntrance.faceDelay(order: 0, slotOpens: true, reduceMotion: false)])

        #expect(model.gooAnimation(capsuleHeight: Theme.capsuleHeight(rows: 2), reduceMotion: false) == RowEntrance.slotOpenAnimation(reduceMotion: false))
        #expect(model.gooAnimation(capsuleHeight: Theme.capsuleHeight(rows: 2), reduceMotion: true) == nil)
        model.layoutDidChange(rows: 2, actions: 0, stackIDs: ["s1", "s2"])
        #expect(model.gooAnimation(capsuleHeight: Theme.capsuleHeight(rows: 1), reduceMotion: false) == RowEntrance.slotCloseAnimation(reduceMotion: false))
        #expect(model.gooAnimation(capsuleHeight: Theme.capsuleHeight(rows: 2), reduceMotion: false) == model.gooAnimation, "same height: the hover springs")
        // The stack's own animation drives a removal transition, so a shrink must run on the departure progress.
        #expect(model.layoutAnimation(rowCount: 1, reduceMotion: false) == RowEntrance.departureAnimation(reduceMotion: false))
        #expect(model.layoutAnimation(rowCount: 1, reduceMotion: true) == RowEntrance.departureAnimation(reduceMotion: true))
        #expect(model.layoutAnimation(rowCount: 2) == Theme.openSpring, "reorders keep the row spring")
    }
}
