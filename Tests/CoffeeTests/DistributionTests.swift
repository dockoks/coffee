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
import Testing

@testable import Coffee

struct DistributionTests {
  @Test func newerReleasesAreComparedNumerically() {
    #expect(Updates.isNewer("v1.0.1", than: "1.0.0"))
    #expect(Updates.isNewer("v1.10.0", than: "1.9.0"))
    #expect(Updates.isNewer("2.0", than: "1.9.9"))
    #expect(!Updates.isNewer("v1.0.0", than: "1.0.0"))
    #expect(!Updates.isNewer("v1.0", than: "1.0.0"))
    #expect(!Updates.isNewer("v0.9.0", than: "1.0.0"))
  }

  @MainActor @Test func downloadsAreTemporaryButApplicationsIsNot() {
    #expect(Welcome.isTemporaryLocation(URL(fileURLWithPath: "/Volumes/Coffee/Coffee.app")))
    #expect(
      Welcome.isTemporaryLocation(
        URL(
          fileURLWithPath:
            "/private/var/folders/x/T/AppTranslocation/1234/d/Coffee.app")))
    #expect(!Welcome.isTemporaryLocation(URL(fileURLWithPath: "/Applications/Coffee.app")))
    #expect(!Welcome.isTemporaryLocation(URL(fileURLWithPath: "/Users/me/Applications/Coffee.app")))
  }
}
