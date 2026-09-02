# Progress log

Newest first. One line per commit-sized unit of work.

## Environment note (blocker)
Xcode is **not installed** on this machine — only Command Line Tools
(`/Library/Developer/CommandLineTools`). That means no `xcodebuild`, no iOS SDK,
no Simulator, and no `metal` compiler. Swift 6.2 + the macOS SDK *are* available,
so Swift sources can be type-checked against the macOS SDK as a partial verification
(see `06-SETUP.md` → "Verification without Xcode"), but the app cannot be compiled
or run until Xcode is installed.

## Log

- [ ] Simulator verification pass (blocked on Xcode)
- [x] `docs/` — overview, architecture, design system
- [x] Repo scaffold + Xcode project (file-system-synchronized, objectVersion 77)
