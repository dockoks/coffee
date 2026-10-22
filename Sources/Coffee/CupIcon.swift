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

/// How many steam curls rise from the cup: all three from the design, or only the one in the middle.
enum SteamCurls: String, CaseIterable {
  case one
  case three

  var title: String {
    switch self {
    case .one: "One Curl"
    case .three: "Three Curls"
    }
  }
}

/// Draws the menu bar cup: a coffee level inside the cup and, while brewing, animated steam above it.
///
/// The artwork lives in `Design/menubar/*.svg`; the path data below is copied from those files.
/// Everything is drawn in the SVGs' 22x22 space with the y axis pointing down.
enum CupIcon {
  static let size = NSSize(width: 22, height: 22)

  private enum Art {
    // cup.svg, split into the bowl (closed) and the handle (open).
    static let bowl = "M16 9H4C4 13.5 4 18.5 10 18.5C16 18.5 16 13.5 16 9Z"
    static let handle = "M16 9C17.5 9 18.5 9.10798 18.5 10.5C18.5 13 17.9451 15.8925 15.5 15.5"
    // steam.svg: three curls side by side, from the Figma frame steam-0: a taller one in the
    // middle and a smaller one either side. Each starts at its bottom point and ends at its top.
    static let steam = [
      "M7.5 7.5C7.5 7.5 7 7.1544 7 6.5C7 5.8456 7.85 5.759 7.85 5C7.85 4.241 7.5 4.5 7.5 3.5",
      "M10 7.5C10 7.5 9.5 7 9.5 6.5C9.5 5.5 10.5 5.75 10.5 4.75C10.5 4 10 4 10 3",
      "M12.5 7.5C12.5 7.5 12 7.1544 12 6.5C12 5.8456 12.85 5.759 12.85 5C12.85 4.241 12.5 4.5 12.5 3.5",
    ]
    /// The curl kept when only one is drawn.
    static let middleCurl = 1

    static let pourX: CGFloat = 10
    /// The rim's corners: tipped, the lower one is the lip that coffee pours over.
    static let rimLeft = NSPoint(x: 4, y: 9)
    static let rimRight = NSPoint(x: 16, y: 9)
    /// The cup tips about the middle of its bowl, which keeps it inside the icon at any angle.
    static let tiltPivot = NSPoint(x: 10, y: 13.75)
    /// Spilled coffee falls to just past the bottom of the icon.
    static let spillBottom: CGFloat = 22.5

    /// The liquid fills the bowl between these heights.
    static let coffeeBottom: CGFloat = 18.5
    static let coffeeTopWhenFull: CGFloat = 10.5
    static let outlineWidth: CGFloat = 1
    /// Clear space between the coffee and the outline, on each side.
    static let coffeeGap: CGFloat = 1
  }

  /// - Parameters:
  ///   - level: How much coffee is in the cup, as the level it reaches standing upright; clamped
  ///     to 0...1.
  ///   - steam: The part of the steam curl to draw, from its bottom point to its top.
  ///   - pour: A stream of coffee down the middle of the cup, or nil for none.
  ///   - tilt: How far the cup is tipped, in degrees; positive tips it to the left. The coffee
  ///     stays level and never stands above the lip.
  ///   - spill: Coffee falling from the lip, or nil for none.
  ///   - curls: How many steam curls to draw.
  static func image(
    level: Double, steam: CupSteam, pour: CupPour? = nil, tilt: Double = 0, spill: CupSpill? = nil,
    curls: SteamCurls = .three
  ) -> NSImage {
    let level = min(max(level, 0), 1)
    let image = NSImage(size: size, flipped: true) { _ in
      drawCoffee(level: level, tilt: tilt)
      NSColor.black.set()
      for path in outlinePaths(tilt: tilt) { path.stroke() }
      if let pour { pourPath(pour).stroke() }
      if let spill, let path = spillPath(spill, tilt: tilt) { path.stroke() }
      if let path = steamPath(steam, curls: curls) { path.stroke() }
      return true
    }
    image.isTemplate = true
    return image
  }

  /// One shape of the icon, in the artwork's 22 pt space with y pointing down. A filled layer is
  /// filled black; any other is stroked black, 1 pt, with round caps and joins.
  struct Layer {
    let name: String
    let path: CGPath
    let isFilled: Bool
  }

