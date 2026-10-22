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

import IOKit.pwr_mgt
import os

// These are seemingly not exposed to Swift
enum Assertion: String {
  /// The Mac and its screen stay awake.
  case NoDisplaySleep = "NoDisplaySleepAssertion"
  /// The Mac stays awake, but the screen may turn off.
  case PreventUserIdleSystemSleep = "PreventUserIdleSystemSleep"
}

// This is seemingly not exposed to Swift
enum AssertionLevel: UInt32 {
  case off = 0
  case on = 255
}

class PowerAssertion {
  let type: Assertion
  var assertion: IOPMAssertionID = 0

  init(named name: String, type: Assertion) {
    self.type = type
    let ret = IOPMAssertionCreateWithName(
      type.rawValue as CFString, AssertionLevel.on.rawValue, name as CFString,
      &assertion)

    if ret != kIOReturnSuccess {
      os_log("Couldn't grab the power assertion")
    }
  }

  deinit {
    let ret = IOPMAssertionRelease(assertion)

    if ret != kIOReturnSuccess {
      os_log("Couldn't release the power assertion")
    }
  }
}
