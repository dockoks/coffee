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

// Renders the cup animations for ./script/preview. Compiled together with the app's drawing code.

import AppKit
import ImageIO
import UniformTypeIdentifiers

let outputDirectory = URL(
  fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".build/preview")

struct Theme {
  let name: String
  let background: NSColor
  let ink: NSColor
}

let themes = [
  Theme(
    name: "light", background: NSColor(srgbRed: 0.91, green: 0.91, blue: 0.92, alpha: 1),
    ink: .black),
  Theme(
    name: "dark", background: NSColor(srgbRed: 0.17, green: 0.17, blue: 0.18, alpha: 1), ink: .white
  ),
]

// MARK: - Drawing

let canvasPoints = 30  // the 22 pt icon plus a margin

func makeRep(width: Int, height: Int) -> NSBitmapImageRep {
  let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
    samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
    bytesPerRow: 0, bitsPerPixel: 0)!
  rep.size = NSSize(width: width, height: height)
  return rep
}

func draw(into rep: NSBitmapImageRep, _ body: () -> Void) {
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
  body()
  NSGraphicsContext.restoreGraphicsState()
}

/// The cup as the menu bar shows it: the template image tinted to the theme's ink.
func render(_ frame: CupFrame, theme: Theme, scale: Int, curls: SteamCurls = .three)
  -> NSBitmapImageRep
{
  let side = canvasPoints * scale
  let icon = makeRep(width: 22 * scale, height: 22 * scale)
  draw(into: icon) {
    CupIcon.image(
      level: frame.level, steam: frame.steam, pour: frame.pour, tilt: frame.tilt,
      spill: frame.spill, curls: curls
    ).draw(
      in: NSRect(x: 0, y: 0, width: 22 * scale, height: 22 * scale))
    theme.ink.set()
    NSRect(x: 0, y: 0, width: 22 * scale, height: 22 * scale).fill(using: .sourceIn)
  }

  let result = makeRep(width: side, height: side)
  draw(into: result) {
    theme.background.set()
    NSRect(x: 0, y: 0, width: side, height: side).fill()
    let margin = 4 * scale
    NSImage(cgImage: icon.cgImage!, size: icon.size)
      .draw(in: NSRect(x: margin, y: margin, width: 22 * scale, height: 22 * scale))
  }
  return result
}

// MARK: - Timelines

let tick = 0.04  // 25 frames per second
let start = Date(timeIntervalSinceReferenceDate: 0)

func live(level: Double, time: Double) -> CupFrame {
  CupFrame(level: level, steam: CupAnimation.steam(at: time))
}

func transitionFrames(_ kind: CupTransition.Kind, from level: Double, steam: CupSteam = .full)
  -> [CupFrame]
{
  let transition = CupTransition(
    kind: kind, startedAt: start, fromLevel: level, steam: kind == .starting ? .hidden : steam)
  var frames: [CupFrame] = []
  var time = 0.0
  while time < transition.duration {
    frames.append(transition.frame(at: start + time, level: 1))
    time += tick
  }
  return frames
}

/// Turn on, brew for a while with the coffee draining, turn off, rest.
func fullCycle() -> [CupFrame] {
  var frames = transitionFrames(.starting, from: 0)
  let brewing = 3.0
  var time = 0.0
  while time < brewing {
    frames.append(live(level: 1 - 0.7 * time / brewing, time: time))
    time += tick
  }
  frames += transitionFrames(
    .stopping, from: 0.3, steam: CupAnimation.steam(at: brewing))
  frames += Array(repeating: CupFrame(level: 0, steam: .hidden), count: 15)
  return frames
}

func steamLoop() -> [CupFrame] {
  let period = Double(CupAnimation.steamLoop.count) * CupAnimation.steamLoopStep
  return stride(from: 0.0, to: period * 2, by: tick).map { live(level: 1, time: $0) }
}

/// The keyframes, for contact sheets. The last one is the state the animation hands over to.
func poses(_ kind: CupTransition.Kind, from level: Double) -> [(String, CupFrame)] {
  let transition = CupTransition(
    kind: kind, startedAt: start, fromLevel: level, steam: kind == .starting ? .hidden : .full)
  let prefix =
    switch kind {
    case .starting: "on"
    case .stopping: "off"
    case .spilling: "spill"
    }
  let last = transition.poses.count - 1
  return transition.poses.indices.map { index in
    let milliseconds = Int((Double(index) * CupAnimation.stepDuration * 1000).rounded())
    let caption =
      index == last ? "then\n\(milliseconds) ms" : "\(prefix)-\(index)\n\(milliseconds) ms"
    return (
      caption, transition.frame(at: start + Double(index) * CupAnimation.stepDuration, level: 1)
    )
  }
}

