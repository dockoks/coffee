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

/// The menu bar item: the animated cup and its menu.
///
/// The menu is built with AppKit rather than SwiftUI. SwiftUI rebuilds a menu bar menu whenever
/// anything it shows changes, which reset the hover highlight in its submenus once a second
/// while the countdown ticked. Here every item is made once; `refresh` only updates what has
/// changed, so the countdown can tick by the second while the menu is open.
@MainActor
final class StatusMenu: NSObject, NSMenuDelegate {
  let menu = NSMenu()

  private let appState: AppState
  private let loginItem: LoginItem
  private let presentError: @MainActor (Error) -> Void
  private var statusItem: NSStatusItem?
  private var countdownTimer: Timer?

  private let header = NSMenuItem.sectionHeader(title: "")
  private var durationItems: [(spec: ActivationSpec, item: NSMenuItem)] = []
  private var turnOffItem = NSMenuItem()
  private var screenOffItem = NSMenuItem()
  private var steamItems: [(curls: SteamCurls, item: NSMenuItem)] = []
  private var soundEffectsItem = NSMenuItem()
  private var keepScreenOnItem = NSMenuItem()
  private var disableAfterSuspendItem = NSMenuItem()
  private var launchAtLoginItem = NSMenuItem()

  /// - Parameter presentError: Tells the person why the login item couldn't be changed.
  init(
    appState: AppState,
    loginItem: LoginItem = .system,
    presentError: @escaping @MainActor (Error) -> Void = StatusMenu.showLoginItemError
  ) {
    self.appState = appState
    self.loginItem = loginItem
    self.presentError = presentError
    super.init()
    buildMenu()
    menu.delegate = self
    refresh()
  }

  /// Puts the cup in the menu bar and keeps it drawn.
  func install() {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    item.menu = menu
    item.button?.setAccessibilityLabel("Coffee")
    statusItem = item
    drawIcon()
  }

  // MARK: - Building

