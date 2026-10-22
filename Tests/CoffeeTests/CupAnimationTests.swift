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

struct CupAnimationTests {
  func close(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 0.001 }

  func close(_ a: CupSteam, _ b: CupSteam) -> Bool {
    close(a.start, b.start) && close(a.end, b.end)
  }

  @Test func steamLoopDrawsAndRetractsTheCurve() {
    let steam = CupAnimation.steam(at:)
    #expect(close(steam(0), .full) && close(steam(0.2), .full))  // held
    #expect(close(steam(0.4), CupSteam(start: 0.25, end: 1)))  // retracting from the bottom point
    #expect(close(steam(0.6), CupSteam(start: 0.5, end: 1)))
    #expect(close(steam(0.8), CupSteam(start: 0.75, end: 1)))
    #expect(steam(1.0).length == 0 && close(steam(1.0).start, 1))  // gone, at the very top
    #expect(steam(1.2).length == 0 && close(steam(1.2).end, 0))  // about to start, at the bottom
    #expect(close(steam(1.4), CupSteam(start: 0, end: 0.35)))  // drawing on from the bottom
    #expect(close(steam(1.6), CupSteam(start: 0, end: 0.7)))
    #expect(close(steam(1.8), .full))
  }

  @Test func steamLoopWrapsAroundSeamlessly() {
    let period = Double(CupAnimation.steamLoop.count) * CupAnimation.steamLoopStep
    #expect(close(period, 2.4))
    #expect(close(CupAnimation.steam(at: period), .full))
    #expect(close(CupAnimation.steam(at: period * 50 + 0.4), CupSteam(start: 0.25, end: 1)))
    #expect(close(CupAnimation.steam(at: -3), .full))  // before the loop starts
  }

  @Test func theCurveShrinksFromItsBottomEndOnly() {
    // While retracting, the top end never moves: the curve loses its bottom, not its top.
    for time in stride(from: 0.2, through: 1.0, by: 0.05) {
      #expect(close(CupAnimation.steam(at: time).end, 1))
    }
    // While drawing on, the bottom end never moves.
    for time in stride(from: 1.2, through: 1.8, by: 0.05) {
      #expect(close(CupAnimation.steam(at: time).start, 0))
    }
  }

  @Test func steamLoopHasNoJumps() {
    var previous = CupAnimation.steam(at: 0)
    var time = 0.005
    while time < 7.2 {
      let steam = CupAnimation.steam(at: time)
      #expect(abs(steam.start - previous.start) < 0.03 && abs(steam.end - previous.end) < 0.03)
      previous = steam
      time += 0.005
    }
  }

  @Test func theLoopStartsWhereTheStartAnimationLeavesOff() throws {
    #expect(CupAnimation.steamLoop.first == .full)
    #expect(try #require(CupAnimation.on.last).steam == .full)
  }

  @Test func theTablesEndOnTheStateTheyHandOverTo() throws {
    let onEnd = try #require(CupAnimation.on.last)
    #expect(onEnd.coffee == 1 && onEnd.pour == nil)
    let offEnd = try #require(CupAnimation.off.last)
    #expect(offEnd.coffee == 0 && offEnd.pour == nil && offEnd.steamShrink == 1)  // curl gone
    let offStart = try #require(CupAnimation.off.first)
    #expect(offStart.coffee == 1 && offStart.steamShrink == 0)  // nothing retracted yet
  }

  @Test func theSpillStartsUprightAndEndsUprightAndEmpty() throws {
    let first = try #require(CupAnimation.spill.first)
    #expect(first.tilt == 0 && first.coffee == 1 && first.steamShrink == 0)
    let last = try #require(CupAnimation.spill.last)
    #expect(last.tilt == 0 && last.coffee == 0 && last.steamShrink == 1)
    #expect(CupAnimation.spill.map(\.tilt).max() == 85)
  }
}
