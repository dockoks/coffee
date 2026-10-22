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

let oneHourInterval = TimeInterval(3600)  // Seconds

struct ActivationSpec: Equatable {
  let title: String
  let timeInterval: TimeInterval
  let label: String
}

enum ActivationSpecs: String, CaseIterable {
  case forever = "Forever"
  case quarterHour = "15 Minutes"
  case halfHour = "30 Minutes"
  case threeQuarterHours = "45 Minutes"
  case oneHour = "1 Hour"
  case oneAndHalfHours = "1.5 Hours"
  case twoHours = "2 Hours"
  case threeHours = "3 Hours"
  case fourHours = "4 Hours"
  case sixHours = "6 Hours"
  case eightHours = "8 Hours"
  case twelveHours = "12 Hours"

  static func spec(for title: String) -> ActivationSpec? {
    return self.init(rawValue: title)?.spec
  }

  var spec: ActivationSpec {
    ActivationSpec(title: rawValue, timeInterval: timeInterval, label: shortcut)
  }

  private var timeInterval: TimeInterval {
    switch self {
    case .forever: return 0
    case .quarterHour: return oneHourInterval / 4
    case .halfHour: return oneHourInterval / 2
    case .threeQuarterHours: return oneHourInterval * 3 / 4
    case .oneHour: return oneHourInterval
    case .oneAndHalfHours: return oneHourInterval * 3 / 2
    case .twoHours: return 2 * oneHourInterval
    case .threeHours: return 3 * oneHourInterval
    case .fourHours: return 4 * oneHourInterval
    case .sixHours: return 6 * oneHourInterval
    case .eightHours: return 8 * oneHourInterval
    case .twelveHours: return 12 * oneHourInterval
    }
  }

  /// The menu key equivalent, or "" for presets without one.
  private var shortcut: String {
    switch self {
    case .forever: return "0"
    case .oneHour: return "1"
    case .twoHours: return "2"
    case .fourHours: return "4"
    case .eightHours: return "8"
    default: return ""
    }
  }
}

extension ActivationSpec {
  /// How full the cup is after `elapsed` seconds, from 1 (just poured) to 0 (time's up).
  /// A spec without a time limit stays full.
  func coffeeLevel(elapsed: TimeInterval) -> Double {
    guard timeInterval > 0 else { return 1 }
    return min(max(1 - elapsed / timeInterval, 0), 1)
  }
}

/// "1 h 24 min", "2 h" or "24 min".
func timeLeftText(minutes: Int) -> String {
  let (hours, rest) = (minutes / 60, minutes % 60)
  switch (hours, rest) {
  case (0, _): return "\(rest) min"
  case (_, 0): return "\(hours) h"
  default: return "\(hours) h \(rest) min"
  }
}
