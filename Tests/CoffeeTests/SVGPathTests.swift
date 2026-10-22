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

import AppKit
import Testing

@testable import Coffee

struct SVGPathTests {
  func close(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) < 0.2 }

  @Test func parsesTheCupBowl() throws {
    let path = try #require(SVGPath.parse("M16 9H4C4 13.5 4 18.5 10 18.5C16 18.5 16 13.5 16 9Z"))
    #expect(close(path.bounds.minX, 4) && close(path.bounds.maxX, 16))
    #expect(close(path.bounds.minY, 9) && close(path.bounds.maxY, 18.5))
  }

  @Test func parsesRelativeCommands() throws {
    let path = try #require(SVGPath.parse("m1 1 l2 0 v2 h-2 z"))
    #expect(path.bounds == NSRect(x: 1, y: 1, width: 2, height: 2))
  }

  @Test func extraCoordinatesAfterMoveAreLines() throws {
    let path = try #require(SVGPath.parse("M0 0 10 0 10 10"))
    #expect(path.bounds == NSRect(x: 0, y: 0, width: 10, height: 10))
  }

  @Test func rejectsCommandsItCannotDraw() {
    #expect(SVGPath.parse("M0 0 A5 5 0 0 1 10 0") == nil)
    #expect(SVGPath.parse("L10") == nil)
    #expect(SVGPath.parse("") == nil)
  }
}
