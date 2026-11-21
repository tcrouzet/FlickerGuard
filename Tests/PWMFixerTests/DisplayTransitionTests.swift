import Foundation
import Testing
@testable import PWMFixer

@Test func displayFadeTakesOneMinuteAndClampsItsEndpoints() {
    let start = Date(timeIntervalSince1970: 1000)
    let from = DisplayTransition.Levels(hardware: 1, software: 0.15)
    let to = DisplayTransition.Levels(hardware: 0.42, software: 1)
    let fade = DisplayTransition(from: from, to: to, destination: .native, startedAt: start)
    #expect(fade.levels(at: start.addingTimeInterval(-1)) == from)
    #expect(fade.levels(at: start) == from)
    #expect(fade.isComplete(at: start.addingTimeInterval(59.75)) == false)
    #expect(fade.levels(at: start.addingTimeInterval(59.75)).software < 1)
    #expect(fade.isComplete(at: start.addingTimeInterval(60)))
    #expect(fade.levels(at: start.addingTimeInterval(60)) == to)
    #expect(fade.levels(at: start.addingTimeInterval(120)) == to)
    var previous = from
    for tick in 1...240 {
        let next = fade.levels(at: start.addingTimeInterval(Double(tick) / 4))
        #expect(next.hardware <= previous.hardware)
        #expect(next.software >= previous.software)
        #expect(abs(next.hardware - previous.hardware) < 0.007)
        #expect(abs(next.software - previous.software) < 0.007)
        previous = next
    }
}

@Test func reversingFadeStartsAtCurrentLevelsWithoutAJump() {
    let start = Date(timeIntervalSince1970: 1000)
    let software = DisplayTransition.Levels(hardware: 1, software: 0.2)
    let native = DisplayTransition.Levels(hardware: 0.42, software: 1)
    let outbound = DisplayTransition(from: software, to: native, destination: .native, startedAt: start)
    let switchTime = start.addingTimeInterval(23)
    let current = outbound.levels(at: switchTime)
    let inbound = DisplayTransition(from: current, to: software, destination: .software, startedAt: switchTime)
    #expect(current != software && current != native)
    #expect(inbound.levels(at: switchTime) == current)
    let next = inbound.levels(at: switchTime.addingTimeInterval(0.25))
    #expect(next.hardware > current.hardware && next.hardware - current.hardware < 0.001)
    #expect(next.software < current.software && current.software - next.software < 0.001)
    #expect(inbound.levels(at: switchTime.addingTimeInterval(60)) == software)
}