  /// The icon's shapes as vector paths, for design tools: drawn in order they give the same
  /// picture as `image`. Shapes that aren't showing are left out.
  static func layers(
    level: Double, steam: CupSteam, pour: CupPour? = nil, tilt: Double = 0, spill: CupSpill? = nil,
    curls: SteamCurls = .three
  ) -> [Layer] {
    var layers: [Layer] = []
    if let coffee = coffeePath(level: min(max(level, 0), 1), tilt: tilt) {
      layers.append(Layer(name: "coffee", path: coffee, isFilled: true))
    }
    let cup = CGMutablePath()
    for path in outlinePaths(tilt: tilt) { cup.addPath(path.cgPath) }
    layers.append(Layer(name: "cup", path: cup, isFilled: false))
    if let pour { layers.append(Layer(name: "pour", path: pourPath(pour).cgPath, isFilled: false)) }
    if let spill, let path = spillPath(spill, tilt: tilt) {
      layers.append(Layer(name: "spill", path: path.cgPath, isFilled: false))
    }
    if let path = steamPath(steam, curls: curls) {
      layers.append(Layer(name: "steam", path: path.cgPath, isFilled: false))
    }
    return layers
  }

  // MARK: - Drawing

  private static func stroked(_ d: String) -> NSBezierPath {
    let path = SVGPath.parse(d)!
    path.lineWidth = Art.outlineWidth
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    return path
  }

  /// The cup's outline: the bowl and the handle, tipped.
  private static func outlinePaths(tilt: Double) -> [NSBezierPath] {
    [Art.bowl, Art.handle].map { d in
      let path = stroked(d)
      path.transform(using: tipping(tilt))
      return path
    }
  }

  /// The stream sits over the cup, down its centre line (x = 10 in the artwork).
  private static func pourPath(_ pour: CupPour) -> NSBezierPath {
    let stream = NSBezierPath()
    stream.lineWidth = Art.outlineWidth
    stream.lineCapStyle = .round
    stream.move(to: NSPoint(x: Art.pourX, y: pour.top))
    stream.line(to: NSPoint(x: Art.pourX, y: pour.bottom))
    return stream
  }

  /// The coffee: the tipped bowl below the coffee's surface, less a margin around the outline.
  private static func coffeePath(level: Double, tilt: Double) -> CGPath? {
    guard level > 0 else { return nil }
    let bowl = SVGPath.parse(Art.bowl)!
    bowl.transform(using: tipping(tilt))
    let top = surface(level: level, tilt: tilt)
    let below = CGPath(
      rect: CGRect(x: 0, y: top, width: size.width, height: size.height - top), transform: nil)
    let margin = bowl.cgPath.copy(
      strokingWithWidth: Art.outlineWidth + 2 * Art.coffeeGap, lineCap: .round, lineJoin: .round,
      miterLimit: 10)
    // Subtracting by area keeps the margin whole at the rim's sharp corners, where its inner
    // edge crosses itself.
    return bowl.cgPath.intersection(below).subtracting(margin)
  }

  private static func drawCoffee(level: Double, tilt: Double) {
    guard let coffee = coffeePath(level: level, tilt: tilt),
      let context = NSGraphicsContext.current?.cgContext
    else { return }
    context.addPath(coffee)
    context.setFillColor(.black)
    context.fillPath()
  }

  /// Coffee falling straight down from just outside the lip.
  private static func spillPath(_ spill: CupSpill, tilt: Double) -> NSBezierPath? {
    let start = min(max(spill.start, 0), 1)
    let end = min(max(spill.end, 0), 1)
    guard end - start > 0.002 else { return nil }
    let lip = lip(tilt: tilt)
    let x = lip.x - Art.outlineWidth / 2 - 0.1
    let fall = Art.spillBottom - lip.y
    let stream = NSBezierPath()
    stream.lineWidth = Art.outlineWidth
    stream.lineCapStyle = .round
    stream.move(to: NSPoint(x: x, y: lip.y + fall * start))
    stream.line(to: NSPoint(x: x, y: lip.y + fall * end))
    return stream
  }

  /// The part of each steam curl between two positions along it, 0 being its bottom point and 1
  /// its very top. The curls stay exactly where steam.svg draws them; they only grow and shrink.
  private static func steamPath(_ steam: CupSteam, curls: SteamCurls) -> NSBezierPath? {
    let start = min(max(steam.start, 0), 1)
    let end = min(max(steam.end, 0), 1)
    guard end - start > 0.002 else { return nil }
    // Each curl grows and shrinks along its own length, all three in step.
    let parts = NSBezierPath()
    parts.lineWidth = Art.outlineWidth
    parts.lineCapStyle = .round
    parts.lineJoinStyle = .round
    let drawn = curls == .one ? [Art.steam[Art.middleCurl]] : Art.steam
    for curl in drawn { parts.append(stroked(curl).trimmed(from: start, to: end)) }
    return parts.isEmpty ? nil : parts
  }

  // MARK: - Tipping

