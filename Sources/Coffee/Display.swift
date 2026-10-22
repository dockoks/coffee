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
import os

enum Display {
  /// Puts the displays to sleep right away, as if the idle timeout had just expired.
  /// Returns true when the request was accepted.
  ///
  /// This runs `pmset displaysleepnow`: setting `IORequestIdle` on `IODisplayWrangler` is
  /// accepted from the sandbox but doesn't do anything on Apple Silicon.
  @MainActor
  static func sleepNow() -> Bool {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
    process.arguments = ["displaysleepnow"]

    do {
      try process.run()
    } catch {
      os_log("Couldn't run pmset: %{public}@", error.localizedDescription)
      return false
    }
    process.waitUntilExit()

    if process.terminationStatus != 0 {
      os_log("pmset displaysleepnow failed with status %d", process.terminationStatus)
    }
    return process.terminationStatus == 0
  }
}
