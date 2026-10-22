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

/// Points are in the artwork's space: 22x22, origin at the top left, y down (like the SVGs).
struct CupIconTests {
  /// Draws the image into a 44x44 px bitmap (22x22 pt at 2x).
  func rasterize(_ image: NSImage) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
      bitmapDataPlanes: nil, pixelsWide: 44, pixelsHigh: 44, bitsPerSample: 8,
      samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
      bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: 22, height: 22)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: 22, height: 22))
    NSGraphicsContext.restoreGraphicsState()
    return rep
  }

  func alpha(_ rep: NSBitmapImageRep, x: CGFloat, y: CGFloat) -> CGFloat {
    rep.colorAt(x: Int(x * 2), y: Int(y * 2))?.alphaComponent ?? -1
  }

  func bitmap(level: Double, steam: CupSteam = .hidden) -> Data? {
    rasterize(CupIcon.image(level: level, steam: steam)).tiffRepresentation
  }

  /// True if any pixel above the cup rim (y < 8 pt) has visible alpha.
  func hasSteam(_ rep: NSBitmapImageRep) -> Bool {
    for px in 0..<44 {
      for py in 0..<16 where (rep.colorAt(x: px, y: py)?.alphaComponent ?? 0) > 0.05 { return true }
    }
    return false
  }

  @Test func templateAndMenuBarSized() {
    let image = CupIcon.image(level: 1, steam: .hidden)
    #expect(image.isTemplate)
    #expect(image.size == NSSize(width: 22, height: 22))
  }

  @Test func fullCup() {
    let rep = rasterize(CupIcon.image(level: 1, steam: .hidden))
    #expect(alpha(rep, x: 10, y: 15) > 0.9)
    #expect(alpha(rep, x: 10, y: 11.5) > 0.9)
  }

  @Test func halfCup() {
    let rep = rasterize(CupIcon.image(level: 0.5, steam: .hidden))
    #expect(alpha(rep, x: 10, y: 16) > 0.9)
    #expect(alpha(rep, x: 10, y: 12) < 0.1)
  }

  @Test func emptyCupStillHasItsOutline() {
    let rep = rasterize(CupIcon.image(level: 0, steam: .hidden))
    #expect(alpha(rep, x: 10, y: 16) < 0.1)
    #expect(alpha(rep, x: 10, y: 18.25) > 0.5)  // bottom of the bowl
    #expect(alpha(rep, x: 10, y: 9.25) > 0.5)  // rim
  }

  @Test func coffeeKeepsAClearGapToTheOutline() {
    let rep = rasterize(CupIcon.image(level: 1, steam: .hidden))
    #expect(alpha(rep, x: 5.3, y: 13) < 0.1)
    #expect(alpha(rep, x: 6.5, y: 13) > 0.9)
  }

  @Test func noSteamWhenNotBrewing() {
    #expect(!hasSteam(rasterize(CupIcon.image(level: 1, steam: .hidden))))
  }

  /// True if there is ink in the box (points in the artwork space) around the steam curl.
  func hasInk(_ rep: NSBitmapImageRep, x: ClosedRange<CGFloat>, y: ClosedRange<CGFloat>) -> Bool {
    for px in Int(x.lowerBound * 2)...Int(x.upperBound * 2) {
      for py in Int(y.lowerBound * 2)...Int(y.upperBound * 2)
      where (rep.colorAt(x: px, y: py)?.alphaComponent ?? 0) > 0.3 { return true }
    }
    return false
  }

  /// The three curls from the Figma frame steam-0, side by side; each is 1 pt wide.
  static let curlCentres: [CGFloat] = [7.5, 10, 12.5]

  func bottomOfCurl(_ x: CGFloat) -> (x: ClosedRange<CGFloat>, y: ClosedRange<CGFloat>) {
    (x - 0.7...x + 0.7, 6.6...7.6)
  }

  func topOfCurl(_ x: CGFloat) -> (x: ClosedRange<CGFloat>, y: ClosedRange<CGFloat>) {
    (x - 0.7...x + 0.7, 2.6...3.6)
  }

  @Test func thereAreThreeCurls() {
    let full = rasterize(CupIcon.image(level: 1, steam: .full))
    for x in Self.curlCentres {
      #expect(
        hasInk(full, x: bottomOfCurl(x).x, y: bottomOfCurl(x).y), "bottom of the curl at \(x)")
      #expect(hasInk(full, x: topOfCurl(x).x, y: topOfCurl(x).y), "top of the curl at \(x)")
    }
  }

  @Test func eachCurlGrowsFromItsBottomPoint() {
    let grown = rasterize(CupIcon.image(level: 1, steam: CupSteam(start: 0, end: 0.25)))
    for x in Self.curlCentres {
      #expect(hasInk(grown, x: bottomOfCurl(x).x, y: bottomOfCurl(x).y), "curl at \(x)")
      #expect(!hasInk(grown, x: topOfCurl(x).x, y: topOfCurl(x).y), "curl at \(x)")
    }
  }

  @Test func eachCurlShrinksAwayFromItsBottomPointToTheTop() {
    let shrunk = rasterize(CupIcon.image(level: 1, steam: CupSteam(start: 0.75, end: 1)))
    for x in Self.curlCentres {
      #expect(!hasInk(shrunk, x: bottomOfCurl(x).x, y: bottomOfCurl(x).y), "curl at \(x)")
      #expect(hasInk(shrunk, x: topOfCurl(x).x, y: topOfCurl(x).y), "curl at \(x)")
    }
  }

  @Test func theCurlMoreCurlMeansMoreInk() {
    func ink(_ end: Double) -> Int {
      let rep = rasterize(CupIcon.image(level: 0, steam: CupSteam(start: 0, end: end)))
      var count = 0
      for px in 0..<44 {
        for py in 0..<16 where (rep.colorAt(x: px, y: py)?.alphaComponent ?? 0) > 0.3 { count += 1 }
      }
      return count
    }
    #expect(ink(0.2) < ink(0.5) && ink(0.5) < ink(1))
    #expect(ink(0) == 0)
  }

  @Test func theCurlStaysPutAndIsDrawnExactlyAsDesignedWhenFull() {
    // Growing then shrinking never moves the curl: a partial curl is a part of the full one.
    let full = rasterize(CupIcon.image(level: 0, steam: .full))
    let part = rasterize(CupIcon.image(level: 0, steam: CupSteam(start: 0.2, end: 0.7)))
    for px in 0..<44 {
      for py in 0..<16 {
        let partAlpha = part.colorAt(x: px, y: py)?.alphaComponent ?? 0
        let fullAlpha = full.colorAt(x: px, y: py)?.alphaComponent ?? 0
        if partAlpha > 0.5 { #expect(fullAlpha > 0.2, "pixel \(px),\(py) is off the curl") }
      }
    }
  }

  @Test func levelIsClamped() {
    #expect(bitmap(level: 1.5) == bitmap(level: 1))
    #expect(bitmap(level: -0.5) == bitmap(level: 0))
  }

  @Test func theStreamPoursDownTheMiddle() {
    let streaming = rasterize(
      CupIcon.image(level: 0, steam: .hidden, pour: CupPour(top: 3, bottom: 7)))
    #expect(alpha(streaming, x: 10, y: 5) > 0.9)
    #expect(alpha(streaming, x: 10, y: 2) < 0.1 && alpha(streaming, x: 10, y: 7.8) < 0.1)
    #expect(alpha(streaming, x: 6, y: 5) < 0.1)
    #expect(
      bitmap(level: 0)
        != rasterize(
          CupIcon.image(level: 0, steam: .hidden, pour: CupPour(top: 3, bottom: 7))
        ).tiffRepresentation)
  }

  @Test func theFullSteamIsDrawnExactlyAsDesigned() throws {
    // The three curls from the Figma frame steam-0, stroked directly: the icon's full steam
    // must match them.
    let design = NSBezierPath()
    for d in [
      "M7.5 7.5C7.5 7.5 7 7.1544 7 6.5C7 5.8456 7.85 5.759 7.85 5C7.85 4.241 7.5 4.5 7.5 3.5",
      "M10 7.5C10 7.5 9.5 7 9.5 6.5C9.5 5.5 10.5 5.75 10.5 4.75C10.5 4 10 4 10 3",
      "M12.5 7.5C12.5 7.5 12 7.1544 12 6.5C12 5.8456 12.85 5.759 12.85 5C12.85 4.241 12.5 4.5 12.5 3.5",
    ] {
      design.append(try #require(SVGPath.parse(d)))
    }
    design.lineWidth = 1
    design.lineCapStyle = .round
    design.lineJoinStyle = .round

    let reference = NSBitmapImageRep(
      bitmapDataPlanes: nil, pixelsWide: 44, pixelsHigh: 44, bitsPerSample: 8,
      samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
      bytesPerRow: 0, bitsPerPixel: 0)!
    reference.size = NSSize(width: 22, height: 22)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: reference)
    CupIcon.image(level: 0, steam: .hidden).draw(in: NSRect(x: 0, y: 0, width: 22, height: 22))
    let flip = NSAffineTransform()  // the artwork's y axis points down
    flip.translateX(by: 0, yBy: 22)
    flip.scaleX(by: 1, yBy: -1)
    flip.concat()
    NSColor.black.set()
    design.stroke()
    NSGraphicsContext.restoreGraphicsState()

    let icon = rasterize(CupIcon.image(level: 0, steam: .full))
    var worst: CGFloat = 0
    for px in 0..<44 {
      for py in 0..<44 {
        let a = icon.colorAt(x: px, y: py)?.alphaComponent ?? 0
        let b = reference.colorAt(x: px, y: py)?.alphaComponent ?? 0
        worst = max(worst, abs(a - b))
      }
    }
    #expect(worst < 0.05, "largest difference from the design: \(worst)")
  }

  // MARK: - Tipping and spilling

  /// The total ink in an image, as summed alpha.
  func ink(_ image: NSImage) -> Double {
    let rep = rasterize(image)
    var total = 0.0
    for px in 0..<44 {
      for py in 0..<44 { total += Double(rep.colorAt(x: px, y: py)?.alphaComponent ?? 0) }
    }
    return total
  }

  @Test func aTippedCupHoldsLess() {
    #expect(abs(CupIcon.capacity(tilt: 0) - 1.19) < 0.03)
    #expect(abs(CupIcon.capacity(tilt: 30) - 0.77) < 0.03)
    #expect(abs(CupIcon.capacity(tilt: 60) - 0.31) < 0.03)
    #expect(CupIcon.capacity(tilt: 90) < 0.02)
  }

  @Test func theCupTipsToTheLeftAboutItsMiddle() {
    let upright = rasterize(CupIcon.image(level: 0, steam: .hidden))
    let tipped = rasterize(CupIcon.image(level: 0, steam: .hidden, tilt: 60))
    #expect(alpha(upright, x: 6, y: 9) > 0.5)  // a point on the rim
    #expect(alpha(tipped, x: 6, y: 9) < 0.1)
    #expect(hasInk(tipped, x: 3.4...4.4, y: 14.4...15.3))  // the same point, tipped 60°
  }

  @Test func theCoffeeSurfaceStaysLevelWhenTipped() {
    let rep = rasterize(CupIcon.image(level: 0.5, steam: .hidden, tilt: 30))
    // Below the surface both sides of the cup have coffee; above it neither does.
    #expect(alpha(rep, x: 7, y: 15.5) > 0.9 && alpha(rep, x: 12, y: 15.5) > 0.9)
    #expect(alpha(rep, x: 7, y: 13.6) < 0.1 && alpha(rep, x: 12, y: 13.6) < 0.1)
  }

  @Test func tippingKeepsTheAmountOfCoffee() {
    let upright =
      ink(CupIcon.image(level: 0.5, steam: .hidden)) - ink(CupIcon.image(level: 0, steam: .hidden))
    let tipped =
      ink(CupIcon.image(level: 0.5, steam: .hidden, tilt: 30))
      - ink(CupIcon.image(level: 0, steam: .hidden, tilt: 30))
    #expect(abs(tipped - upright) / upright < 0.08)
  }

  @Test func theCoffeeNeverRisesAboveTheRim() {
    // A full cup tipped 50° holds only what fits below its lowest rim corner (y 15.3).
    let rep = rasterize(CupIcon.image(level: 1, steam: .hidden, tilt: 50))
    #expect(alpha(rep, x: 9, y: 13.5) < 0.1 && alpha(rep, x: 12, y: 13.5) < 0.1)
    #expect(alpha(rep, x: 9, y: 16.2) > 0.9)  // below the lip, clear of the outline
  }

  @Test func spilledCoffeeFallsFromTheLip() {
    let spilling = rasterize(
      CupIcon.image(level: 0.4, steam: .hidden, tilt: 50, spill: CupSpill(start: 0, end: 1)))
    #expect(hasInk(spilling, x: 0.8...1.8, y: 18...21))
    let still = rasterize(CupIcon.image(level: 0.4, steam: .hidden, tilt: 50))
    #expect(!hasInk(still, x: 0.8...1.8, y: 18...21))
  }

  @Test func theFallingCoffeeLeavesTheLipFirst() {
    // Starting to pour: only the part by the lip. Done pouring: only the part at the bottom.
    let starting = rasterize(
      CupIcon.image(level: 0.4, steam: .hidden, tilt: 50, spill: CupSpill(start: 0, end: 0.3)))
    #expect(hasInk(starting, x: 0.8...1.8, y: 15.6...16.8))
    #expect(!hasInk(starting, x: 0.8...1.8, y: 19.5...21.5))
    let finishing = rasterize(
      CupIcon.image(level: 0, steam: .hidden, tilt: 50, spill: CupSpill(start: 0.7, end: 1)))
    #expect(!hasInk(finishing, x: 0.8...1.8, y: 15.6...16.8))
    #expect(hasInk(finishing, x: 0.8...1.8, y: 20.5...21.8))
  }

  @Test func noCoffeeGetsIntoTheRimCornerWhenTipped() {
    // At 18° a full cup's coffee is at the lip; the sharp rim corner beside it must stay clear.
    let rep = rasterize(CupIcon.image(level: 1, steam: .hidden, tilt: 18))
    #expect(alpha(rep, x: 4, y: 11.5) < 0.1)
  }

  // MARK: - Vector layers, for design tools

  /// Draws the layers the way a design tool shows them: fills filled, strokes stroked 1 pt with
  /// round caps and joins, in order.
  func rasterize(_ layers: [CupIcon.Layer]) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
      bitmapDataPlanes: nil, pixelsWide: 44, pixelsHigh: 44, bitsPerSample: 8,
      samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
      bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: 22, height: 22)
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = context
    let cg = context.cgContext
    cg.translateBy(x: 0, y: 22)  // the artwork's y axis points down
    cg.scaleBy(x: 1, y: -1)
    cg.setFillColor(.black)
    cg.setStrokeColor(.black)
    cg.setLineWidth(1)
    cg.setLineCap(.round)
    cg.setLineJoin(.round)
    for layer in layers {
      cg.addPath(layer.path)
      if layer.isFilled { cg.fillPath() } else { cg.strokePath() }
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep
  }

  func largestDifference(_ a: NSBitmapImageRep, _ b: NSBitmapImageRep) -> CGFloat {
    var worst: CGFloat = 0
    for px in 0..<44 {
      for py in 0..<44 {
        let x = a.colorAt(x: px, y: py)?.alphaComponent ?? 0
        let y = b.colorAt(x: px, y: py)?.alphaComponent ?? 0
        worst = max(worst, abs(x - y))
      }
    }
    return worst
  }

  @Test func theLayersDrawTheSamePictureAsTheIcon() {
    let cases: [(Double, CupSteam, CupPour?, Double, CupSpill?)] = [
      (1, .full, nil, 0, nil),
      (0.5, CupSteam(start: 0.3, end: 1), nil, 0, nil),
      (0.3, .hidden, CupPour(top: 3, bottom: 7), 0, nil),
      (0.4, .hidden, nil, 50, CupSpill(start: 0, end: 1)),
      (1, CupSteam(start: 0.5, end: 1), nil, 18, CupSpill(start: 0, end: 0.4)),
      (0, .hidden, nil, -6, nil),
    ]
    for (level, steam, pour, tilt, spill) in cases {
      let image = rasterize(
        CupIcon.image(level: level, steam: steam, pour: pour, tilt: tilt, spill: spill))
      let layers = rasterize(
        CupIcon.layers(level: level, steam: steam, pour: pour, tilt: tilt, spill: spill))
      // Edge pixels can differ a little in anti-aliasing; a misplaced shape differs by ~1.
      #expect(largestDifference(image, layers) < 0.25, "level \(level), tilt \(tilt)")
    }
  }

  @Test func layersAreNamedAndOnlyThereWhenVisible() {
    let names = CupIcon.layers(
      level: 0.4, steam: .full, pour: nil, tilt: 50, spill: CupSpill(start: 0, end: 1)
    ).map(\.name)
    #expect(names == ["coffee", "cup", "spill", "steam"])
    let empty = CupIcon.layers(level: 0, steam: .hidden, pour: nil, tilt: 0, spill: nil)
    #expect(empty.map(\.name) == ["cup"])
    #expect(empty.allSatisfy { !$0.isFilled })
  }

  // MARK: - One curl or three

  @Test func oneCurlKeepsOnlyTheMiddleOne() {
    let one = rasterize(CupIcon.image(level: 1, steam: .full, curls: .one))
    #expect(hasInk(one, x: bottomOfCurl(10).x, y: bottomOfCurl(10).y))
    #expect(hasInk(one, x: topOfCurl(10).x, y: topOfCurl(10).y))
    for x: CGFloat in [7.5, 12.5] {
      #expect(!hasInk(one, x: bottomOfCurl(x).x, y: bottomOfCurl(x).y), "curl at \(x)")
      #expect(!hasInk(one, x: topOfCurl(x).x, y: topOfCurl(x).y), "curl at \(x)")
    }
  }

  @Test func threeCurlsIsTheDefault() {
    #expect(
      bitmap(level: 1, steam: .full)
        == rasterize(
          CupIcon.image(level: 1, steam: .full, curls: .three)
        ).tiffRepresentation)
  }

  @Test func theOneCurlStillGrowsAndShrinks() {
    let grown = rasterize(
      CupIcon.image(level: 1, steam: CupSteam(start: 0, end: 0.25), curls: .one))
    #expect(hasInk(grown, x: bottomOfCurl(10).x, y: bottomOfCurl(10).y))
    #expect(!hasInk(grown, x: topOfCurl(10).x, y: topOfCurl(10).y))
  }

  @Test func theLayersFollowTheCurlChoice() {
    let image = rasterize(CupIcon.image(level: 0.5, steam: .full, curls: .one))
    let layers = rasterize(CupIcon.layers(level: 0.5, steam: .full, curls: .one))
    #expect(largestDifference(image, layers) < 0.25)
  }
}
