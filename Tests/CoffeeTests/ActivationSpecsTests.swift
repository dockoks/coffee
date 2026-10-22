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

struct ActivationSpecsTests {
  @Test func offersFinePresetsInAscendingOrder() {
    let specs = ActivationSpecs.allCases.map(\.spec)
    #expect(specs.first?.title == "Forever")
    let minutes = specs.dropFirst().map { Int($0.timeInterval / 60) }
    #expect(minutes == [15, 30, 45, 60, 90, 120, 180, 240, 360, 480, 720])
  }

  @Test func titlesAndShortcutsAreUnique() {
    let specs = ActivationSpecs.allCases.map(\.spec)
    #expect(Set(specs.map(\.title)).count == specs.count)
    let labels = specs.map(\.label).filter { !$0.isEmpty }
    #expect(Set(labels).count == labels.count)
    #expect(labels.allSatisfy { $0.count == 1 })
  }

  @Test(arguments: [
    (1, "1 min"), (59, "59 min"), (60, "1 h"), (84, "1 h 24 min"), (120, "2 h"), (720, "12 h"),
  ])
  func timeLeft(minutes: Int, expected: String) {
    #expect(timeLeftText(minutes: minutes) == expected)
  }
}
