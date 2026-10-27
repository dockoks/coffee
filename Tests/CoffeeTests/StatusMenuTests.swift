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

@MainActor
@Suite(.serialized)
struct StatusMenuTests {
  let defaults: UserDefaults

  init() {
    defaults = UserDefaults(suiteName: "CoffeeMenuTests")!
    defaults.removePersistentDomain(forName: "CoffeeMenuTests")
  }

  /// Records what the menu asks the login item service to do, instead of registering for real.
  @MainActor final class LoginItemSpy {
    var requests: [Bool] = []
    var fails = false
  }

  func make(spy: LoginItemSpy = LoginItemSpy()) -> (AppState, StatusMenu) {
    let state = AppState(defaults: defaults, sleepDisplay: { true })
    let menu = StatusMenu(appState: state) { enabled in
      spy.requests.append(enabled)
      if spy.fails { throw CocoaError(.featureUnsupported) }
    }
    return (state, menu)
  }

  func item(_ title: String, in menu: NSMenu) -> NSMenuItem {
    menu.items.first { $0.title == title }!
  }

  /// Chooses a menu item: sends its action to its target, as AppKit does when it's clicked.
  func press(_ title: String, in menu: NSMenu) {
    let chosen = item(title, in: menu)
    #expect(chosen.isEnabled, "\(title) is disabled")
    let target = chosen.target as? NSObject
    #expect(target != nil && chosen.action != nil, "\(title) has no action")
    _ = target?.perform(chosen.action, with: chosen)
  }

  func titles(_ menu: NSMenu) -> [String] {
    menu.items.map { $0.isSeparatorItem ? "—" : $0.title }
  }

  // MARK: - The same menu as before

