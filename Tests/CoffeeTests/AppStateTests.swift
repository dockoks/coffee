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
struct AppStateTests {
  let defaults: UserDefaults

  init() {
    defaults = UserDefaults(suiteName: "CoffeeTests")!
    defaults.removePersistentDomain(forName: "CoffeeTests")
  }

  /// Records display sleep requests so tests never turn off the real display.
  @MainActor final class DisplaySpy {
    var calls = 0
    var result = true
  }

  func makeAppState(spy: DisplaySpy = DisplaySpy()) -> AppState {
    AppState(
      defaults: defaults,
      sleepDisplay: {
        spy.calls += 1
        return spy.result
      })
  }

  @Test func activatingHoldsAssertionAndSchedulesTimer() {
    let state = makeAppState()
    state.activate(spec: ActivationSpecs.oneHour.spec)
    #expect(state.isActive)
    #expect(state.activeSpec == ActivationSpecs.oneHour.spec)
    #expect(state.powerAssertion != nil)
    #expect(state.deactivationTask != nil)
  }

  @Test func activatingForeverSchedulesNoTimer() {
    let state = makeAppState()
    state.activate(spec: ActivationSpecs.forever.spec)
    #expect(state.isActive)
    #expect(state.deactivationTask == nil)
  }

  @Test func activatingSameSpecTogglesOff() {
    let state = makeAppState()
    state.activate(spec: ActivationSpecs.oneHour.spec)
    state.activate(spec: ActivationSpecs.oneHour.spec)
    #expect(!state.isActive)
    #expect(state.activeSpec == nil)
    #expect(state.powerAssertion == nil)
  }

  @Test func activatingDifferentSpecReplaces() {
    let state = makeAppState()
    state.activate(spec: ActivationSpecs.halfHour.spec)
    state.activate(spec: ActivationSpecs.twoHours.spec)
    #expect(state.isActive)
    #expect(state.activeSpec == ActivationSpecs.twoHours.spec)
  }

  @Test func timerExpiryDeactivates() async throws {
    let state = makeAppState()
    state.activate(spec: ActivationSpec(title: "Test", timeInterval: 0.2, label: ""))
    try await Task.sleep(for: .seconds(1))
    #expect(!state.isActive)
    #expect(state.powerAssertion == nil)
  }

  @Test(arguments: [true, false])
  func systemWakeRespectsPreference(enabled: Bool) {
    let state = makeAppState()
    state.setDisableAfterSuspend(enabled)
    state.activate(spec: ActivationSpecs.oneHour.spec)
    state.handleSystemWake()
    #expect(state.isActive == !enabled)
  }

  @Test func observedSystemWakeDeactivates() async {
    let state = makeAppState()
    state.observeSystemEvents()
    state.setDisableAfterSuspend(true)
    state.activate(spec: ActivationSpecs.oneHour.spec)
    NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
    await Task.yield()
    #expect(!state.isActive)
  }

  @Test func idleCupIsEmpty() {
    #expect(makeAppState().coffeeLevel(at: .now) == 0)
  }

  @Test func levelFollowsWallClock() {
    let state = makeAppState()
    let t0 = Date()
    state.activate(spec: ActivationSpecs.twoHours.spec, now: t0)
    #expect(abs(state.coffeeLevel(at: t0 + 1800) - 0.75) < 0.0001)
    #expect(state.remainingTime(at: t0 + 1800) == 5400)
  }

  @Test func foreverHasNoRemainingTime() {
    let state = makeAppState()
    state.activate(spec: ActivationSpecs.forever.spec)
    #expect(state.remainingTime(at: .now) == nil)
  }

  @Test func reactivatingRestartsLevel() {
    let state = makeAppState()
    let t0 = Date()
    state.activate(spec: ActivationSpecs.twoHours.spec, now: t0)
    state.activate(spec: ActivationSpecs.oneHour.spec, now: t0 + 1800)
    #expect(state.coffeeLevel(at: t0 + 1800) == 1.0)
  }

  @Test func brewingStartsSteamLoop() {
    let state = makeAppState()
    state.activate(spec: ActivationSpecs.oneHour.spec)
    #expect(state.animationTask != nil)
  }

