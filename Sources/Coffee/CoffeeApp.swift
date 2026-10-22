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
import SwiftUI
import os

@main
struct CoffeeApp: App {
  @State private var appState: AppState

  init() {
    let state = AppState()
    // Observe system events here rather than in the menu view, which SwiftUI
    // doesn't guarantee to keep alive while the menu is closed.
    state.observeSystemEvents()
    _appState = State(initialValue: state)
  }

  var body: some Scene {
    MenuBarExtra {
      MenuBarMenu(
        appState: appState,
        activate: { appState.activate(spec: $0) },
        turnOff: { appState.turnOff() },
        toggleDisableAfterSuspend: toggleDisableAfterSuspend,
        toggleLaunchAtLogin: toggleLaunchAtLogin
      )
    } label: {
      CupLabel(appState: appState)
    }
  }

  // MARK: - Actions

  private func toggleDisableAfterSuspend() {
    appState.setDisableAfterSuspend(!appState.isDisableAfterSuspendEnabled)
  }

  private func toggleLaunchAtLogin() {
    let newState = !appState.isLoginItemEnabled

    do {
      if newState {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
    } catch {
      os_log("Failed to update login item: %{public}@", error.localizedDescription)
      return
    }

    appState.setLoginItemEnabled(newState)
    os_log("Launch at login: %{public}s", newState ? "enabled" : "disabled")
  }
}

// MARK: - Menu Bar Label

/// The cup in the menu bar. It's a view of its own so that the steam frame ticking five times a
/// second only re-renders this icon, not the whole scene.
struct CupLabel: View {
  let appState: AppState

  var body: some View {
    // Reading `now` makes the icon redraw on every animation tick.
    let frame = appState.cupFrame(at: appState.now)
    Image(
      nsImage: CupIcon.image(
        level: frame.level, steam: frame.steam, pour: frame.pour, tilt: frame.tilt,
        spill: frame.spill, curls: appState.steamCurls))
  }
}

// MARK: - Menu View

struct MenuBarMenu: View {
  let appState: AppState
  let activate: (ActivationSpec) -> Void
  let turnOff: () -> Void
  let toggleDisableAfterSuspend: () -> Void
  let toggleLaunchAtLogin: () -> Void

  /// Only reads values that change when what the menu shows changes (see `minutesLeft`).
  private var headerText: String {
    guard appState.isActive else { return "Keep This Mac Awake" }
    guard let minutes = appState.minutesLeft else { return "Awake, no time limit" }
    return "Awake, \(timeLeftText(minutes: minutes)) left"
  }

  var body: some View {
    Text(headerText)
      .font(.headline)

    Divider()

    ForEach(ActivationSpecs.allCases, id: \.self) { specCase in
      let spec = specCase.spec
      Button {
        activate(spec)
      } label: {
        HStack {
          Text(spec.title)
          if appState.activeSpec == spec {
            Spacer()
            Image(systemName: "checkmark")
          }
        }
      }
      .if(!spec.label.isEmpty) { view in
        view.keyboardShortcut(KeyEquivalent(Character(spec.label)), modifiers: [])
      }
    }

    Divider()

    Button("Turn Off") {
      turnOff()
    }
    .disabled(!appState.isActive)

    Button("Turn Off Screen Now") {
      appState.turnOffScreenNow()
    }
    .disabled(!appState.isActive)

    Divider()

    Menu("Preferences") {
      Picker(
        "Steam",
        selection: Binding(
          get: { appState.steamCurls },
          set: { appState.setSteamCurls($0) }
        )
      ) {
        ForEach(SteamCurls.allCases, id: \.self) { curls in
          Text(curls.title).tag(curls)
        }
      }
      Toggle(
        "Keep Screen On",
        isOn: Binding(
          get: { appState.isKeepScreenOnEnabled },
          set: { appState.setKeepScreenOn($0) }
        ))
      Toggle(
        "Disable After Suspend",
        isOn: Binding(
          get: { appState.isDisableAfterSuspendEnabled },
          set: { _ in toggleDisableAfterSuspend() }
        ))
    }

    Divider()

    Toggle(
      "Launch at Login",
      isOn: Binding(
        get: { appState.isLoginItemEnabled },
        set: { _ in toggleLaunchAtLogin() }
      ))

    Button("Quit Coffee") {
      NSApplication.shared.terminate(nil)
    }
    .keyboardShortcut("q")
  }
}

// MARK: - Conditional View Modifier

extension View {
  @ViewBuilder
  func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
    if condition {
      transform(self)
    } else {
      self
    }
  }
}
