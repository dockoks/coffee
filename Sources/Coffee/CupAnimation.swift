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

/// A stream of coffee: a 1 pt vertical line down the middle of the cup, between two heights
/// (in the 22 pt artwork space, y pointing down).
struct CupPour: Equatable {
  var top: Double
  var bottom: Double
}

/// Coffee falling from the lip of a tipped cup: the part of the fall, from the lip (0) down to the
/// bottom of the icon (1), that has coffee in it. It grows down from the lip when pouring starts
/// and its top falls away when pouring stops.
struct CupSpill: Equatable {
  var start: Double
  var end: Double
}

/// The part of the steam curl that is showing, as positions along the curl from its bottom point
/// (0) to its very top (1). The full curl is 0...1; a curl growing from the bottom is 0...0.4; one
/// shrinking away towards the top is 0.6...1.
struct CupSteam: Equatable {
  var start: Double
  var end: Double

  static let hidden = CupSteam(start: 0, end: 0)
  static let full = CupSteam(start: 0, end: 1)

  var length: Double { max(end - start, 0) }
}

/// A keyframe of the start or stop animation.
struct CupPose: Equatable {
  /// How far the coffee level has moved: when starting, from where the cup was (0) to where it
  /// ends up (1); when stopping, from where the cup was (1) down to empty (0).
  var coffee: Double
  var pour: CupPour? = nil
  /// Starting only: the part of the steam curl that is showing.
  var steam: CupSteam = .hidden
  /// Stopping only: how far the steam showing at that moment has shrunk away, its bottom end
  /// travelling to its top end (0 = as it was, 1 = gone).
  var steamShrink: Double = 0
  /// How far the cup is tipped, in degrees: positive tips its top to the left, away from the
  /// handle. Its coffee stays level and pours over the rim when it no longer fits.
  var tilt: Double = 0
}

/// The start and stop animations as keyframes, one every `stepDuration`. The app blends smoothly
/// from each keyframe to the next, so nothing moves in steps. The numbers come from the frames
/// in the Figma template sheet (`on-0` ... `on-11`, `off-0` ... `off-7`, `steam-0` ... `steam-11`);
/// update them when the art changes.
enum CupAnimation {
  /// The time between keyframes.
  static let stepDuration: TimeInterval = 0.1

  /// How often the icon is redrawn while something is moving.
  static let tick: Duration = .milliseconds(50)

  /// Turn on: a stream pours in, the coffee rises while it runs, the stream shrinks away from
  /// the top, then the steam curl grows from its bottom point. The last pose is the live cup,
  /// which takes over from there.
  static let on: [CupPose] = [
    CupPose(coffee: 0, pour: CupPour(top: 3, bottom: 5)),
    CupPose(coffee: 0, pour: CupPour(top: 3, bottom: 6)),
    CupPose(coffee: 0, pour: CupPour(top: 3, bottom: 7)),
    CupPose(coffee: 0.1, pour: CupPour(top: 3, bottom: 7)),
    CupPose(coffee: 0.35, pour: CupPour(top: 3, bottom: 7)),
    CupPose(coffee: 0.65, pour: CupPour(top: 3, bottom: 7)),
    CupPose(coffee: 0.9, pour: CupPour(top: 3, bottom: 7)),
    CupPose(coffee: 1, pour: CupPour(top: 5, bottom: 7)),
    CupPose(coffee: 1, pour: CupPour(top: 6, bottom: 7)),
    CupPose(coffee: 1),
    CupPose(coffee: 1, steam: CupSteam(start: 0, end: 0.33)),
    CupPose(coffee: 1, steam: CupSteam(start: 0, end: 0.67)),
    CupPose(coffee: 1, steam: .full),  // hand-over: the steam loop starts here
  ]

  /// Turn off: the steam shrinks away from its bottom point to its top, then the coffee drains.
  /// The last pose is the empty cup.
  static let off: [CupPose] = [
    CupPose(coffee: 1, steamShrink: 0),
    CupPose(coffee: 1, steamShrink: 0.33),
    CupPose(coffee: 1, steamShrink: 0.67),
    CupPose(coffee: 1, steamShrink: 1),
    CupPose(coffee: 0.9, steamShrink: 1),
    CupPose(coffee: 0.65, steamShrink: 1),
    CupPose(coffee: 0.35, steamShrink: 1),
    CupPose(coffee: 0.1, steamShrink: 1),
    CupPose(coffee: 0, steamShrink: 1),
  ]

