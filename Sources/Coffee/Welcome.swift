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
import os

/// What Coffee says when it opens for the first time. Coffee has no window, so without it a
/// new user would see nothing happen.
@MainActor
enum Welcome {
  private static let welcomedKey = "Welcomed"

  /// Whether an app at `url` runs from somewhere it won't stay: a disk image, or the private copy
  /// macOS runs (App Translocation) when an app is opened straight from where it was downloaded.
  /// Login items need the app to stay put.
  static func isTemporaryLocation(_ url: URL) -> Bool {
    let path = url.standardizedFileURL.path
    return path.hasPrefix("/Volumes/") || path.contains("/AppTranslocation/")
  }

  static func showIfNeeded(defaults: UserDefaults = .standard, loginItem: LoginItem = .system) {
    if isTemporaryLocation(Bundle.main.bundleURL) {
      askToMoveToApplications()
    } else if !defaults.bool(forKey: welcomedKey) {
      greet(loginItem: loginItem)
      defaults.set(true, forKey: welcomedKey)
    }
  }

  private static func askToMoveToApplications() {
    let alert = NSAlert()
    alert.messageText = "Move Coffee to Applications"
    alert.informativeText =
      "Coffee is running from its download. Quit it, drag Coffee into the Applications folder, "
      + "and open it from there, so it can start when you log in."
    alert.addButton(withTitle: "Quit")
    alert.addButton(withTitle: "Keep Running")
    NSApp.activate()
    if alert.runModal() == .alertFirstButtonReturn {
      NSApp.terminate(nil)
    }
  }

  private static func greet(loginItem: LoginItem) {
    let alert = NSAlert()
    alert.messageText = "Coffee is in your menu bar"
    alert.informativeText =
      "Click the cup at the top of your screen and pick how long to keep your Mac awake."
    alert.showsSuppressionButton = true
    alert.suppressionButton?.title = "Open Coffee when you log in"
    alert.suppressionButton?.state = .on
    NSApp.activate()
    alert.runModal()
    guard alert.suppressionButton?.state == .on, !loginItem.isEnabled() else { return }
    do {
      try loginItem.setEnabled(true)
    } catch {
      os_log("Failed to add login item: %{public}@", error.localizedDescription)
    }
  }
}