  private func buildMenu() {
    menu.autoenablesItems = false
    menu.addItem(header)
    menu.addItem(.separator())

    for specCase in ActivationSpecs.allCases {
      let spec = specCase.spec
      let item = action(spec.title, #selector(chooseDuration(_:)), key: spec.label)
      item.representedObject = specCase.rawValue
      durationItems.append((spec, item))
      menu.addItem(item)
    }
    menu.addItem(.separator())

    turnOffItem = action("Turn Off", #selector(turnOff))
    screenOffItem = action("Turn Off Screen Now", #selector(turnOffScreenNow))
    menu.addItem(turnOffItem)
    menu.addItem(screenOffItem)
    menu.addItem(.separator())

    let steam = NSMenu()
    steam.autoenablesItems = false
    for curls in SteamCurls.allCases {
      let item = action(curls.title, #selector(chooseSteam(_:)))
      item.representedObject = curls.rawValue
      steamItems.append((curls, item))
      steam.addItem(item)
    }
    let preferences = NSMenu()
    preferences.autoenablesItems = false
    preferences.addItem(submenu("Steam", steam))
    soundEffectsItem = action("Sound Effects", #selector(toggleSoundEffects))
    preferences.addItem(soundEffectsItem)
    keepScreenOnItem = action("Keep Screen On", #selector(toggleKeepScreenOn))
    disableAfterSuspendItem = action("Disable After Suspend", #selector(toggleDisableAfterSuspend))
    preferences.addItem(keepScreenOnItem)
    preferences.addItem(disableAfterSuspendItem)
    menu.addItem(submenu("Preferences", preferences))
    menu.addItem(.separator())

    launchAtLoginItem = action("Launch at Login", #selector(toggleLaunchAtLogin))
    menu.addItem(launchAtLoginItem)
    menu.addItem(.separator())
    menu.addItem(action("About Coffee", #selector(showAbout)))
    menu.addItem(action("Check for Updates…", #selector(checkForUpdates)))
    menu.addItem(action("Quit Coffee", #selector(quit), key: "q", modifiers: .command))
  }

  private func action(
    _ title: String, _ selector: Selector, key: String = "", modifiers: NSEvent.ModifierFlags = []
  ) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
    item.keyEquivalentModifierMask = modifiers
    item.target = self
    return item
  }

  private func submenu(_ title: String, _ submenu: NSMenu) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
    item.submenu = submenu
    return item
  }

  // MARK: - Updating

  /// Brings every item up to date, changing only what differs, so items are never replaced and
  /// an open menu isn't disturbed.
  func refresh(at now: Date = .now) {
    set(header, title: headerText(at: now))
    for (spec, item) in durationItems { set(item, on: appState.activeSpec == spec) }
    set(turnOffItem, enabled: appState.isActive)
    set(screenOffItem, enabled: appState.isActive)
    for (curls, item) in steamItems { set(item, on: appState.steamCurls == curls) }
    set(soundEffectsItem, on: appState.isSoundEffectsEnabled)
    set(keepScreenOnItem, on: appState.isKeepScreenOnEnabled)
    set(disableAfterSuspendItem, on: appState.isDisableAfterSuspendEnabled)
    set(launchAtLoginItem, on: loginItem.isEnabled())
  }

  private func headerText(at now: Date) -> String {
    guard appState.isActive else { return "Keep This Mac Awake" }
    guard let remaining = appState.remainingTime(at: now) else { return "Awake, no time limit" }
    return "Awake, \(remaining.countdownText) left"
  }

  private func set(_ item: NSMenuItem, title: String) {
    if item.title != title { item.title = title }
  }

  private func set(_ item: NSMenuItem, on: Bool) {
    let state: NSControl.StateValue = on ? .on : .off
    if item.state != state { item.state = state }
  }

  private func set(_ item: NSMenuItem, enabled: Bool) {
    if item.isEnabled != enabled { item.isEnabled = enabled }
  }

  /// Redraws the cup whenever what it shows changes: on every animation tick while it moves.
  private func drawIcon() {
    withObservationTracking {
      let frame = appState.cupFrame(at: appState.now)
      statusItem?.button?.image = CupIcon.image(
        level: frame.level, steam: frame.steam, pour: frame.pour, tilt: frame.tilt,
        spill: frame.spill, curls: appState.steamCurls)
    } onChange: { [weak self] in
      Task { @MainActor in self?.drawIcon() }
    }
  }

  // MARK: - NSMenuDelegate

  func menuNeedsUpdate(_ menu: NSMenu) {
    refresh()
  }

  /// While the menu is open, the countdown ticks. The timer runs in the run loop's common modes,
  /// which include the one menus track the mouse in.
  func menuWillOpen(_ menu: NSMenu) {
    countdownTimer?.invalidate()
    let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.refresh() }
    }
    RunLoop.main.add(timer, forMode: .common)
    countdownTimer = timer
  }

  func menuDidClose(_ menu: NSMenu) {
    countdownTimer?.invalidate()
    countdownTimer = nil
  }

  // MARK: - Actions

  @objc private func chooseDuration(_ sender: NSMenuItem) {
    guard let title = sender.representedObject as? String,
      let spec = ActivationSpecs.spec(for: title)
    else { return }
    appState.activate(spec: spec)
    refresh()
  }

  @objc private func turnOff() {
    appState.turnOff()
    refresh()
  }

  @objc private func turnOffScreenNow() {
    appState.turnOffScreenNow()
    refresh()
  }

  @objc private func chooseSteam(_ sender: NSMenuItem) {
    guard let raw = sender.representedObject as? String, let curls = SteamCurls(rawValue: raw)
    else { return }
    appState.setSteamCurls(curls)
    refresh()
  }

  @objc private func toggleSoundEffects() {
    appState.setSoundEffects(!appState.isSoundEffectsEnabled)
    refresh()
  }

  @objc private func toggleKeepScreenOn() {
    appState.setKeepScreenOn(!appState.isKeepScreenOnEnabled)
    refresh()
  }

  @objc private func toggleDisableAfterSuspend() {
    appState.setDisableAfterSuspend(!appState.isDisableAfterSuspendEnabled)
    refresh()
  }

  @objc private func toggleLaunchAtLogin() {
    let newState = !loginItem.isEnabled()
    do {
      try loginItem.setEnabled(newState)
      os_log("Launch at login: %{public}s", newState ? "enabled" : "disabled")
    } catch {
      os_log("Failed to update login item: %{public}@", error.localizedDescription)
      presentError(error)
    }
    refresh()
  }

  @objc private func showAbout() {
    NSApp.activate()
    NSApp.orderFrontStandardAboutPanel(options: [
      .credits: NSAttributedString(
        string: "github.com/dockoks/coffee",
        attributes: [
          .link: URL(string: "https://github.com/dockoks/coffee")!,
          .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
        ])
    ])
  }

  @objc private func checkForUpdates() {
    Task { await Updates.check() }
  }

  @objc private func quit() {
    NSApplication.shared.terminate(nil)
  }

  static func showLoginItemError(_ error: Error) {
    let alert = NSAlert()
    alert.messageText = "Coffee can’t open at login"
    alert.informativeText =
      Welcome.isTemporaryLocation(Bundle.main.bundleURL)
      ? "Move Coffee into the Applications folder and open it from there, then try again."
      : error.localizedDescription
    NSApp.activate()
    alert.runModal()
  }
}
