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

import ServiceManagement

/// Coffee's entry in System Settings → General → Login Items.
///
/// macOS keeps the truth: people can also switch it off in System Settings, so `isEnabled` asks
/// every time instead of remembering what Coffee last set.
@MainActor
struct LoginItem {
  var isEnabled: () -> Bool
  /// Throws when macOS refuses, for example when the app runs from a disk image.
  var setEnabled: (Bool) throws -> Void

  static let system = LoginItem(
    isEnabled: {
      let status = SMAppService.mainApp.status
      return status == .enabled || status == .requiresApproval
    },
    setEnabled: { enabled in
      if enabled {
        try SMAppService.mainApp.register()
        if SMAppService.mainApp.status == .requiresApproval {
          SMAppService.openSystemSettingsLoginItems()
        }
      } else {
        try SMAppService.mainApp.unregister()
      }
    })
}
