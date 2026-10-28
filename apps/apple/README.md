# Home Base for Mac, iPhone and iPad

One SwiftUI project. iPad uses the Mac layout, iPhone has its own tabs. Built Mac first, in the approved v3 "Apple TV style": black ground, full-bleed artwork hero, glass capsule tabs, cards that lift when chosen, white means on, no visible scroll bars.

## Run it on the Mac

1. Open `HomeBase.xcodeproj` in Xcode 16 or later.
2. Pick the **HomeBase** scheme and **My Mac**, then press ⌘R.

On the Mac Mini it connects to the hub at `localhost:4900` on its own. Anywhere else, open Settings (⌘,) and type the Mac Mini's address. An empty address runs **demo mode** with pretend devices, so you can try the design anywhere.

The hub only listens on the Mac Mini itself until milestone 3 adds pairing. To try the app from the MacBook Air or an iPhone before then, set `host = "0.0.0.0"` in the hub's `hub.toml` on the Mac Mini and restart it.

## Put it on an iPhone or iPad

Xcode lives on the MacBook Air, so do this there. A free Apple ID is enough; the app then needs re-installing every 7 days until the paid developer account is set up.

1. Plug the iPhone or iPad into the Air with a cable and tap **Trust** on it.
2. On the iPhone or iPad, turn on Settings › Privacy & Security › **Developer Mode** and let it restart.
3. In Xcode, open `HomeBase.xcodeproj`, click the **HomeBase** project › **Signing & Capabilities**, and pick your Apple ID under **Team** (Xcode › Settings › Accounts to add it).
4. Choose the device at the top of the window and press ⌘R.
5. The first time, the device says the developer isn't trusted: Settings › General › VPN & Device Management › your Apple ID › **Trust**. Then open Home Base.
6. Home Base asks to find devices on your local network: tap **Allow**. In the app, open the hub tile at the bottom of Home and type the Mac Mini's address.

Until milestone 3 adds pairing, the hub only answers on the Mac Mini itself. To reach it from a phone, set `host = "0.0.0.0"` in `~/Library/Application Support/HomeBase/hub.toml` on the Mac Mini and restart the hub.

## What works

- **Home**: the chosen screen as the hero (switch screens from the eyebrow menu), Screens, apps to open on that screen, and a tile for every hub device. Opening an app turns its screen on first.
- **Remote** (⇧⌘R or the Remote button): its own small window. Swipe or use the arrow keys, Return selects, Esc goes back; volume, mute, inputs and power.
- **⌘K**: type to turn screens on or off, open an app on a screen, switch inputs, or jump to a tab.
- **Media**: the screen wall. Pick an app (or drag it) and tap the screen it should play on.
- Lights, Scenes, Vault and Pages are placeholders until their milestones.

## Layout

| Folder | What's in it |
| --- | --- |
| `Hub/` | The live connection to the hub, device models, and how devices map to screens |
| `Design/` | Colours, glass, lift buttons, pills, shelves |
| `Mac/` | The Mac window, its header and the ⌘K palette |
| `Home/`, `Remote/`, `Tabs/` | Shared screens and the iPhone layout |

On macOS 26 and iOS 26 the glass is real Liquid Glass; on earlier systems it falls back to a blur material.
