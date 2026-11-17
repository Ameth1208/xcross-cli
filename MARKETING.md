# Marketing / Publicity Templates

Use these to make XCross CLI more visible. Replace placeholders as needed.

## Reddit (r/FlutterDev, r/programming, r/commandline)

**Title:** XCross CLI – one-line install for Flutter on Windows & Linux (with interactive menu)

**Body:**
```
Hey everyone,

I built XCross CLI – a terminal tool that makes setting up and running Flutter apps effortless, especially on Windows with xcross for iOS.

Features:
- One-line install (no admin): irm ... | iex  /  curl ... | bash
- Interactive menu with arrows + command palette (/)
- Bilingual (English/Spanish)
- xcross integration: Swift, SDK import, precache
- USB/Wi-Fi tunnels, signing diagnostics
- Windows: install an existing signed IPA over USB with xcm install "app.ipa" (no certificate file prompt)
- Windows: Flutter IPA builds, optional zsign re-signing, and Git project updates
- MIT licensed, open source

Repo: https://github.com/Ameth1208/xcross-cli
Live preview: https://ameth1208.github.io/xcross-cli/

Feedback welcome!
```

## Windows 1.3 update

Existing IPA installation is now one command: `xcm install "app.ipa"`. It uses pymobiledevice3 over USB without requesting a certificate file, provisioning profile or Apple ID. The IPA must already have a valid signature for the target iPhone; iOS enforces code signing. Re-signing through zsign is a separate optional operation.

Also included: `xcm ipa build --mode release`, `xcm project update` for the current Git checkout, and `xcm update-cli --local` for local CLI changes. These new commands are Windows features; the Linux helper retains its existing behavior.

## Twitter / X

```
🚀 XCross CLI – the easiest way to build Flutter apps on Windows & Linux.

One-line install, interactive menu, xcross integration, bilingual (EN/ES).

Try it: https://github.com/Ameth1208/xcross-cli
Demo: https://ameth1208.github.io/xcross-cli/

#Flutter #Dart #OpenSource #CLI
```

## Dev.to / Medium

**Title:** Building a Flutter CLI that makes iOS development on Windows effortless

Write a post explaining:
1. The problem (Flutter iOS on Windows is hard)
2. How XCross CLI solves it (one-line install, menu, xcross)
3. Demo GIF + screenshot
4. Link to repo and live preview

## Product Hunt

Tagline: "One-line install for Flutter on Windows & Linux"
Description: "XCross CLI gives you a beautiful terminal experience for Flutter development. Interactive menu, xcross integration, bilingual, open source."

## Hacker News (Show HN)

Title: Show HN: XCross CLI – easiest Flutter setup for Windows/Linux
URL: https://github.com/Ameth1208/xcross-cli

## Where to post

- Reddit: r/FlutterDev, r/Flutter, r/commandline, r/programming
- Hacker News: Show HN
- Product Hunt
- Dev.to, Medium, Hashnode
- Twitter/X, LinkedIn
- Flutter community Discord/Slack
- Awesome Flutter lists (PR to add)
- YouTube: short demo video

## Tips to get more stars

- Add a demo GIF to README (done: docs/cli-demo.gif)
- Respond to issues/PRs quickly
- Add "good first issue" labels
- Cross-post in multiple communities (stagger, don't spam)
- Ask friends/colleagues to star
- Add to awesome lists via PR
