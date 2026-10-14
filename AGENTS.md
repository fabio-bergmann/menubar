# Menubar

A menu bar icon manager for macOS 27, kept small on purpose. Each app with a
menu bar icon gets a tier: **Always** visible, **On click** (shown while the
chevron's section is open), or **Never**. A click on the chevron opens and
closes the section; it closes by itself once the menu bar has been left alone
for the chosen delay. Right-click the chevron for Settings, which lists the
apps with their tiers. No search, no layouts, no spacing, no themes: Fabio
asked for exactly the three tiers, so features beyond them need his ask.

## Working agreement

- **`dev` is the working branch; commit there.** `main` is what gets
  installed: the Update button in Settings and `scripts/release-local.sh`
  both build `main` / `origin/main`. Merge `dev` → `main` only when Fabio
  asks, and never commit to `main` directly. No other branches or worktrees
  without asking.
- **A merge or push is not an install.** `scripts/release-local.sh` replaces
  `/Applications/Menubar.app` and relaunches it. Run it only when Fabio asks
  for a release or install in so many words, each time.
- **Releasing a version**, when asked: bump `CFBundleShortVersionString` in
  `Support/Info.plist`, commit, merge to `main`, push, then install.
- **Don't put Settings on Fabio's screen to check a change.** Render it
  instead (see Previews).
- **Testing hiding changes Fabio's real menu bar.** Keep it short (the
  `--try-hiding` probe releases after a few seconds) and say when you did it.

## The dev loop

`scripts/dev.sh` builds the working tree as "Menubar Dev" (bundle id
`dev.fabio.menubar.dev`, its own settings, an orange dot on the chevron) and
relaunches it within a few seconds of any change under `Sources/` or
`Support/`. Two copies would each ask macOS to hide a different set of icons,
so the script quits the installed Menubar while it runs and reopens it after.

- The dev build runs from `/Applications/Menubar Dev.app` (removed again on
  Ctrl-C). macOS only keeps an allowed app's icons for a copy in
  `/Applications`; one in `build/` or `~/Applications` hides its own chevron.
- It starts the app with `open`, not by running the binary: macOS only gives
  a menu bar item to an app it launched itself. Anything the app prints lands
  in `build/dev.log`.
- Every rebuild is a new ad-hoc signature, and macOS ties the Accessibility
  grant to the signature, so after a rebuild the grant is stale (still
  switched on in System Settings, doing nothing). Hiding doesn't need it; the
  full app list and the clock do. Settings' **Allow Accessibility…** runs
  `tccutil reset Accessibility <bundle id>` and prompts again. A stable
  self-signed certificate would end this, but adding one changes the login
  keychain, so that's Fabio's call.

## Commands

```sh
scripts/dev.sh                     # the dev loop above
swift build                        # compile
swift test                         # unit tests (MenubarCore)
swift run Menubar --render-previews /tmp/menubar-previews
"/Applications/Menubar Dev.app/Contents/MacOS/Menubar" --try-hiding <bundle id> [seconds]
                                   # hide one app's icons briefly; run from an
                                   # .app (a bare binary is answered but hides nothing)
scripts/build-app.sh               # build/Menubar.app, not installed
scripts/release-local.sh [ref]     # build a committed ref, install, relaunch
```

## Layout

- `Sources/MenubarCore`: what can be tested without a screen. `Tier`, and
  `VisibilityPlan`, which turns the tiers and the running apps into the list
  of apps macOS may show. The icon paths (`Icon`, `SVGPath`).
- `Sources/MenuBarRestriction`: the private macOS API, in Objective-C so its
  exceptions are caught. The only code that touches it.
- `Sources/Menubar`: the AppKit and SwiftUI shell. `MenuBarController`
  decides when to re-plan (tier change, chevron click, app launch or quit,
  wake, display change) and when the section closes again. `Concealer` holds
  the restriction and reports problems. `ClockClicks` keeps the clock opening
  Notification Center. `MenuBarInventory` lists apps with menu bar icons
  through Accessibility. `StatusItemController` and `ChevronRenderer` are the
  chevron; `SettingsWindowController` and `SettingsView` are Settings;
  `UpdateService` is the Update button.
- `Support/Info.plist`: the bundle's plist. The version lives here.
- `scripts/`: building and releasing.

## Things that are the way they are on purpose

- **Hiding is macOS's own, through a private API.** macOS 27 draws the whole
  menu bar out of process, so pushing icons off screen with a wide spacer
  item no longer works. What does: `MBAssessmentModeAssertion` in
  `MenuBarClientCore.framework`, the allowlist behind exam mode. Every app on
  the list keeps its icons; every other app's are hidden. Hidden Bar, Thaw
  3, Pelmet and others use the same one. It's checked at runtime and fails
  open: if it's missing or refused, nothing is hidden and Settings says why.
