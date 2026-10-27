// SPDX-License-Identifier: GPL-3.0-only
//
// Coffee - Keep your Mac awake, one cup at a time
// Copyright (C) 2026 Coffee authors
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, version 3 of the License.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

import Foundation
import Testing

@testable import Coffee

struct CupTransitionTests {
  let t0 = Date(timeIntervalSinceReferenceDate: 1000)

  func starting(from level: Double = 0) -> CupTransition {
    CupTransition(kind: .starting, startedAt: t0, fromLevel: level, steam: .hidden)
  }

  func stopping(from level: Double = 0.8, steam: CupSteam = .full) -> CupTransition {
    CupTransition(kind: .stopping, startedAt: t0, fromLevel: level, steam: steam)
  }

  func frame(_ transition: CupTransition, at seconds: Double, target: Double = 1) -> CupFrame {
    transition.frame(at: t0 + seconds, level: target)
  }

  func close(_ a: Double, _ b: Double, _ tolerance: Double = 0.001) -> Bool {
    abs(a - b) < tolerance
  }

  func close(_ a: CupSteam, _ start: Double, _ end: Double, _ tolerance: Double = 0.001) -> Bool {
    close(a.start, start, tolerance) && close(a.end, end, tolerance)
  }

  // MARK: - Timing

  @Test func turnOnTakesTwelveStepsAndTurnOffEight() {
    #expect(close(starting().duration, 1.2))
    #expect(close(stopping().duration, 0.8))
    #expect(starting().end == t0 + starting().duration)
  }

  // MARK: - Turn on: pour, fill, drain the stream, draw the steam

  @Test func theCupStartsAsItWasWithAShortStream() {
    let start = frame(starting(from: 0.3), at: 0)
    #expect(close(start.level, 0.3))
    #expect(start.pour == CupPour(top: 3, bottom: 5))
    #expect(start.steam.length == 0)
  }

  @Test func theStreamLengthensSmoothly() throws {
    let halfway = try #require(frame(starting(), at: 0.05).pour)
    #expect(close(halfway.top, 3) && close(halfway.bottom, 5.5))
    #expect(frame(starting(), at: 0.2).pour == CupPour(top: 3, bottom: 7))
  }

  @Test func theCoffeeRisesBetweenItsKeyframes() {
    #expect(close(frame(starting(), at: 0.3).level, 0.1))
    #expect(close(frame(starting(), at: 0.35).level, 0.225))
    #expect(close(frame(starting(), at: 0.45).level, 0.5))
    #expect(close(frame(starting(), at: 0.6).level, 0.9))
    #expect(close(frame(starting(), at: 0.7).level, 1))
  }

  @Test func fillingStartsFromWhereTheCupWas() {
    // 0.4 -> 1: at the 10% keyframe the cup is 10% of the way.
    #expect(close(frame(starting(from: 0.4), at: 0.3).level, 0.4 + 0.6 * 0.1))
  }

  @Test func theStreamShrinksAwayFromTheTopAndVanishes() throws {
    let shrinking = try #require(frame(starting(), at: 0.75).pour)
    #expect(close(shrinking.top, 5.5) && close(shrinking.bottom, 7))
    let almostGone = try #require(frame(starting(), at: 0.88).pour)
    #expect(close(almostGone.top, 6.8, 0.01) && almostGone.bottom == 7)
    #expect(frame(starting(), at: 0.9).pour == nil)
    #expect(frame(starting(), at: 1.1).pour == nil)
  }

  @Test func theSteamIsDrawnOnFromItsBottomPoint() {
    #expect(frame(starting(), at: 0.9).steam.length == 0)
    #expect(close(frame(starting(), at: 0.95).steam, 0, 0.165))
    #expect(close(frame(starting(), at: 1.0).steam, 0, 0.33))
    #expect(close(frame(starting(), at: 1.1).steam, 0, 0.67))
  }

  @Test func turnOnHandsOverToTheLiveCupWithoutAJump() {
    let end = frame(starting(), at: starting().duration)
    #expect(end.level == 1 && end.pour == nil && end.steam == .full)
    let almost = frame(starting(), at: starting().duration - 0.005)
    #expect(close(almost.level, 1, 0.01) && close(almost.steam, 0, 1, 0.02))
  }

  // MARK: - Turn off: the steam retracts from the bottom, the coffee drains

  @Test func turnOffBeginsWithTheCupAsItWas() {
    let start = frame(stopping(from: 0.8), at: 0)
    #expect(close(start.level, 0.8) && close(start.steam, 0, 1) && start.pour == nil)
  }

  @Test func theSteamRetractsFromTheBottomPointUpToTheTop() {
    #expect(close(frame(stopping(), at: 0.1).steam, 0.33, 1))
    #expect(close(frame(stopping(), at: 0.2).steam, 0.67, 1))
    #expect(frame(stopping(), at: 0.3).steam.length == 0)
    #expect(close(frame(stopping(), at: 0.3).level, 0.8))
  }

  @Test func retractingStartsFromHowMuchSteamThereWas() {
    // Caught mid-way through being drawn on, (0 ... 0.4): the bottom end climbs to the 0.4 mark.
    let growing = CupSteam(start: 0, end: 0.4)
    #expect(close(frame(stopping(steam: growing), at: 0.1).steam, 0.33 * 0.4, 0.4))
    #expect(frame(stopping(steam: growing), at: 0.3).steam.length == 0)
    // Caught while already retracting, (0.5 ... 1).
    let shrinking = CupSteam(start: 0.5, end: 1)
    #expect(close(frame(stopping(steam: shrinking), at: 0.2).steam, 0.5 + 0.5 * 0.67, 1))
  }

