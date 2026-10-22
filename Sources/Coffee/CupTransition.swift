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

/// What the menu bar cup shows at one moment.
struct CupFrame: Equatable {
  var level: Double
  /// The part of the steam curl that is showing.
  var steam: CupSteam
  var pour: CupPour? = nil
  /// How far the cup is tipped, in degrees; positive tips it to the left.
  var tilt: Double = 0
  /// Coffee falling from the lip of the tipped cup.
  var spill: CupSpill? = nil
}

/// The animation played on the cup when Coffee is turned on or off: the keyframes in
/// `CupAnimation`, blended smoothly. The power assertion doesn't wait for this: it is only what
/// the icon shows.
struct CupTransition: Equatable {
  /// `stopping` drains the cup (the timer ran out, or the Mac woke up); `spilling` tips it over
  /// (turned off by hand).
  enum Kind { case starting, stopping, spilling }

  let kind: Kind
  let startedAt: Date
  /// The coffee level the cup had when the transition began.
  let fromLevel: Double
  /// The part of the steam curl that was showing when a stopping transition began.
  let steam: CupSteam
  /// Spilling only: when coffee starts and stops pouring over the lip, in seconds from the start.
  private let pouring: ClosedRange<TimeInterval>?

  init(kind: Kind, startedAt: Date, fromLevel: Double, steam: CupSteam) {
    self.kind = kind
    self.startedAt = startedAt
    self.fromLevel = fromLevel
    self.steam = steam
    pouring = kind == .spilling ? Self.pouringTimes(spillingFrom: fromLevel) : nil
  }

  var poses: [CupPose] {
    switch kind {
    case .starting: CupAnimation.on
    case .stopping: CupAnimation.off
    case .spilling: CupAnimation.spill
    }
  }

  var duration: TimeInterval { Double(poses.count - 1) * CupAnimation.stepDuration }

  var end: Date { startedAt + duration }

  /// - Parameter target: Where a starting transition ends up: the cup's real level.
  func frame(at now: Date, level target: Double) -> CupFrame {
    let elapsed = now.timeIntervalSince(startedAt)
    let pose = CupAnimation.pose(in: poses, at: elapsed)
    switch kind {
    case .starting:
      return CupFrame(
        level: fromLevel + (target - fromLevel) * pose.coffee, steam: pose.steam, pour: pose.pour)
    case .stopping:
      // The curl shrinks from its bottom end towards its top end, wherever those were.
      let shrunk = CupSteam(
        start: steam.start + (steam.end - steam.start) * pose.steamShrink, end: steam.end)
      return CupFrame(level: fromLevel * pose.coffee, steam: shrunk, pour: pose.pour)
    case .spilling:
      let shrunk = CupSteam(
        start: steam.start + (steam.end - steam.start) * pose.steamShrink, end: steam.end)
      return CupFrame(
        level: Self.coffee(spillingFrom: fromLevel, at: elapsed), steam: shrunk, tilt: pose.tilt,
        spill: stream(at: elapsed))
    }
  }

  // MARK: - Spilling

  /// How much coffee a tipping cup still holds: no more than fits at the furthest it has tipped
  /// so far, so it only ever leaves over the rim, and none once the table says it has all gone.
  static func coffee(spillingFrom level: Double, at elapsed: TimeInterval) -> Double {
    let allowed = level * CupAnimation.pose(in: CupAnimation.spill, at: elapsed).coffee
    let fits = CupIcon.capacity(tilt: CupAnimation.peakTilt(in: CupAnimation.spill, at: elapsed))
    return min(allowed, fits)
  }

  /// When coffee first pours over the lip and when the last of it has gone, or nil if none does.
  private static func pouringTimes(spillingFrom level: Double) -> ClosedRange<TimeInterval>? {
    let duration = Double(CupAnimation.spill.count - 1) * CupAnimation.stepDuration
    let times = Array(stride(from: 0.0, through: duration, by: 0.005))
    guard let first = times.first(where: { coffee(spillingFrom: level, at: $0) < level - 0.001 })
    else { return nil }
    let remaining = coffee(spillingFrom: level, at: duration)
    let last =
      times.first { $0 >= first && coffee(spillingFrom: level, at: $0) <= remaining + 0.001 }
      ?? duration
    return first...last
  }

  /// The falling coffee: it grows down from the lip once pouring starts, and its top falls away
  /// once pouring stops.
  private func stream(at elapsed: TimeInterval) -> CupSpill? {
    guard let pouring else { return nil }
    func fallen(since time: TimeInterval) -> Double {
      min(max((elapsed - time) / CupAnimation.spillFall, 0), 1)
    }
    let (start, end) = (fallen(since: pouring.upperBound), fallen(since: pouring.lowerBound))
    return end > start ? CupSpill(start: start, end: end) : nil
  }
}
