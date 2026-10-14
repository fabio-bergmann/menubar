# Menubar

Decides which menu bar icons show on macOS 27. Every app with a menu bar icon
gets one of three tiers:

| Tier | The app's icons |
| --- | --- |
| **Always** | stay in the menu bar |
| **On click** | show when you click Menubar's chevron, and hide again once the menu bar has been left alone for a while |
| **Never** | never show |

Right-click the chevron for Settings, where every app with a menu bar icon is
listed with its tier. That's all it does.

## How it hides

macOS 27 draws the whole menu bar itself, so the old trick of pushing icons
off the edge no longer works. It does have its own hiding, built for exam
("assessment") mode: an app hands it a list of the apps allowed to show
icons, and macOS hides the rest. Menubar keeps that list up to date. It's a
private API, so a macOS update could move it; Menubar then hides nothing and
says so in Settings, rather than hiding the wrong things. Quitting Menubar,
or a crash, shows every icon again.

Two limits come with it. Tiers are per app: an app with two icons hides or
shows both. And Apple's own icons (clock, Wi-Fi, Battery, Sound, Control
Center) always stay; switch those off in System Settings › Control Center.

## Permissions

Accessibility, to list which apps have menu bar icons. Hiding works without
it, from a shorter list (apps without a Dock icon).

## Install and update

Needs Xcode. There is no Apple Developer licence behind this, so the app is
built and signed locally rather than downloaded:

```sh
scripts/release-local.sh
```

That builds the committed `main`, installs `/Applications/Menubar.app` and
opens it. Settings › Updates rebuilds from `origin/main` later.
Quit Bartender (or any other menu bar manager) first: two of them undo each
other's hiding.
