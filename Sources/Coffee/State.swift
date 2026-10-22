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
import Observation
import os

@Observable
@MainActor
final class AppState {
  private enum DefaultsKey {
    static let disableAfterSuspend = "DisableAfterSuspend"
    static let loginItemEnabled = "LoginItemEnabled"
    static let keepScreenOn = "KeepScreenOn"
    static let steamCurls = "SteamCurls"
  }

  private(set) var isActive: Bool = false
  private(set) var activeSpec: ActivationSpec? = nil
  private(set) var activatedAt: Date? = nil
  private(set) var isDisableAfterSuspendEnabled: Bool = false
  private(set) var isLoginItemEnabled: Bool = false
  /// Whether brewing also keeps the screen on. When off, the Mac stays awake but the screen may turn off.
  private(set) var isKeepScreenOnEnabled: Bool = true
  /// How many steam curls the menu bar cup shows.
  private(set) var steamCurls: SteamCurls = .three
  /// Set from "Turn Off Screen Now" until the screen wakes up again.
  private(set) var isScreenForcedOff: Bool = false
  private(set) var powerAssertion: PowerAssertion? = nil
  private(set) var deactivationTask: Task<Void, Never>? = nil
  /// When the steam loop began; the steam's opacity follows from the time since.
  private(set) var steamLoopStart: Date = .now
  private(set) var isScreenAsleep: Bool = false
  private(set) var animationTask: Task<Void, Never>? = nil
  /// The time as of the last animation tick, so views showing a countdown stay current.
  private(set) var now: Date = .now
  /// The time left as the menu shows it: whole minutes, rounded up, or nil without a time limit.
  /// The open menu is rebuilt whenever something it shows changes, and rebuilding it on every
  /// animation tick made its submenus' hover highlight flicker; this changes once a minute.
  private(set) var minutesLeft: Int? = nil

  /// The start or stop animation currently playing on the icon, if any.
  private(set) var transition: CupTransition? = nil

  var shouldAnimate: Bool { (isActive || transition != nil) && !isScreenAsleep }

  var assertionType: Assertion {
    isKeepScreenOnEnabled && !isScreenForcedOff ? .NoDisplaySleep : .PreventUserIdleSystemSleep
  }

  private static let assertionName = "Brewing Coffee"

  private let defaults: UserDefaults
  private let sleepDisplay: @MainActor () -> Bool
  @ObservationIgnored private var observers: [NSObjectProtocol] = []

  init(
    defaults: UserDefaults = .standard,
    sleepDisplay: @escaping @MainActor () -> Bool = Display.sleepNow
  ) {
    self.defaults = defaults
    self.sleepDisplay = sleepDisplay
    isKeepScreenOnEnabled = defaults.object(forKey: DefaultsKey.keepScreenOn) as? Bool ?? true
    steamCurls = defaults.string(forKey: DefaultsKey.steamCurls).flatMap(SteamCurls.init) ?? .three
    isDisableAfterSuspendEnabled = defaults.bool(forKey: DefaultsKey.disableAfterSuspend)
    isLoginItemEnabled = defaults.bool(forKey: DefaultsKey.loginItemEnabled)
  }

  // MARK: - Activation

  func activate(spec: ActivationSpec, now: Date = .now) {
    // If already active with the same spec, toggle off
    if isActive && activeSpec == spec {
      turnOff(now: now)
      return
    }

    // Refill from wherever the cup is now, then release any existing assertion first
    let fromLevel = cupFrame(at: now).level
    release()

    powerAssertion = PowerAssertion(named: Self.assertionName, type: assertionType)

    if spec.timeInterval > 0 {
      os_log("Scheduling deactivation in %f seconds", spec.timeInterval)
      deactivationTask = Task { @MainActor in
        try? await Task.sleep(for: .seconds(spec.timeInterval))
        guard !Task.isCancelled else { return }
        os_log("Timer fired, deactivating")
        self.deactivate()
      }
    }

    isActive = true
    activeSpec = spec
    activatedAt = now
    self.now = now
    updateMinutesLeft(at: now)
    transition =
      isScreenAsleep
      ? nil : CupTransition(kind: .starting, startedAt: now, fromLevel: fromLevel, steam: .hidden)
    // The steam loop starts when the start animation ends, with the steam at full strength.
    steamLoopStart = transition?.end ?? now
    refreshAnimation()
    os_log("Activated")
  }

  /// Releases the Mac at once. The cup takes a moment longer to empty on screen.
  func deactivate(now: Date = .now) {
    stop(now: now, animation: .stopping)
  }

  /// Turned off by hand: releases the Mac at once, and the cup tips over and spills.
  func turnOff(now: Date = .now) {
    stop(now: now, animation: .spilling)
  }

  private func stop(now: Date, animation kind: CupTransition.Kind) {
    guard isActive else { return }
    let shown = cupFrame(at: now)
    release()
    self.now = now
    transition =
      isScreenAsleep
      ? nil : CupTransition(kind: kind, startedAt: now, fromLevel: shown.level, steam: shown.steam)
    refreshAnimation()
    os_log("Deactivated")
  }