  @Test func theCoffeeDrainsSmoothlyFromItsCurrentLevel() {
    #expect(close(frame(stopping(from: 1), at: 0.4).level, 0.9))
    #expect(close(frame(stopping(from: 1), at: 0.45).level, 0.775))
    #expect(close(frame(stopping(from: 0.4), at: 0.5).level, 0.4 * 0.65))
    let done = frame(stopping(), at: stopping().duration)
    #expect(done.level == 0 && done.steam.length == 0)
  }

  @Test func timesPastTheEndStayOnTheLastPose() {
    #expect(frame(starting(), at: 60) == frame(starting(), at: starting().duration))
    #expect(frame(stopping(), at: 60) == frame(stopping(), at: stopping().duration))
  }

  // MARK: - Continuity

  @Test func nothingJumpsAnywhereInEitherAnimation() {
    for transition in [starting(from: 0.2), stopping(from: 1, steam: .full)] {
      var previous = frame(transition, at: 0)
      var seconds = 0.005
      while seconds <= transition.duration {
        let current = frame(transition, at: seconds)
        #expect(abs(current.level - previous.level) < 0.03, "level at \(seconds)")
        #expect(abs(current.steam.start - previous.steam.start) < 0.05, "steam start at \(seconds)")
        #expect(abs(current.steam.end - previous.steam.end) < 0.05, "steam end at \(seconds)")
        if let a = previous.pour, let b = current.pour {
          #expect(abs(a.top - b.top) < 0.3 && abs(a.bottom - b.bottom) < 0.3, "pour at \(seconds)")
        }
        previous = current
        seconds += 0.005
      }
    }
  }

  // MARK: - Turned off by hand: the cup tips over and spills

  func spilling(from level: Double = 1, steam: CupSteam = .full) -> CupTransition {
    CupTransition(kind: .spilling, startedAt: t0, fromLevel: level, steam: steam)
  }

  /// When coffee first falls from the lip, sampling every 10 ms.
  func firstSpill(_ transition: CupTransition) -> Double? {
    stride(from: 0.0, through: transition.duration, by: 0.01).first {
      frame(transition, at: $0).spill != nil
    }
  }

  @Test func spillingTakesFourteenSteps() {
    #expect(close(spilling().duration, 1.4))
  }

  @Test func spillingBeginsWithTheCupAsItWas() {
    let start = frame(spilling(from: 0.8), at: 0)
    #expect(
      close(start.level, 0.8) && start.tilt == 0 && start.steam == .full && start.spill == nil)
  }

  @Test func theSteamPullsBackBeforeTheCupTips() {
    #expect(close(frame(spilling(), at: 0.1).steam, 0.5, 1))
    #expect(frame(spilling(), at: 0.2).steam.length == 0)
  }

  @Test func theCupTipsOverAndRightsItselfWithAWobble() {
    #expect(close(frame(spilling(), at: 0.4).tilt, 52))
    #expect(close(frame(spilling(), at: 0.75).tilt, 85))
    #expect(close(frame(spilling(), at: 1.2).tilt, -6))
    #expect(frame(spilling(), at: spilling().duration).tilt == 0)
  }

  @Test func coffeeOnlyLeavesOverTheRim() {
    // The cup never holds more than fits at the furthest it has tipped so far, and never refills.
    for level in [1.0, 0.6, 0.3] {
      let transition = spilling(from: level)
      var peak = 0.0
      var previous = level
      for seconds in stride(from: 0.0, through: 1.4, by: 0.01) {
        let current = frame(transition, at: seconds)
        peak = max(peak, current.tilt)
        #expect(current.level <= min(level, CupIcon.capacity(tilt: peak)) + 0.005)
        #expect(current.level <= previous + 1e-9)
        previous = current.level
      }
    }
  }

  @Test func aFullCupSpillsSoonerThanALowOne() throws {
    #expect(try #require(firstSpill(spilling(from: 1))) < 0.25)
    #expect(try #require(firstSpill(spilling(from: 0.3))) > 0.4)
  }

  @Test func theStreamStartsAtTheLipAndFallsAway() throws {
    let starting = try #require(frame(spilling(), at: 0.2).spill)
    #expect(starting.start == 0 && starting.end > 0 && starting.end < 1)
    #expect(frame(spilling(), at: 0.45).spill == CupSpill(start: 0, end: 1))
    let leaving = try #require(frame(spilling(), at: 0.6).spill)
    #expect(leaving.start > 0 && leaving.end == 1)
    #expect(frame(spilling(), at: 1.0).spill == nil)
  }

  @Test func theCupEndsUprightAndEmpty() {
    let end = frame(spilling(), at: spilling().duration)
    #expect(end.level == 0 && end.tilt == 0 && end.spill == nil && end.steam.length == 0)
    #expect(frame(spilling(), at: 60) == end)
  }

  @Test func anEmptyCupTipsWithoutSpilling() {
    #expect(firstSpill(spilling(from: 0)) == nil)
    #expect(close(frame(spilling(from: 0), at: 0.75).tilt, 85))
  }

  @Test func nothingJumpsWhileSpilling() {
    for transition in [spilling(from: 1), spilling(from: 0.3)] {
      var previous = frame(transition, at: 0)
      for seconds in stride(from: 0.005, through: transition.duration, by: 0.005) {
        let current = frame(transition, at: seconds)
        #expect(abs(current.tilt - previous.tilt) < 2, "tilt at \(seconds)")
        #expect(abs(current.level - previous.level) < 0.03, "level at \(seconds)")
        if let a = previous.spill, let b = current.spill {
          #expect(abs(a.start - b.start) < 0.06 && abs(a.end - b.end) < 0.06, "spill at \(seconds)")
        }
        previous = current
      }
    }
  }
}
