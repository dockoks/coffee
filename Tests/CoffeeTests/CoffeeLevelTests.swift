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

struct CoffeeLevelTests {
  @Test(arguments: [
    (-10.0, 1.0), (0, 1.0), (900, 0.75), (1800, 0.5), (3600, 0.0), (7200, 0.0),
  ])
  func oneHourLevel(elapsed: Double, expected: Double) {
    let level = ActivationSpecs.oneHour.spec.coffeeLevel(elapsed: elapsed)
    #expect(abs(level - expected) < 0.0001)
  }

  @Test func foreverStaysFull() {
    #expect(ActivationSpecs.forever.spec.coffeeLevel(elapsed: 100_000) == 1.0)
  }
}