  @Test func screenSleepPausesAndWakeResumesSteam() {
    let state = makeAppState()
    state.activate(spec: ActivationSpecs.oneHour.spec)
    state.handleScreensDidSleep()
    #expect(state.animationTask == nil)
    state.handleScreensDidWake()
    #expect(state.animationTask != nil)
  }

  @Test func switchingSpecsKeepsOneSteamLoop() {
    let state = makeAppState()
    state.activate(spec: ActivationSpecs.halfHour.spec)
    let first = state.animationTask
    state.activate(spec: ActivationSpecs.twoHours.spec)
    #expect(first?.isCancelled == true)
    #expect(state.animationTask != nil)
    #expect(state.animationTask != first)
  }

  @Test func wakeWhileIdleDoesNotStartSteam() {
    let state = makeAppState()
    state.activate(spec: ActivationSpecs.oneHour.spec)
    state.handleScreensDidSleep()
    state.deactivate()
    state.handleScreensDidWake()
    #expect(state.animationTask == nil)
  }

  // MARK: - Start and stop animations

  @Test func activatingPoursAndFillsTheCupFromEmpty() {
    let state = makeAppState()
    let t0 = Date()
    state.activate(spec: ActivationSpecs.oneHour.spec, now: t0)
    #expect(state.transition?.kind == .starting)

    let begin = state.cupFrame(at: t0)
    #expect(begin.level == 0 && begin.pour == CupPour(top: 3, bottom: 5) && begin.steam.length == 0)
    let filling = state.cupFrame(at: t0 + 0.45)
    #expect(abs(filling.level - 0.5) < 0.01 && filling.pour == CupPour(top: 3, bottom: 7))
    let draining = state.cupFrame(at: t0 + 0.75)
    #expect(draining.level > 0.99 && abs((draining.pour?.top ?? 0) - 5.5) < 0.01)
    let steaming = state.cupFrame(at: t0 + 0.95)
    #expect(steaming.steam.start == 0 && abs(steaming.steam.end - 0.165) < 0.01)
  }

  @Test func theSteamLoopTakesOverWhereTheStartAnimationEnds() {
    let state = makeAppState()
    let t0 = Date()
    state.activate(spec: ActivationSpecs.oneHour.spec, now: t0)
    #expect(state.steamLoopStart == state.transition?.end)

    let end = t0 + 1.2
    let settled = state.cupFrame(at: end)
    #expect(settled.steam == .full && settled.pour == nil)
    // A moment later the loop is under way, with no jump from the animation.
    let before = state.cupFrame(at: end - 0.005).steam
    #expect(before.start == 0 && abs(before.end - 1) < 0.02)
    let shrinking = state.cupFrame(at: end + 0.4).steam
    #expect(abs(shrinking.start - 0.25) < 0.01 && shrinking.end == 1)
  }

  @Test func theSteamLoopStartsAtOnceWhenNobodyIsWatching() {
    let state = makeAppState()
    let t0 = Date()
    state.handleScreensDidSleep()
    state.activate(spec: ActivationSpecs.oneHour.spec, now: t0)
    #expect(state.transition == nil)
    #expect(state.steamLoopStart == t0)
  }

  @Test func deactivatingShrinksTheCurlFromWhereItWasAndDrains() {
    let state = makeAppState()
    let t0 = Date()
    state.activate(spec: ActivationSpecs.twoHours.spec, now: t0 - 1.2)  // loop starts right at t0
    state.deactivate(now: t0)

    // The Mac is released at once; only the icon takes its time.
    #expect(!state.isActive && state.powerAssertion == nil)
    #expect(state.transition?.kind == .stopping)

    let begin = state.cupFrame(at: t0)
    #expect(begin.steam == .full)
    let shrinking = state.cupFrame(at: t0 + 0.1)
    #expect(abs(shrinking.steam.start - 0.33) < 0.01 && shrinking.steam.end == 1)
    let draining = state.cupFrame(at: t0 + 0.55)
    #expect(draining.steam.length == 0 && draining.level < begin.level)
    let gone = state.cupFrame(at: t0 + 1)
    #expect(gone.level == 0 && gone.steam.length == 0)
  }