  /// Turned off by hand: the steam pulls back, the cup tips over to the left until the coffee has
  /// poured out over its rim, then it swings back upright with a little wobble. `coffee` is how
  /// much of the coffee may still be in the cup; tipping pours out whatever no longer fits.
  static let spill: [CupPose] = [
    CupPose(coffee: 1, tilt: 0),
    CupPose(coffee: 1, steamShrink: 0.5, tilt: 6),
    CupPose(coffee: 1, steamShrink: 1, tilt: 18),
    CupPose(coffee: 1, steamShrink: 1, tilt: 34),
    CupPose(coffee: 1, steamShrink: 1, tilt: 52),
    CupPose(coffee: 1, steamShrink: 1, tilt: 68),
    CupPose(coffee: 1, steamShrink: 1, tilt: 80),
    CupPose(coffee: 0.5, steamShrink: 1, tilt: 85),
    CupPose(coffee: 0, steamShrink: 1, tilt: 85),  // the last drops are out
    CupPose(coffee: 0, steamShrink: 1, tilt: 70),
    CupPose(coffee: 0, steamShrink: 1, tilt: 45),
    CupPose(coffee: 0, steamShrink: 1, tilt: 18),
    CupPose(coffee: 0, steamShrink: 1, tilt: -6),  // the wobble
    CupPose(coffee: 0, steamShrink: 1, tilt: 2),
    CupPose(coffee: 0, steamShrink: 1, tilt: 0),
  ]

  /// How long spilled coffee takes to fall from the lip to the bottom of the icon.
  static let spillFall: TimeInterval = 0.15

  /// The steam loop, one keyframe every `steamLoopStep`; it repeats while Coffee is brewing. The
  /// full curl holds, then shrinks away from its bottom point to its top, then grows again from
  /// the bottom. Between the last shrunk and the first grown keyframe nothing is showing, so
  /// blending them shows nothing.
  static let steamLoop: [CupSteam] = [
    .full,
    .full,
    CupSteam(start: 0.25, end: 1),
    CupSteam(start: 0.5, end: 1),
    CupSteam(start: 0.75, end: 1),
    CupSteam(start: 1, end: 1),
    .hidden,
    CupSteam(start: 0, end: 0.35),
    CupSteam(start: 0, end: 0.7),
    .full,
    .full,
    .full,
  ]
  static let steamLoopStep: TimeInterval = 0.2

  /// The steam `elapsed` seconds into the loop, blended between its keyframes.
  static func steam(at elapsed: TimeInterval) -> CupSteam {
    let count = steamLoop.count
    let position = max(elapsed, 0) / steamLoopStep
    let index = Int(position) % count
    let fraction = position - position.rounded(.down)
    return blend(steamLoop[index], steamLoop[(index + 1) % count], fraction)
  }

  /// The pose `elapsed` seconds into `poses`, blended between the two keyframes around it.
  /// Past the last keyframe it stays on the last pose.
  static func pose(in poses: [CupPose], at elapsed: TimeInterval) -> CupPose {
    let position = min(max(elapsed / stepDuration, 0), Double(poses.count - 1))
    let index = min(Int(position), poses.count - 2)
    let fraction = position - Double(index)
    // `Date` arithmetic isn't exact: a time that is on a keyframe to within rounding error is on it.
    if fraction < 1e-9 { return poses[index] }
    if fraction > 1 - 1e-9 { return poses[index + 1] }
    let (a, b) = (poses[index], poses[index + 1])
    return CupPose(
      coffee: lerp(a.coffee, b.coffee, fraction),
      pour: blend(a.pour, b.pour, fraction),
      steam: blend(a.steam, b.steam, fraction),
      steamShrink: lerp(a.steamShrink, b.steamShrink, fraction),
      tilt: lerp(a.tilt, b.tilt, fraction))
  }

  /// The furthest the cup has tipped in `poses` by `elapsed` seconds in.
  static func peakTilt(in poses: [CupPose], at elapsed: TimeInterval) -> Double {
    let passed = poses.prefix(Int(max(elapsed, 0) / stepDuration + 1e-6) + 1).map(\.tilt)
    return max(passed.max() ?? 0, pose(in: poses, at: elapsed).tilt)
  }

  private static func lerp(_ a: Double, _ b: Double, _ fraction: Double) -> Double {
    a + (b - a) * fraction
  }

  private static func blend(_ a: CupSteam, _ b: CupSteam, _ fraction: Double) -> CupSteam {
    CupSteam(start: lerp(a.start, b.start, fraction), end: lerp(a.end, b.end, fraction))
  }

  /// A stream that appears or vanishes grows from, or shrinks into, its lower end.
  private static func blend(_ a: CupPour?, _ b: CupPour?, _ fraction: Double) -> CupPour? {
    let blended: CupPour?
    switch (a, b) {
    case (nil, nil):
      blended = nil
    case (let a?, let b?):
      blended = CupPour(
        top: lerp(a.top, b.top, fraction), bottom: lerp(a.bottom, b.bottom, fraction))
    case (let a?, nil):
      blended = CupPour(top: lerp(a.top, a.bottom, fraction), bottom: a.bottom)
    case (nil, let b?):
      blended = CupPour(top: lerp(b.bottom, b.top, fraction), bottom: b.bottom)
    }
    // Too short to see: it has vanished.
    guard let blended, blended.bottom - blended.top > 0.05 else { return nil }
    return blended
  }
}
