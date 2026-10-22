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

/// Turns the `d` attribute of an SVG `<path>` into an `NSBezierPath`.
///
/// Supports `M L H V C Z` in absolute and relative form, which covers what vector editors export
/// for simple line art. Anything else (arcs, quadratics, ...) makes `parse` return nil. In
/// SVG space the y axis points down, so draw into a flipped context.
enum SVGPath {
  static func parse(_ d: String) -> NSBezierPath? {
    guard let tokens = tokenize(d) else { return nil }

    let path = NSBezierPath()
    var current = NSPoint.zero
    var subpathStart = NSPoint.zero
    var command: Character?
    var hasMoved = false
    var index = 0

    func point(_ x: Double, _ y: Double, relative: Bool) -> NSPoint {
      relative ? NSPoint(x: current.x + x, y: current.y + y) : NSPoint(x: x, y: y)
    }

    while index < tokens.count {
      if case .command(let letter) = tokens[index] {
        index += 1
        if letter == "Z" || letter == "z" {
          guard hasMoved else { return nil }
          path.close()
          current = subpathStart
          command = nil
          continue
        }
        command = letter
      }

      guard let letter = command, let arity = arity(of: letter) else { return nil }
      var args: [Double] = []
      while args.count < arity, index < tokens.count, case .number(let value) = tokens[index] {
        args.append(value)
        index += 1
      }
      guard args.count == arity else { return nil }

      let relative = letter.isLowercase
      switch letter.uppercased() {
      case "M":
        current = point(args[0], args[1], relative: relative)
        subpathStart = current
        path.move(to: current)
        hasMoved = true
        command = relative ? "l" : "L"  // further pairs are implicit line-tos
      case "L":
        guard hasMoved else { return nil }
        current = point(args[0], args[1], relative: relative)
        path.line(to: current)
      case "H":
        guard hasMoved else { return nil }
        current = NSPoint(x: relative ? current.x + args[0] : args[0], y: current.y)
        path.line(to: current)
      case "V":
        guard hasMoved else { return nil }
        current = NSPoint(x: current.x, y: relative ? current.y + args[0] : args[0])
        path.line(to: current)
      case "C":
        guard hasMoved else { return nil }
        let control1 = point(args[0], args[1], relative: relative)
        let control2 = point(args[2], args[3], relative: relative)
        let end = point(args[4], args[5], relative: relative)
        path.curve(to: end, controlPoint1: control1, controlPoint2: control2)
        current = end
      default:
        return nil
      }
    }

    return path.elementCount > 0 ? path : nil
  }

  // MARK: - Tokens

  private enum Token {
    case command(Character)
    case number(Double)
  }

  private static func arity(of command: Character) -> Int? {
    switch command.uppercased() {
    case "M", "L": return 2
    case "H", "V": return 1
    case "C": return 6
    default: return nil
    }
  }

  private static func tokenize(_ d: String) -> [Token]? {
    var tokens: [Token] = []
    var index = d.startIndex

    while index < d.endIndex {
      let character = d[index]
      if character.isWhitespace || character == "," {
        index = d.index(after: index)
      } else if character.isLetter {
        tokens.append(.command(character))
        index = d.index(after: index)
      } else {
        var end = index
        var seenDigit = false
        var seenDot = false
        if d[end] == "-" || d[end] == "+" { end = d.index(after: end) }
        while end < d.endIndex {
          let next = d[end]
          if next.isASCII && next.isNumber {
            seenDigit = true
          } else if next == "." && !seenDot {
            seenDot = true
          } else if (next == "e" || next == "E") && seenDigit {
            end = d.index(after: end)
            if end < d.endIndex, d[end] == "-" || d[end] == "+" { end = d.index(after: end) }
            continue
          } else {
            break
          }
          end = d.index(after: end)
        }
        guard seenDigit, let value = Double(d[index..<end]) else { return nil }
        tokens.append(.number(value))
        index = end
      }
    }
    return tokens
  }
}