  @Test func deactivatingDrainsFromTheCurrentLevel() {
    let state = makeAppState()
    let t0 = Date()
    state.activate(spec: ActivationSpecs.twoHours.spec, now: t0 - 3600)  // half empty by now
    state.deactivate(now: t0)
    #expect(abs(state.cupFrame(at: t0).level - 0.5) < 0.01)
    #expect(abs(state.cupFrame(at: t0 + 0.55).level - 0.5 * 0.5) < 0.01)
  }

  @Test func deactivatingWhenIdleStartsNoAnimation() {
    let state = makeAppState()
    state.deactivate()
    #expect(state.transition == nil)
    #expect(state.animationTask == nil)
  }

  @Test func idleCupIsEmptyWithoutSteam() {
    #expect(makeAppState().cupFrame(at: .now) == CupFrame(level: 0, steam: .hidden, pour: nil))
  }

  @Test func switchingSpecsRefillsFromTheCurrentLevel() {
    let state = makeAppState()
    let t0 = Date()
    state.activate(spec: ActivationSpecs.twoHours.spec, now: t0 - 3600)  // half empty by now
    state.activate(spec: ActivationSpecs.oneHour.spec, now: t0)
    #expect(state.isActive)
    #expect(state.transition?.kind == .starting)
    #expect(abs(state.cupFrame(at: t0).level - 0.5) < 0.01)
    #expect(state.cupFrame(at: t0 + 0.75).level > 0.99)
  }

  @Test func theClockKeepsRunningAfterTheStartAnimation() async throws {
    let state = makeAppState()
    state.activate(spec: ActivationSpecs.forever.spec)
    try await Task.sleep(for: .seconds(0.6))
    #expect(state.transition != nil)
    try await Task.sleep(for: .seconds(1.0))  // 1.6 s: past the 1.2 s animation
    #expect(state.transition == nil)
    #expect(state.animationTask != nil)
    let before = state.now
    try await Task.sleep(for: .milliseconds(300))
    #expect(state.now > before)
  }

  @Test func screenSleepEndsTheAnimationAtOnce() {
    let state = makeAppState()
    state.activate(spec: ActivationSpecs.oneHour.spec)
    state.handleScreensDidSleep()
    #expect(state.transition == nil)
  }

  @Test func stoppingWhileTheScreenIsAsleepSkipsTheAnimation() {
    let state = makeAppState()
    state.activate(spec: ActivationSpecs.oneHour.spec)
    state.handleScreensDidSleep()
    state.deactivate()
    #expect(state.transition == nil)
  }

  @Test func loopEndsWhenTheStopAnimationEnds() async throws {
    let state = makeAppState()
    state.activate(spec: ActivationSpecs.forever.spec)
    state.deactivate()
    #expect(state.animationTask != nil)  // the cup is still emptying
    try await Task.sleep(for: .seconds(1.3))
    #expect(state.animationTask == nil)
    #expect(state.transition == nil)
  }

  // MARK: - Turning off by hand spills the cup

  @Test func turningOffSpillsTheCup() {
    let state = makeAppState()
    state.activate(spec: ActivationSpecs.oneHour.spec)
    state.turnOff()
    #expect(!state.isActive && state.powerAssertion == nil && state.deactivationTask == nil)
    #expect(state.transition?.kind == .spilling)
  }

  @Test func clickingTheActiveDurationAgainSpills() {
    let state = makeAppState()
    state.activate(spec: ActivationSpecs.oneHour.spec)
    state.activate(spec: ActivationSpecs.oneHour.spec)
    #expect(!state.isActive)
    #expect(state.transition?.kind == .spilling)
  }

  @Test func theTimerRunningOutDrainsInstead() async throws {
    let state = makeAppState()
    state.activate(spec: ActivationSpec(title: "Test", timeInterval: 0.2, label: ""))
    try await Task.sleep(for: .seconds(0.45))
    #expect(!state.isActive)
    #expect(state.transition?.kind == .stopping)
  }

