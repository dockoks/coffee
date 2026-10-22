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
import Testing

@testable import Coffee

struct PathTrimTests {
  let curl = SVGPath.parse("M10 7C10 7 9 6.8 9 6C9 5 10.5 5.5 10.5 4.5C10.5 3.87197 10 4 10 3")!

  func close(_ a: CGFloat, _ b: CGFloat, _ tolerance: CGFloat = 0.01) -> Bool {
    abs(a - b) < tolerance
  }

  func close(_ a: NSPoint, _ b: NSPoint, _ tolerance: CGFloat = 0.01) -> Bool {
    close(a.x, b.x, tolerance) && close(a.y, b.y, tolerance)
  }

  /// Each element of the path: its type and points.
  func elements(_ path: NSBezierPath) -> [(NSBezierPath.ElementType, [NSPoint])] {
    var points = [NSPoint](repeating: .zero, count: 3)
    return (0..<path.elementCount).map { index in
      let type = path.element(at: index, associatedPoints: &points)
      return (type, type == .cubicCurveTo ? Array(points) : [points[0]])
    }
  }

  /// The path's length, measured finely enough to stand in for the exact value.
  func length(_ path: NSBezierPath) -> CGFloat {
    var total: CGFloat = 0
    var current = NSPoint.zero
    for (type, points) in elements(path) {
      switch type {
      case .moveTo:
        current = points[0]
      case .lineTo:
        total += hypot(points[0].x - current.x, points[0].y - current.y)
        current = points[0]
      case .cubicCurveTo:
        var previous = current
        for step in 1...2000 {
          let t = CGFloat(step) / 2000
          let u = 1 - t
          let a = u * u * u
          let b = 3 * u * u * t
          let c = 3 * u * t * t
          let d = t * t * t
          let point = NSPoint(
            x: a * current.x + b * points[0].x + c * points[1].x + d * points[2].x,
            y: a * current.y + b * points[0].y + c * points[1].y + d * points[2].y)
          total += hypot(point.x - previous.x, point.y - previous.y)
          previous = point
        }
        current = points[2]
      default:
        break
      }
    }
    return total
  }

  func first(_ path: NSBezierPath) -> NSPoint { elements(path).first!.1[0] }
  func last(_ path: NSBezierPath) -> NSPoint { elements(path).last!.1.last! }

  // MARK: - Smoothness

  @Test func curvesStayCurves() {
    // A trimmed curl is still made of curves, never chopped into straight lines.
    for (start, end) in [(0.0, 1.0), (0.2, 0.7), (0.0, 0.3), (0.6, 1.0)] {
      let types = elements(curl.trimmed(from: start, to: end)).map(\.0)
      #expect(types.first == .moveTo)
      #expect(types.dropFirst().allSatisfy { $0 == .cubicCurveTo }, "trimmed \(start)...\(end)")
      #expect(types.count <= elements(curl).count)
    }
  }

  @Test func theWholeCurveIsTheOriginal() {
    let whole = elements(curl.trimmed(from: 0, to: 1))
    let original = elements(curl)
    #expect(whole.count == original.count)
    for (a, b) in zip(whole, original) {
      #expect(a.0 == b.0)
      #expect(zip(a.1, b.1).allSatisfy { close($0, $1, 0.0001) })
    }
  }

  // MARK: - Positions along the curve

  @Test func positionsAreMeasuredAlongTheCurve() {
    let total = length(curl)
    #expect(close(length(curl.trimmed(from: 0, to: 0.5)), total / 2, total * 0.01))
    #expect(close(length(curl.trimmed(from: 0.5, to: 1)), total / 2, total * 0.01))
    #expect(close(length(curl.trimmed(from: 0.2, to: 0.45)), total * 0.25, total * 0.01))
  }

  @Test func itStartsAtTheBottomPointAndEndsAtTheTop() {
    #expect(close(first(curl.trimmed(from: 0, to: 0.3)), NSPoint(x: 10, y: 7)))
    #expect(close(last(curl.trimmed(from: 0.7, to: 1)), NSPoint(x: 10, y: 3)))
  }

  @Test func neighbouringPiecesMeet() {
    #expect(close(last(curl.trimmed(from: 0, to: 0.4)), first(curl.trimmed(from: 0.4, to: 1))))
    #expect(
      close(last(curl.trimmed(from: 0.1, to: 0.73)), first(curl.trimmed(from: 0.73, to: 0.9))))
  }

  @Test func linesStayLines() throws {
    let line = try #require(SVGPath.parse("M0 0 L10 0"))
    let part = line.trimmed(from: 0.2, to: 0.7)
    #expect(elements(part).map(\.0) == [.moveTo, .lineTo])
    #expect(close(part.bounds.minX, 2) && close(part.bounds.maxX, 7))
  }

  @Test func lengthIsSharedAcrossSegments() throws {
    // 10 along, then 30 up: a quarter of the length is the whole first leg.
    let corner = try #require(SVGPath.parse("M0 0 L10 0 L10 30"))
    let quarter = corner.trimmed(from: 0, to: 0.25)
    #expect(close(quarter.bounds.maxX, 10) && close(quarter.bounds.maxY, 0))
    #expect(close(corner.trimmed(from: 0, to: 0.5).bounds.maxY, 10))
  }

  // MARK: - Edges

  @Test func anEmptyRangeIsAnEmptyPath() {
    #expect(curl.trimmed(from: 0.5, to: 0.5).isEmpty)
    #expect(curl.trimmed(from: 0.8, to: 0.2).isEmpty)
    #expect(curl.trimmed(from: 2, to: 3).isEmpty)
  }

  @Test func outOfRangeValuesAreClamped() {
    let all = curl.trimmed(from: -1, to: 5)
    #expect(close(first(all), NSPoint(x: 10, y: 7)) && close(last(all), NSPoint(x: 10, y: 3)))
  }

  @Test func theStrokeStyleIsKept() {
    curl.lineWidth = 1.5
    curl.lineCapStyle = .round
    let part = curl.trimmed(from: 0.1, to: 0.9)
    #expect(part.lineWidth == 1.5 && part.lineCapStyle == .round)
  }
}
