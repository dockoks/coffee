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
import IOKit.pwr_mgt
import Testing

@testable import Coffee

struct PowerAssertionTests {
  /// The assertion this process holds with the given name, if any.
  func heldAssertion(named name: String) -> [String: Any]? {
    var byProcess: Unmanaged<CFDictionary>?
    guard IOPMCopyAssertionsByProcess(&byProcess) == kIOReturnSuccess,
      let table = byProcess?.takeRetainedValue() as? [NSNumber: [[String: Any]]]
    else { return nil }
    return table[NSNumber(value: getpid())]?.first { $0["AssertName"] as? String == name }
  }

  @Test(arguments: [Assertion.NoDisplaySleep, .PreventUserIdleSystemSleep])
  func assertionIsHeldUntilReleased(type: Assertion) {
    let name = "CoffeeTests-\(UUID())"
    var assertion: PowerAssertion? = PowerAssertion(named: name, type: type)
    #expect(assertion?.type == type)

    // The system reports the display assertion under its modern name.
    let accepted =
      type == .NoDisplaySleep ? [type.rawValue, "PreventUserIdleDisplaySleep"] : [type.rawValue]
    let heldType = heldAssertion(named: name)?["AssertType"] as? String
    #expect(heldType.map(accepted.contains) == true)

    assertion = nil
    #expect(heldAssertion(named: name) == nil)
  }
}