  private func release() {
    powerAssertion = nil
    isScreenForcedOff = false
    deactivationTask?.cancel()
    deactivationTask = nil
    isActive = false
    activeSpec = nil
    activatedAt = nil
    updateMinutesLeft(at: .now)
  }

  // MARK: - Screen

  func setSteamCurls(_ curls: SteamCurls) {
    defaults.set(curls.rawValue, forKey: DefaultsKey.steamCurls)
    steamCurls = curls
  }

  func setKeepScreenOn(_ enabled: Bool) {
    defaults.set(enabled, forKey: DefaultsKey.keepScreenOn)
    isKeepScreenOnEnabled = enabled
    syncAssertion()
  }

  /// Turns the screen off right away while the Mac stays awake. Does nothing unless brewing.
  func turnOffScreenNow() {
    guard isActive else { return }
    // Swap first: a display assertion would keep the screen on.
    isScreenForcedOff = true
    syncAssertion()
    if !sleepDisplay() {
      isScreenForcedOff = false
      syncAssertion()
    }
  }

  /// Makes the held assertion match `assertionType`. The new assertion is created before the
  /// old one is released, so the Mac can't idle-sleep in between.
  private func syncAssertion() {
    guard isActive, powerAssertion?.type != assertionType else { return }
    powerAssertion = PowerAssertion(named: Self.assertionName, type: assertionType)
  }

  // MARK: - Coffee Level

  // Measured against the wall clock so the level stays right after the Mac sleeps.
  // The deactivation timer's ContinuousClock counts sleep time too, so the two agree.
  func coffeeLevel(at now: Date) -> Double {
    guard let activeSpec, let activatedAt else { return 0 }
    return activeSpec.coffeeLevel(elapsed: now.timeIntervalSince(activatedAt))
  }

  /// Sets `minutesLeft` only when it changes: setting an observed property, even to the value it
  /// already has, would rebuild the open menu.
  private func updateMinutesLeft(at now: Date) {
    let minutes = remainingTime(at: now).map { Int(($0 / 60).rounded(.up)) }
    if minutes != minutesLeft { minutesLeft = minutes }
  }

  func remainingTime(at now: Date) -> TimeInterval? {
    guard let activeSpec, let activatedAt, activeSpec.timeInterval > 0 else { return nil }
    return max(0, activeSpec.timeInterval - now.timeIntervalSince(activatedAt))
  }

  // MARK: - Animation

  /// What the menu bar cup shows at `now`: the start or stop animation while one is playing,
  /// otherwise the real coffee level and, while brewing, the steam loop.
  func cupFrame(at now: Date) -> CupFrame {
    if let transition, now < transition.end {
      return transition.frame(at: now, level: coffeeLevel(at: now))
    }
    return CupFrame(
      level: coffeeLevel(at: now),
      steam: isActive ? CupAnimation.steam(at: now.timeIntervalSince(steamLoopStart)) : .hidden)
  }

  /// Restarts the animation loop if the cup should be moving, otherwise stops it.
  /// The label redraws on every tick, which also keeps the coffee level and the steam current.
  func refreshAnimation() {
    animationTask?.cancel()
    animationTask = nil
    guard shouldAnimate else { return }

    animationTask = Task { @MainActor [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: CupAnimation.tick)
        guard !Task.isCancelled, let self else { return }

        let now = Date.now
        self.now = now
        self.updateMinutesLeft(at: now)
        if let transition = self.transition, now >= transition.end {
          self.transition = nil
          if !self.isActive {
            self.refreshAnimation()
            return
          }
        }
      }
    }
  }

  func handleScreensDidSleep() {
    os_log("Screens went to sleep")
    isScreenAsleep = true
    transition = nil  // nobody is watching, so skip to the end
    refreshAnimation()
  }

  func handleScreensDidWake() {
    os_log("Screens woke up")
    isScreenAsleep = false
    if isScreenForcedOff {
      isScreenForcedOff = false
      syncAssertion()
    }
    refreshAnimation()
  }

  // MARK: - System Events

  func handleSystemWake() {
    guard isDisableAfterSuspendEnabled else { return }
    os_log("System wakeup detected, disabling according to config")
    deactivate()
  }

  func observeSystemEvents() {
    let center = NSWorkspace.shared.notificationCenter
    observers.append(
      center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) {
        [weak self] _ in
        MainActor.assumeIsolated { self?.handleSystemWake() }
      })
    observers.append(
      center.addObserver(
        forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main
      ) {
        [weak self] _ in
        MainActor.assumeIsolated { self?.handleScreensDidSleep() }
      })
    observers.append(
      center.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main)
      {
        [weak self] _ in
        MainActor.assumeIsolated { self?.handleScreensDidWake() }
      })
  }

  // MARK: - Preferences

  func setDisableAfterSuspend(_ enabled: Bool) {
    defaults.set(enabled, forKey: DefaultsKey.disableAfterSuspend)
    isDisableAfterSuspendEnabled = enabled
  }

  func setLoginItemEnabled(_ enabled: Bool) {
    defaults.set(enabled, forKey: DefaultsKey.loginItemEnabled)
    isLoginItemEnabled = enabled
  }
}
