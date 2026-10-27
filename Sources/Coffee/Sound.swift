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

/// A sound effect that plays from the start and can be cut short.
@MainActor
protocol SoundEffect: AnyObject {
  func play()
  func stop()
}

/// A sound in the app's Resources folder, where `script/build` puts it.
final class BundledSound: SoundEffect {
  private let sound: NSSound

  /// Nil when the app has no such sound, as when it runs outside its bundle (`swift run`, tests).
  init?(named name: String, extension ext: String) {
    guard let url = Bundle.main.url(forResource: name, withExtension: ext),
      let sound = NSSound(contentsOf: url, byReference: false)
    else { return nil }
    self.sound = sound
  }

  func play() {
    sound.stop()  // so playing again starts over
    sound.play()
  }

  func stop() {
    sound.stop()
  }
}
