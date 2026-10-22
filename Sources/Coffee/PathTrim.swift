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

extension NSBezierPath {
  /// The part of the path between two fractions of its length: 0 is its first point and 1 its
  /// last. Curves are cut exactly where the part starts and ends, so what's left is still made
  /// of curves and is drawn just as smoothly as the whole path. Lines stay lines.
  func trimmed(from start: Double, to end: Double) -> NSBezierPath {
    let result = NSBezierPath()
    result.lineWidth = lineWidth
    result.lineCapStyle = lineCapStyle
    result.lineJoinStyle = lineJoinStyle

    let segments = PathSegment.segments(of: self)
    let total = segments.reduce(0) { $0 + $1.length }
    let from = min(max(start, 0), 1) * total
    let to = min(max(end, 0), 1) * total
    guard total > 0, to - from > 1e-9 else { return result }

    var offset = 0.0
    var needsMove = true
    for segment in segments {
      defer { offset += segment.length }
      if segment.startsSubpath { needsMove = true }
      guard segment.length > 0, offset + segment.length > from, offset < to else { continue }

      let piece = segment.cut(
        from: segment.parameter(atLength: from - offset),
        to: segment.parameter(atLength: to - offset))
      if needsMove {
        result.move(to: piece.p0)
        needsMove = false
      }
      if segment.isLine {
        result.line(to: piece.p3)
      } else {
        result.curve(to: piece.p3, controlPoint1: piece.c1, controlPoint2: piece.c2)
      }
    }
    return result
  }

  /// Points along the path, `pointsPerCurve` for each curve and the ends of each line: a polygon
  /// close enough to the path to measure areas with.
  func polygon(pointsPerCurve: Int = 32) -> [NSPoint] {
    var points: [NSPoint] = []
    for segment in PathSegment.segments(of: self) {
      if points.isEmpty || segment.startsSubpath { points.append(segment.p0) }
      let steps = segment.isLine ? 1 : pointsPerCurve
      for step in 1...steps { points.append(segment.point(at: Double(step) / Double(steps))) }
    }
    if let first = points.first, let last = points.last,
      hypot(first.x - last.x, first.y - last.y) < 1e-9
    {
      points.removeLast()
    }
    return points
  }
}

/// One drawn piece of a path, as a cubic Bézier curve. A line is the straight curve between its
/// ends, and is drawn as a line again.
private struct PathSegment {
  var p0, c1, c2, p3: NSPoint
  var isLine: Bool
  /// Whether this segment begins a new subpath (it comes straight after a move).
  var startsSubpath: Bool
  /// Arc length at evenly spaced parameters 0, 1/n, ..., 1: the table behind `parameter(atLength:)`.
  private(set) var lengths: [Double] = []

  var length: Double { lengths.last ?? 0 }

  private static let samples = 64

  init(p0: NSPoint, c1: NSPoint, c2: NSPoint, p3: NSPoint, isLine: Bool, startsSubpath: Bool) {
    (self.p0, self.c1, self.c2, self.p3) = (p0, c1, c2, p3)
    self.isLine = isLine
    self.startsSubpath = startsSubpath
    var lengths = [0.0]
    var previous = p0
    for step in 1...Self.samples {
      let point = self.point(at: Double(step) / Double(Self.samples))
      lengths.append(lengths[step - 1] + hypot(point.x - previous.x, point.y - previous.y))
      previous = point
    }
    self.lengths = lengths
  }

  static func line(from a: NSPoint, to b: NSPoint, startsSubpath: Bool) -> PathSegment {
    PathSegment(
      p0: a, c1: mix(a, b, 1.0 / 3), c2: mix(a, b, 2.0 / 3), p3: b, isLine: true,
      startsSubpath: startsSubpath)
  }

  static func segments(of path: NSBezierPath) -> [PathSegment] {
    var segments: [PathSegment] = []
    var points = [NSPoint](repeating: .zero, count: 3)
    var current = NSPoint.zero
    var subpathStart = NSPoint.zero
    var afterMove = true
    for index in 0..<path.elementCount {
      switch path.element(at: index, associatedPoints: &points) {
      case .moveTo:
        current = points[0]
        subpathStart = current
        afterMove = true
      case .lineTo:
        segments.append(.line(from: current, to: points[0], startsSubpath: afterMove))
        current = points[0]
        afterMove = false
      case .cubicCurveTo:
        segments.append(
          PathSegment(
            p0: current, c1: points[0], c2: points[1], p3: points[2], isLine: false,
            startsSubpath: afterMove))
        current = points[2]
        afterMove = false
      case .quadraticCurveTo:
        // The same curve as a cubic: each control point two thirds of the way to the quadratic's.
        segments.append(
          PathSegment(
            p0: current, c1: mix(current, points[0], 2.0 / 3),
            c2: mix(points[1], points[0], 2.0 / 3),
            p3: points[1], isLine: false, startsSubpath: afterMove))
        current = points[1]
        afterMove = false
      case .closePath:
        segments.append(.line(from: current, to: subpathStart, startsSubpath: afterMove))
        current = subpathStart
        afterMove = false
      @unknown default:
        break
      }
    }
    return segments
  }

  func point(at t: Double) -> NSPoint {
    let u = 1 - t
    let (a, b, c, d) = (u * u * u, 3 * u * u * t, 3 * u * t * t, t * t * t)
    return NSPoint(
      x: a * p0.x + b * c1.x + c * c2.x + d * p3.x, y: a * p0.y + b * c1.y + c * c2.y + d * p3.y)
  }

  /// The curve parameter at which `length` of the segment has been drawn.
  func parameter(atLength length: Double) -> Double {
    guard length > 0 else { return 0 }
    guard length < self.length else { return 1 }
    let index = lengths.firstIndex { $0 >= length } ?? Self.samples
    let span = lengths[index] - lengths[index - 1]
    let fraction = span > 0 ? (length - lengths[index - 1]) / span : 0
    return (Double(index - 1) + fraction) / Double(Self.samples)
  }

  /// The part of this curve between parameters `t0` and `t1`, found by de Casteljau splitting.
  func cut(from t0: Double, to t1: Double) -> (p0: NSPoint, c1: NSPoint, c2: NSPoint, p3: NSPoint) {
    let head = split(p0, c1, c2, p3, at: t1).left
    let piece = t1 > 0 ? split(head.0, head.1, head.2, head.3, at: t0 / t1).right : head
    return (piece.0, piece.1, piece.2, piece.3)
  }

  private typealias Cubic = (NSPoint, NSPoint, NSPoint, NSPoint)

  private func split(_ a: NSPoint, _ b: NSPoint, _ c: NSPoint, _ d: NSPoint, at t: Double)
    -> (left: Cubic, right: Cubic)
  {
    let ab = Self.mix(a, b, t)
    let bc = Self.mix(b, c, t)
    let cd = Self.mix(c, d, t)
    let abc = Self.mix(ab, bc, t)
    let bcd = Self.mix(bc, cd, t)
    let middle = Self.mix(abc, bcd, t)
    return ((a, ab, abc, middle), (middle, bcd, cd, d))
  }

  private static func mix(_ a: NSPoint, _ b: NSPoint, _ t: Double) -> NSPoint {
    NSPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
  }
}