// MARK: - Output

func writeGIF(_ frames: [CupFrame], theme: Theme, name: String, curls: SteamCurls = .three) {
  let url = outputDirectory.appendingPathComponent("\(name)-\(theme.name).gif")
  let destination = CGImageDestinationCreateWithURL(
    url as CFURL, UTType.gif.identifier as CFString, frames.count, nil)!
  CGImageDestinationSetProperties(
    destination,
    [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
  let delay = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: tick]] as CFDictionary
  for frame in frames {
    CGImageDestinationAddImage(
      destination, render(frame, theme: theme, scale: 8, curls: curls).cgImage!, delay)
  }
  CGImageDestinationFinalize(destination)
}

func writeSheet(_ cells: [(String, CupFrame)], theme: Theme, name: String) {
  let scale = 5
  let cell = canvasPoints * scale
  let captionHeight = 34
  let rep = makeRep(width: cell * cells.count, height: cell + captionHeight)
  draw(into: rep) {
    theme.background.set()
    NSRect(x: 0, y: 0, width: rep.pixelsWide, height: rep.pixelsHigh).fill()
    let style = NSMutableParagraphStyle()
    style.alignment = .center
    let attributes: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: 11), .foregroundColor: theme.ink.withAlphaComponent(0.7),
      .paragraphStyle: style,
    ]
    for (index, (caption, frame)) in cells.enumerated() {
      let image = NSImage(
        cgImage: render(frame, theme: theme, scale: scale).cgImage!,
        size: NSSize(width: cell, height: cell))
      image.draw(in: NSRect(x: index * cell, y: captionHeight, width: cell, height: cell))
      caption.draw(
        in: NSRect(x: index * cell, y: 2, width: cell, height: captionHeight - 4),
        withAttributes: attributes)
    }
  }
  let url = outputDirectory.appendingPathComponent("\(name)-\(theme.name).png")
  try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

// MARK: - Keyframes for Figma

/// A path as SVG path data, in the artwork's 22 pt space.
func svgPathData(_ path: CGPath) -> String {
  func n(_ value: CGFloat) -> String {
    let rounded = (value * 1000).rounded() / 1000
    return rounded == rounded.rounded() ? String(Int(rounded)) : String(Double(rounded))
  }
  var d: [String] = []
  path.applyWithBlock { pointer in
    let element = pointer.pointee
    let p = element.points
    switch element.type {
    case .moveToPoint: d.append("M\(n(p[0].x)) \(n(p[0].y))")
    case .addLineToPoint: d.append("L\(n(p[0].x)) \(n(p[0].y))")
    case .addQuadCurveToPoint: d.append("Q\(n(p[0].x)) \(n(p[0].y)) \(n(p[1].x)) \(n(p[1].y))")
    case .addCurveToPoint:
      d.append("C\(n(p[0].x)) \(n(p[0].y)) \(n(p[1].x)) \(n(p[1].y)) \(n(p[2].x)) \(n(p[2].y))")
    case .closeSubpath: d.append("Z")
    @unknown default: break
    }
  }
  return d.joined(separator: " ")
}

/// The spill keyframes from a full cup, as JSON: each frame's numbers and its shapes as SVG path
/// data, so they can be rebuilt as editable layers in Figma.
func writeSpillKeyframesForFigma() {
  let transition = CupTransition(kind: .spilling, startedAt: start, fromLevel: 1, steam: .full)
  let frames: [[String: Any]] = transition.poses.indices.map { index in
    let time = Double(index) * CupAnimation.stepDuration
    let frame = transition.frame(at: start + time, level: 1)
    let layers = CupIcon.layers(
      level: frame.level, steam: frame.steam, pour: frame.pour, tilt: frame.tilt,
      spill: frame.spill)
    var shapes: [String: String] = [:]
    for layer in layers { shapes[layer.name] = svgPathData(layer.path) }
    return [
      "name": "spill-\(index)", "ms": Int((time * 1000).rounded()), "tilt": frame.tilt,
      "coffee": frame.level, "steam": frame.steam.length,
      "allowed": transition.poses[index].coffee, "shapes": shapes,
    ]
  }
  let data = try! JSONSerialization.data(
    withJSONObject: ["frames": frames], options: [.prettyPrinted, .sortedKeys])
  try! data.write(to: outputDirectory.appendingPathComponent("figma-spill.json"))
}

try! FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

