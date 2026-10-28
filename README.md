# Home Base

Control the screens, computers, lights and media in the house from any of our devices.

The always-on Mac Mini runs the **hub**, the single source of truth. Every app (iPhone, iPad, Mac, Windows) talks only to the hub, and only the hub talks to devices.

## Layout

| Folder | What's in it |
| --- | --- |
| `hub/` | The Python service on the Mac Mini, with one adapter per kind of device |
| `apps/` | The SwiftUI app (iPhone, iPad, Mac) and the Windows app, coming in milestones 3 and 4 |
| `shared/protocol/` | The messages apps and hub exchange |
| `docs/` | Setup and device notes |

## Status

- **Milestone 1**: hub and the LG TV. Setup: [docs/setup-hub.md](docs/setup-hub.md).
- **Milestone 2**: Sony TV, Apple TV, and waking, sleeping and shutting down the computers. Setup: [docs/setup-devices.md](docs/setup-devices.md).
- Next: the SwiftUI app for iPhone, iPad and Mac, with pairing and live sync.
