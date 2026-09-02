# Setup

## Requirements

- macOS 26+
- **Xcode 26** (App Store). Command Line Tools alone are not enough — the project
  needs the iOS SDK, the Simulator, and the Metal compiler.
- No package dependencies. Nothing to install.

## Build & run

```bash
open Plate/Plate.xcodeproj
```
Select an iPhone simulator and hit ⌘R. Deployment target is iOS 18.0.

From the command line:
```bash
xcodebuild -project Plate/Plate.xcodeproj -scheme Plate \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

## Keys (all optional)

The app is fully functional with no keys at all: a local rule-based agent, a bundled
nutrition database, and procedurally-rendered food imagery. Adding keys upgrades
those three pieces in place.

| Setting | Enables | Get one |
|---|---|---|
| Anthropic API key | The real conversational agent (`claude-opus-5`) | console.anthropic.com |
| Gemini API key | Generated studio food photography (`gemini-3.1-flash-image`) | aistudio.google.com |
| OpenAI API key | Alternate image backend (`gpt-image-1-mini`) | platform.openai.com |
| USDA FDC key | Expands nutrition lookup beyond the bundled DB | fdc.nal.usda.gov |

Enter them in **Settings → Connections** inside the app. They are stored in the
Keychain (`kSecAttrAccessibleAfterFirstUnlock`), never in UserDefaults, never logged,
and never leave the device except to the vendor they belong to.

## Verification without Xcode

`scripts/typecheck.sh` runs `swiftc -typecheck` over the platform-agnostic sources
against the macOS SDK. It catches the large majority of Swift-level mistakes
(typos, signature drift, missing members) without an iOS toolchain. It cannot
verify UIKit-only code, Metal shaders, asset catalogs, or anything about layout.
It is a smoke test, not a substitute for building.