- **Tiers are by bundle id, never by position.** Icons are not moved or
  rearranged; their order is whatever the user ⌘-dragged it to. That keeps
  out the fragile part of other managers (faking drags), and it's why there
  is no layout editor.
- **The list is an allowlist, so new apps are hidden until re-planned.** The
  plan lists every running app that isn't hidden (Apple's background apps
  included: SystemUIServer hosts Siri, Time Machine and VPN), plus
  remembered visible ones, and is rebuilt the moment any app launches or
  quits (KVO on `runningApplications`; the launch notifications miss
  background agents). While nothing running needs hiding, no restriction is
  held at all, which also gives the clock and the indicators below back.
  The "New icons" tier is written to an app when it's first seen; until then
  it covers apps that just started, except Apple's own and background-only
  ones, which stay allowed (SystemUIServer's Siri and Time Machine are never
  listed, so they'd have no way back).
- **Every new restriction costs a connection until the app quits.**
  MenuBarClientCore opens one to MenuBarAgent per activation and keeps it
  after `invalidate()` and after the assertion is freed (measured: the
  server logs the close only at process exit). So the plan is kept stable:
  apps seen running earlier stay on the allowlist (`seen`), and only a
  never-seen app, a tier change, a chevron click or a lift makes a new one.
- **Restrictions from different apps add up.** macOS shows an icon if any
  held restriction allows it, so another manager running alongside brings
  back what it doesn't hide too. Settings warns about the known ones.
- **What macOS hides regardless.** While any restriction is held: Now
  Playing, Focus, the camera and microphone capsule (the dot stays), Live
  Activities, AirDrop, a running Timer. And a helper app outside
  `/Applications` (iStat Menus' used to be) loses its icon whatever its tier.
  Nothing here works around those; Settings mentions the first three.
- **The clock is pressed for macOS.** While icons are hidden MenuBarAgent
  ignores the clock (exam mode keeps Notification Center shut). `ClockClicks`
  watches clicks on it, lifts the restriction, waits 30 ms, presses the clock
  through Accessibility and restores the restriction: Hidden Bar's approach
  (PR #453, MIT), measured there. Hidden icons show for under a second while
  it does; macOS keeps them up that long however soon the restriction comes
  back. Without Accessibility the clock stays dead while icons are hidden.
- **New apps get looked at.** macOS can park an icon that arrives while a
  restriction is held (no width, off screen) until there's a moment with
  none. 2.5 s after a visible app starts, its icons are checked through
  Accessibility, and a parked one gets the restriction lifted until it lands
  (2.5 s at most). For the same reason the first restriction waits a second
  after launch, so the chevron is in the bar first.
- **The private API is wrapped defensively.** `MenuBarRestriction.m` checks
  every class and selector, catches exceptions, answers exactly once on the
  main queue and gives up after 3 s (a yes after that is dropped again). A
  new restriction is in place before the old one is dropped, so changing it
  never flashes the whole bar. Lifts (the clock, a parked new icon) are
  counted: while one is in progress a new plan is only noted, and the last
  `reassert()` puts the latest back.
- **Per app, not per icon.** macOS hides by bundle id, so an app's icons go
  together. A status item owned by a helper process is listed (and tiered)
  under the helper's own bundle id.
- **Apple's own items are always kept.** They're allowed by numeric id
  (`VisibilityPlan.allSystemItems`, 0-63); System Settings › Control Center
  already turns them on and off.
- **Accessibility is only for the list.** Without it Settings lists apps
  without a Dock icon (nearly all menu bar apps) plus remembered ones.
- **No Apple Developer licence.** The app is ad-hoc signed and never
  notarized, which only works because it is built on the machine it runs on.
  Updates rebuild from the checkout: `release-local.sh` exports a committed
  ref with `git archive` (never the working tree), builds it, bakes the
  commit and checkout path into Info.plist (`MBBuildSHA`, `MBRepoPath`) and
  installs it. The Update button compares that commit with `origin/main`.
- **No package dependencies.** The bundle is assembled by hand in
  `build-app.sh`, and SwiftPM resource bundles from dependencies don't end
  up where such a bundle looks for them.
- **Icons are Hugeicons Pro, stroke rounded**, the set CoWork uses, copied
  into `MenubarCore/Icon.swift` (that file says how to add one). They're
  licensed, so the repo stays private. The app icon is drawn in code
  (`PreviewRenderer.drawIcon`) and rendered into the bundle at build time.

## Previews

`--render-previews <dir>` writes PNGs of the chevron (closed, open, dev
build; light and dark) and of Settings (with and without notices, light and
dark), without opening a window. Read those to check a UI change. What they
can't show is behaviour: the real menu bar needs the dev build.