let animations: [(name: String, title: String, note: String, frames: [CupFrame])] = [
  (
    "cycle", "Full cycle",
    "Turn on, brew while the coffee drains from 100% to 30%, turn off, rest.",
    fullCycle()
  ),
  (
    "on", "Turn on", "12 keyframes 100 ms apart, blended smoothly, then the steam loop.",
    transitionFrames(.starting, from: 0)
  ),
  (
    "steam", "Steam loop",
    "12 keyframes 200 ms apart (2.4 s per loop), blended smoothly. Two loops.", steamLoop()
  ),
  (
    "steam-one", "Steam loop with one curl",
    "Preferences → Steam → One Curl: only the middle curl. Two loops.", steamLoop()
  ),
  (
    "off", "Turn off (timer ran out)",
    "8 keyframes 100 ms apart, blended smoothly, from a full cup.",
    transitionFrames(.stopping, from: 1)
  ),
  (
    "spill", "Turned off by hand: the cup spills",
    "From a full cup. The steam pulls back, the cup tips over, coffee pours from the rim, and the empty cup swings back.",
    transitionFrames(.spilling, from: 1)
  ),
  (
    "spill-low", "Turned off by hand, with the cup at 30%",
    "Less coffee: it only reaches the rim later in the tip, so it spills later.",
    transitionFrames(.spilling, from: 0.3)
  ),
]
/// Animations drawn with the one-curl steam setting; the rest use three curls.
let oneCurlAnimations: Set<String> = ["steam-one"]

let sheets: [(name: String, title: String, cells: [(String, CupFrame)])] = [
  (
    "sheet-on", "Turn on, keyframes (the app blends smoothly between them)",
    poses(.starting, from: 0)
  ),
  (
    "sheet-steam",
    "Steam loop, keyframes (the curl grows from its bottom point, then shrinks away towards its top)",
    CupAnimation.steamLoop.indices.map {
      let time = Double($0) * CupAnimation.steamLoopStep
      return ("steam-\($0)\n\(Int(time * 1000)) ms", live(level: 1, time: time))
    }
  ),
  ("sheet-off", "Turn off (timer ran out), keyframes", poses(.stopping, from: 1)),
  ("sheet-spill", "Turned off by hand, keyframes (from a full cup)", poses(.spilling, from: 1)),
  (
    "sheet-levels", "Coffee level while brewing",
    [1.0, 0.75, 0.5, 0.25, 0.05].map { ("\(Int($0 * 100))%", live(level: $0, time: 0)) }
  ),
  (
    "sheet-switch", "Switching to a new duration at 40% (refills from where it is)",
    poses(.starting, from: 0.4)
  ),
]

writeSpillKeyframesForFigma()

for theme in themes {
  for animation in animations {
    writeGIF(
      animation.frames, theme: theme, name: animation.name,
      curls: oneCurlAnimations.contains(animation.name) ? .one : .three)
  }
  for sheet in sheets { writeSheet(sheet.cells, theme: theme, name: sheet.name) }
}

var html = """
  <!doctype html><meta charset="utf-8"><title>Coffee cup preview</title>
  <style>
  body { font: 14px -apple-system, sans-serif; margin: 32px; background: #fff; color: #222; }
  h1 { font-size: 22px } h2 { font-size: 16px; margin: 32px 0 4px } p { color: #666; margin: 0 0 10px }
  .row { display: flex; gap: 16px; align-items: flex-start; flex-wrap: wrap }
  img { border-radius: 8px; image-rendering: auto } .real { width: \(canvasPoints)px; height: \(canvasPoints)px }
  figure { margin: 0 } figcaption { font-size: 11px; color: #888; margin-top: 4px }
  </style>
  <h1>Coffee cup preview</h1>
  <p>Rendered by ./script/preview from the app's own drawing code. Re-run it after changing the art or the animation table.</p>
  """
for animation in animations {
  html += "<h2>\(animation.title)</h2><p>\(animation.note)</p><div class=\"row\">"
  for theme in themes {
    html +=
      "<figure><img src=\"\(animation.name)-\(theme.name).gif\" width=\"\(canvasPoints * 8)\"><figcaption>\(theme.name), enlarged</figcaption></figure>"
  }
  for theme in themes {
    html +=
      "<figure><img class=\"real\" src=\"\(animation.name)-\(theme.name).gif\"><figcaption>\(theme.name), actual size</figcaption></figure>"
  }
  html += "</div>"
}
for sheet in sheets {
  html += "<h2>\(sheet.title)</h2>"
  for theme in themes {
    html += "<div><img src=\"\(sheet.name)-\(theme.name).png\" style=\"max-width:100%\"></div><br>"
  }
}
try! html.write(
  to: outputDirectory.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
print("Preview written to \(outputDirectory.path)/index.html")