  @Test func theMenuHasTheSameItemsAsBefore() {
    let (_, status) = make()
    #expect(
      titles(status.menu) == [
        "Keep This Mac Awake", "—",
        "Forever", "15 Minutes", "30 Minutes", "45 Minutes", "1 Hour", "1.5 Hours", "2 Hours",
        "3 Hours", "4 Hours", "6 Hours", "8 Hours", "12 Hours", "—",
        "Turn Off", "Turn Off Screen Now", "—",
        "Preferences", "—",
        "Launch at Login", "Quit Coffee",
      ])
    let preferences = item("Preferences", in: status.menu).submenu!
    #expect(
      titles(preferences) == ["Steam", "Sound Effects", "Keep Screen On", "Disable After Suspend"])
    #expect(titles(item("Steam", in: preferences).submenu!) == ["One Curl", "Three Curls"])
  }

  @Test func durationsKeepTheirShortcuts() {
    let (_, status) = make()
    let keys = ["Forever": "0", "1 Hour": "1", "2 Hours": "2", "4 Hours": "4", "8 Hours": "8"]
    for spec in ActivationSpecs.allCases {
      let menuItem = item(spec.rawValue, in: status.menu)
      #expect(menuItem.keyEquivalent == (keys[spec.rawValue] ?? ""), "\(spec.rawValue)")
      #expect(menuItem.keyEquivalentModifierMask == [], "\(spec.rawValue)")
    }
    let quit = item("Quit Coffee", in: status.menu)
    #expect(quit.keyEquivalent == "q" && quit.keyEquivalentModifierMask == [.command])
  }

  // MARK: - Actions

  @Test func choosingADurationStartsItAndTicksIt() {
    let (state, status) = make()
    press("1 Hour", in: status.menu)
    #expect(state.isActive && state.activeSpec == ActivationSpecs.oneHour.spec)
    #expect(item("1 Hour", in: status.menu).state == .on)
    #expect(item("2 Hours", in: status.menu).state == .off)
  }

  @Test func turningOffIsOnlyOfferedWhileBrewing() {
    let (state, status) = make()
    #expect(!item("Turn Off", in: status.menu).isEnabled)
    #expect(!item("Turn Off Screen Now", in: status.menu).isEnabled)
    state.activate(spec: ActivationSpecs.oneHour.spec)
    status.refresh()
    #expect(item("Turn Off", in: status.menu).isEnabled)
    #expect(item("Turn Off Screen Now", in: status.menu).isEnabled)
  }

  @Test func turnOffSpillsTheCup() {
    let (state, status) = make()
    state.activate(spec: ActivationSpecs.oneHour.spec)
    status.refresh()
    press("Turn Off", in: status.menu)
    #expect(!state.isActive && state.transition?.kind == .spilling)
    #expect(!item("Turn Off", in: status.menu).isEnabled)
  }

  @Test func theSteamChoiceIsAPairOfCheckmarks() {
    let (state, status) = make()
    let steam = item("Steam", in: item("Preferences", in: status.menu).submenu!).submenu!
    #expect(item("Three Curls", in: steam).state == .on && item("One Curl", in: steam).state == .off)
    press("One Curl", in: steam)
    #expect(state.steamCurls == .one)
    #expect(item("Three Curls", in: steam).state == .off && item("One Curl", in: steam).state == .on)
  }

  @Test func preferenceTogglesShowAndChangeTheirSetting() {
    let (state, status) = make()
    let preferences = item("Preferences", in: status.menu).submenu!
    #expect(item("Sound Effects", in: preferences).state == .on)
    press("Sound Effects", in: preferences)
    #expect(!state.isSoundEffectsEnabled && item("Sound Effects", in: preferences).state == .off)
    #expect(item("Keep Screen On", in: preferences).state == .on)
    press("Keep Screen On", in: preferences)
    #expect(!state.isKeepScreenOnEnabled && item("Keep Screen On", in: preferences).state == .off)
    #expect(item("Disable After Suspend", in: preferences).state == .off)
    press("Disable After Suspend", in: preferences)
    #expect(state.isDisableAfterSuspendEnabled)
    #expect(item("Disable After Suspend", in: preferences).state == .on)
  }

  @Test func launchAtLoginGoesThroughTheLoginItemService() {
    let spy = LoginItemSpy()
    let (state, status) = make(spy: spy)
    press("Launch at Login", in: status.menu)
    #expect(spy.requests == [true] && state.isLoginItemEnabled)
    #expect(item("Launch at Login", in: status.menu).state == .on)
    spy.fails = true
    press("Launch at Login", in: status.menu)
    #expect(spy.requests == [true, false] && state.isLoginItemEnabled)  // unchanged when it fails
  }

  // MARK: - The countdown, by the second, without disturbing the rest of the menu

  @Test func theHeaderCountsDownInSeconds() {
    let (state, status) = make()
    #expect(status.menu.items[0].title == "Keep This Mac Awake")
    let t0 = Date()
    state.activate(spec: ActivationSpecs.twoHours.spec, now: t0)
    status.refresh(at: t0 + 1)
    #expect(status.menu.items[0].title == "Awake, 1:59:59 left")
    status.refresh(at: t0 + 7200 - 65)
    #expect(status.menu.items[0].title == "Awake, 1:05 left")
    state.activate(spec: ActivationSpecs.forever.spec)
    status.refresh()
    #expect(status.menu.items[0].title == "Awake, no time limit")
  }

  /// Every item in the menu and its submenus, depth first.
  func allItems(_ menu: NSMenu) -> [NSMenuItem] {
    menu.items.flatMap { [$0] + ($0.submenu.map(allItems) ?? []) }
  }

  @Test func refreshingOnlyChangesTheCountdownAndNeverReplacesAnItem() {
    // Replacing items, or changing any but the countdown, is what disturbed the hover highlight.
    let (state, status) = make()
    let t0 = Date()
    state.activate(spec: ActivationSpecs.twoHours.spec, now: t0)
    status.refresh(at: t0)
    let before = allItems(status.menu)
    let titlesBefore = before.map(\.title)
    let submenusBefore = before.compactMap(\.submenu)
    for second in 1...5 { status.refresh(at: t0 + Double(second)) }
    let after = allItems(status.menu)
    #expect(after.count == before.count)
    #expect(zip(after, before).allSatisfy { $0 === $1 })
    #expect(zip(after.compactMap(\.submenu), submenusBefore).allSatisfy { $0 === $1 })
    #expect(Array(after.map(\.title).dropFirst()) == Array(titlesBefore.dropFirst()))
    #expect(after[0].title == "Awake, 1:59:55 left")
  }
}