  @Test func turningOffSpillsWhatIsInTheCup() {
    let state = makeAppState()
    let t0 = Date()
    state.activate(spec: ActivationSpecs.twoHours.spec, now: t0 - 3600)  // half empty by now
    state.turnOff(now: t0)
    let start = state.cupFrame(at: t0)
    #expect(abs(start.level - 0.5) < 0.01 && start.tilt == 0)
    #expect(state.cupFrame(at: t0 + 0.75).tilt > 80)
  }

  @Test func turningOffWhileIdleDoesNothing() {
    let state = makeAppState()
    state.turnOff()
    #expect(state.transition == nil && state.animationTask == nil)
  }

  @Test func turningOffWithTheScreenAsleepSkipsTheAnimation() {
    let state = makeAppState()
    state.activate(spec: ActivationSpecs.oneHour.spec)
    state.handleScreensDidSleep()
    state.turnOff()
    #expect(!state.isActive && state.transition == nil)
  }

  // MARK: - Steam preference

  @Test func steamHasThreeCurlsUnlessChosenOtherwise() {
    #expect(makeAppState().steamCurls == .three)
  }

  @Test func theSteamChoiceIsRemembered() {
    let state = makeAppState()
    state.setSteamCurls(.one)
    #expect(state.steamCurls == .one)
    #expect(makeAppState().steamCurls == .one)  // a fresh start reads it back
    state.setSteamCurls(.three)
    #expect(makeAppState().steamCurls == .three)
  }

  @Test func anUnknownSavedSteamChoiceFallsBackToThree() {
    defaults.set("seven", forKey: "SteamCurls")
    #expect(makeAppState().steamCurls == .three)
  }

  // MARK: - The open menu

  /// A flag the menu's observation sets when anything it shows changes.
  @MainActor final class Changed { var value = false }

  func watchMenu(of state: AppState) -> Changed {
    let changed = Changed()
    let menu = MenuBarMenu(
      appState: state, activate: { _ in }, turnOff: {}, toggleDisableAfterSuspend: {},
      toggleLaunchAtLogin: {})
    withObservationTracking {
      _ = menu.body
    } onChange: {
      MainActor.assumeIsolated { changed.value = true }
    }
    return changed
  }

  @Test func theOpenMenuIsNotRebuiltOnEveryAnimationTick() async throws {
    // SwiftUI rebuilds the open menu whenever something it shows changes; rebuilding it on every
    // animation tick (20 times a second) made the Preferences submenu's hover highlight flicker.
    let state = makeAppState()
    state.activate(spec: ActivationSpecs.twoHours.spec)
    try await Task.sleep(for: .seconds(1.5))  // past the start animation: only the steam moves
    let changed = watchMenu(of: state)
    try await Task.sleep(for: .milliseconds(300))  // several animation ticks
    #expect(!changed.value)
  }

  @Test func minutesLeftAreRoundedUp() async throws {
    let state = makeAppState()
    #expect(state.minutesLeft == nil)
    state.activate(spec: ActivationSpecs.twoHours.spec, now: Date() - 90)
    #expect(state.minutesLeft == 120)  // as of when it started
    try await Task.sleep(for: .milliseconds(200))  // the next tick sees 118.5 min to go
    #expect(state.minutesLeft == 119)
    state.deactivate()
    #expect(state.minutesLeft == nil)
  }

  @Test func foreverHasNoMinutesLeft() {
    let state = makeAppState()
    state.activate(spec: ActivationSpecs.forever.spec)
    #expect(state.minutesLeft == nil)
  }

  @Test func theOpenMenuStillUpdatesWhenTheMinuteChanges() async throws {
    let state = makeAppState()
    // Started 59.95 s ago: in a moment there are 119 minutes left, not 120.
    state.activate(spec: ActivationSpecs.twoHours.spec, now: Date() - 59.95)
    #expect(state.minutesLeft == 120)
    let changed = watchMenu(of: state)
    try await Task.sleep(for: .milliseconds(300))
    #expect(changed.value)
    #expect(state.minutesLeft == 119)
  }
}