  /// How much coffee the cup holds when tipped `tilt` degrees, as the level that coffee reaches
  /// standing upright. Upright the cup holds a little more than a full cup: up to its rim.
  /// The bowl is symmetric, so tipping it either way holds the same.
  static func capacity(tilt: Double) -> Double {
    let degrees = min(abs(tilt), 180)
    let index = min(Int(degrees), 179)
    let fraction = degrees - Double(index)
    let (a, b) = (Geometry.capacities[index], Geometry.capacities[index + 1])
    return a + (b - a) * fraction
  }

  private enum Geometry {
    /// The bowl as a polygon, for measuring how much coffee it holds.
    static let bowl: [NSPoint] = SVGPath.parse(Art.bowl)!.polygon()
    /// The upright level at which coffee reaches the rim.
    static let rimLevel = Double(
      (Art.coffeeBottom - Art.rimLeft.y) / (Art.coffeeBottom - Art.coffeeTopWhenFull))
    /// The coffee in the upright cup at `areaSteps + 1` evenly spaced levels from empty to the
    /// rim, for turning an amount of coffee back into a level.
    static let areaSteps = 400
    static let uprightAreas: [Double] = (0...areaSteps).map {
      uprightArea(rimLevel * Double($0) / Double(areaSteps))
    }
    /// What the cup holds at 0°, 1°, ..., 180°, measured once.
    static let capacities: [Double] = (0...180).map {
      let tilt = Double($0)
      return uprightLevel(holding: area(of: tipped(bowl, tilt: tilt), below: lip(tilt: tilt).y))
    }
  }

  /// Rotates the artwork the way the cup tips: positive degrees tip its top to the left. (With y
  /// pointing down, that is a negative angle.)
  private static func tipping(_ tilt: Double) -> AffineTransform {
    let angle = -tilt * .pi / 180
    let (c, s) = (cos(angle), sin(angle))
    let p = Art.tiltPivot
    return AffineTransform(
      m11: c, m12: s, m21: -s, m22: c, tX: p.x - p.x * c + p.y * s, tY: p.y - p.x * s - p.y * c)
  }

  private static func tipped(_ points: [NSPoint], tilt: Double) -> [NSPoint] {
    let transform = tipping(tilt)
    return points.map { transform.transform($0) }
  }

  /// The lowest point of the tipped rim: where coffee pours over.
  private static func lip(tilt: Double) -> NSPoint {
    let corners = tipped([Art.rimLeft, Art.rimRight], tilt: tilt)
    return corners[0].y >= corners[1].y ? corners[0] : corners[1]
  }

  /// The height of the coffee's surface in a cup tipped `tilt` degrees holding as much coffee as
  /// an upright cup at `level`. The surface stays level, and never stands above the lip.
  private static func surface(level: Double, tilt: Double) -> CGFloat {
    guard tilt != 0 else { return uprightSurface(level) }
    let bowl = tipped(Geometry.bowl, tilt: tilt)
    let target = uprightArea(level)
    var (top, bottom) = (bowl.map(\.y).min()!, bowl.map(\.y).max()!)
    for _ in 0..<40 {
      let middle = (top + bottom) / 2
      if area(of: bowl, below: middle) > target { top = middle } else { bottom = middle }
    }
    return max(top, lip(tilt: tilt).y)
  }

  private static func uprightSurface(_ level: Double) -> CGFloat {
    Art.coffeeBottom - (Art.coffeeBottom - Art.coffeeTopWhenFull) * level
  }

  private static func uprightArea(_ level: Double) -> Double {
    area(of: Geometry.bowl, below: uprightSurface(level))
  }

  /// The upright level that holds `area` of coffee.
  private static func uprightLevel(holding area: Double) -> Double {
    let areas = Geometry.uprightAreas
    guard area > 0 else { return 0 }
    guard area < areas[areas.count - 1] else { return Geometry.rimLevel }
    let index = areas.firstIndex { $0 >= area }!
    let span = areas[index] - areas[index - 1]
    let fraction = span > 0 ? (area - areas[index - 1]) / span : 0
    return Geometry.rimLevel * (Double(index - 1) + fraction) / Double(Geometry.areaSteps)
  }

  /// The area of the part of `polygon` below the height `y` (y points down).
  private static func area(of polygon: [NSPoint], below y: CGFloat) -> Double {
    var part: [NSPoint] = []
    for (a, b) in zip(polygon, polygon.dropFirst() + polygon.prefix(1)) {
      let (aBelow, bBelow) = (a.y >= y, b.y >= y)
      if aBelow { part.append(a) }
      if aBelow != bBelow {
        let t = (y - a.y) / (b.y - a.y)
        part.append(NSPoint(x: a.x + (b.x - a.x) * t, y: y))
      }
    }
    guard part.count >= 3 else { return 0 }
    var twice: Double = 0
    for (a, b) in zip(part, part.dropFirst() + part.prefix(1)) { twice += a.x * b.y - b.x * a.y }
    return abs(twice) / 2
  }
}
