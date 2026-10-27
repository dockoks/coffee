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

/// Asks GitHub for the newest release and offers to download it.
enum Updates {
  static let releasesPage = URL(string: "https://github.com/dockoks/coffee/releases/latest")!
  private static let latestRelease = URL(
    string: "https://api.github.com/repos/dockoks/coffee/releases/latest")!

  static var currentVersion: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
  }

  /// Whether release tag `latest` (such as "v1.2.0") is a newer version than `current` ("1.1.0").
  static func isNewer(_ latest: String, than current: String) -> Bool {
    func numbers(_ version: String) -> [Int] {
      version.trimmingPrefix("v").split(separator: ".").map { Int($0) ?? 0 }
    }
    let new = numbers(latest)
    let old = numbers(current)
    for index in 0..<max(new.count, old.count) {
      let a = index < new.count ? new[index] : 0
      let b = index < old.count ? old[index] : 0
      if a != b { return a > b }
    }
    return false
  }

  static func latestTag() async throws -> String {
    var request = URLRequest(url: latestRelease)
    request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
    let (data, response) = try await URLSession.shared.data(for: request)
    guard (response as? HTTPURLResponse)?.statusCode == 200 else {
      throw URLError(.badServerResponse)
    }
    struct Release: Decodable { let tagName: String }
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try decoder.decode(Release.self, from: data).tagName
  }

  @MainActor static func check() async {
    let current = currentVersion
    let alert = NSAlert()
    var offersDownload = false
    do {
      let latest = try await latestTag()
      if isNewer(latest, than: current) {
        alert.messageText = "Coffee \(latest.trimmingPrefix("v")) is available"
        alert.informativeText =
          "You have version \(current). Download the new version, quit Coffee, and drag the new "
          + "Coffee into the Applications folder to replace it."
        alert.addButton(withTitle: "Download")
        alert.addButton(withTitle: "Later")
        offersDownload = true
      } else {
        alert.messageText = "Coffee is up to date"
        alert.informativeText = "You have the newest version, \(current)."
      }
    } catch {
      os_log("Update check failed: %{public}@", error.localizedDescription)
      alert.messageText = "Couldn’t check for updates"
      alert.informativeText = "Check your internet connection and try again."
    }
    NSApp.activate()
    if alert.runModal() == .alertFirstButtonReturn && offersDownload {
      NSWorkspace.shared.open(releasesPage)
    }
  }
}
