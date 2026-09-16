# Portkeeper identity

Portkeeper uses a harbour lighthouse as a visual metaphor for local ports: it watches what is active and helps a developer find a clear route. The light is a signal, not a mascot or a literal port gate.

The app icon is a stone lighthouse on midnight water with one amber lantern. Its silhouette stays legible at menu bar scale. In the menu bar the lantern is dark when no managed service is active, glows steadily while a service runs, and blinks when an issue is detected. Ordered-dither shadowing gives it a coding and printmaking character without making text or controls grainy.

| Role | Colour | Hex |
| --- | --- | --- |
| Background | Graphite harbour | `#0E1720` |
| Raised surfaces | Slate | `#1F2B34` |
| Primary text | Warm stone | `#F5F1E2` |
| Secondary text | Steel mist | `#A7B8B8` |
| Signal and warnings | Lantern amber | `#E7B158` |
| Running and links | Sea glass | `#85BFB8` |

The interface uses the macOS system font for names and actions and a monospaced system font for ports, commands, groups, and process details. Native Liquid Glass marks navigation and primary actions on macOS 26; older macOS versions use system material and bordered buttons. The anchored popover animates between the service list, editors, output, and confirmations. Service and port rows remain quiet, flat, and easy to scan. The dither is limited to the backdrop so it never competes with diagnostics.
