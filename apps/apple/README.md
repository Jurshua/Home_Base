# Home Base for Mac, iPhone and iPad

One SwiftUI project, built Mac first, in the approved v3 "Apple TV style": black ground, full-bleed artwork hero, glass capsule tabs, cards that lift when chosen, white means on, no visible scroll bars.

## Run it on the Mac

1. Open `HomeBase.xcodeproj` in Xcode 16 or later.
2. Pick the **HomeBase** scheme and **My Mac**, then press ⌘R.

On the Mac Mini it connects to the hub at `localhost:4900` on its own. Anywhere else, open Settings (⌘,) and type the Mac Mini's address. An empty address runs **demo mode** with pretend devices, so you can try the design anywhere.

The hub only listens on the Mac Mini itself until milestone 3 adds pairing. To try the app from the MacBook Air or an iPhone before then, set `host = "0.0.0.0"` in the hub's `hub.toml` on the Mac Mini and restart it.

## What works

- **Home**: the chosen screen as the hero (switch screens from the eyebrow menu), Screens, apps to open on that screen, and a tile for every hub device. Opening an app turns its screen on first.
- **Remote** (⇧⌘R or the Remote button): its own small window. Swipe or use the arrow keys, Return selects, Esc goes back; volume, mute, inputs and power.
- **⌘K**: type to turn screens on or off, open an app on a screen, switch inputs, or jump to a tab.
- **Media**: every app for each screen.
- Lights, Scenes, Vault and Pages are placeholders until their milestones.

## Layout

| Folder | What's in it |
| --- | --- |
| `Hub/` | The live connection to the hub, device models, and how devices map to screens |
| `Design/` | Colours, glass, lift buttons, pills, shelves |
| `Mac/` | The Mac window, its header and the ⌘K palette |
| `Home/`, `Remote/`, `Tabs/` | Shared screens and the iPhone layout |

On macOS 26 and iOS 26 the glass is real Liquid Glass; on earlier systems it falls back to a blur material.
