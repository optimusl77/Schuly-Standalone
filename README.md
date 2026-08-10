# <p align="center">Schuly Standalone</p>
<p align="center">
  <img src="./assets/app_icon.png?v=0015919" width="200" alt="Schuly Standalone Logo">
</p>
<p align="center">
  <strong>Schuly, running fully on-device - no backend server required</strong>
</p>
<p align="center">
  <a href="https://github.com/schulydev/Schuly/blob/main/LICENSE"><img src="https://img.shields.io/github/license/schulydev/Schuly?color=3da8ff" alt="License"/></a>
  <a href="#installation"><img src="https://img.shields.io/badge/Selfhost-Not%20needed-3da8ff.svg" alt="No backend needed"/></a>
</p>

This is a fork of **[schulydev/Schuly](https://github.com/schulydev/Schuly)**, a mobile app that provides a superior alternative to the official Schulnetz client. All credit for the original app, its design, and its feature set goes to the upstream project and its maintainer, **[PianoNic](https://github.com/PianoNic)**.

> [!IMPORTANT]
> This project is **NOT** affiliated with, endorsed by, or connected to Schulnetz, Centerboard AG, schulydev, or PianoNic. It's an independent, unofficial fork. Like the upstream project, it is an unofficial client that talks to Schulnetz's own systems on your behalf.

## What's different in this fork

Upstream Schuly (in the version this fork is based on, `v2.7.0`) talks to Schulnetz through a hosted or self-hosted **[SchulwareAPI](https://github.com/PianoNic/SchulwareAPI)** backend, which proxies authentication and data requests. That backend is what makes the "superior alternative" experience possible (unified login, Microsoft/Entra SSO support, a clean REST API over Schulnetz's own quirks) - but it also means a server is a required, always-on part of the chain, and it's a dependency this fork does not need or want.

This fork removes that dependency entirely for schools using **Microsoft/Entra SSO**:

- **Login talks directly to your school's own Schulnetz instance.** The Microsoft sign-in step happens in an embedded, on-device WebView (a real browser, so it passes Microsoft's normal sign-in and MFA prompts natively) instead of being brokered by a server. PKCE and the token exchange are done entirely on-device, straight against Schulnetz's own `/authorize.php` and `/token.php`.
- **Every data request goes straight to Schulnetz's REST API** (`{your-school}/rest/v1/...`) with the token from that login - grades, exams, absences, agenda, notifications, settings, lateness, and the student ID card. No proxy, no intermediate server, no SchulwareAPI URL to configure.
- **The old email/password and "API Base URL" login path is gone.** It routed through the same backend, so it doesn't fit a backend-free fork. Only school URL + Microsoft sign-in remains.

Everything else - the UI, the multi-account switching, the theming, the feature set - is unchanged from upstream `v2.7.0`.

## Screenshots

<p align="center">
  <img src="./assets/screenshot_home.png" width="19%" alt="Start Screen">
  <img src="./assets/screenshot_agenda.png" width="19%" alt="Agenda Calendar">
  <img src="./assets/screenshot_grades.png" width="19%" alt="Grades View">
  <img src="./assets/screenshot_absences.png" width="19%" alt="Absences Tracker">
  <img src="./assets/screenshot_account.png" width="19%" alt="Account Profile">
</p>

## Features

- Grades, agenda, absences, student ID card
- Multi-user account switching
- Material 3 theming with dark/light mode
- Tons of customization options
- Push notifications
- Android and iOS support
- No backend server anywhere in the loop - the app is the whole client

## Installation

Build it yourself with Flutter (see `src/Schuly.App`), or grab an APK/IPA if one has been shared with you. There are no upstream release binaries for this fork.

## Configuration

1. Open the app
2. Enter your school's Schulnetz URL (pre-filled with `https://schulnetz.bbbaden.ch` - change it to your own school's URL)
3. Sign in with Microsoft

That's it - no server URL, no separate account to configure.

## Credits

- **[schulydev/Schuly](https://github.com/schulydev/Schuly)** and **[PianoNic](https://github.com/PianoNic)** - the original app this is forked from, and all of its design and functionality.
- **[SchulwareAPI](https://github.com/PianoNic/SchulwareAPI)** by PianoNic - reverse-engineering its (open-source) proxy logic is what made a direct, backend-free connection to Schulnetz possible in this fork.
- **[Entrance](https://github.com/PianoNic/Entrance)** (`ms-entrance`) by PianoNic - its login flow documented the Microsoft/Entra + Schulnetz OAuth handshake this fork replicates on-device via WebView instead of headless HTTP.

---
<p align="center">Original app made with ❤️ by <a href="https://github.com/Pianonic">PianoNic</a></p>
<p align="center">
  <a href="https://buymeacoffee.com/pianonic"><img src="https://img.shields.io/badge/-buy_me_a%C2%A0coffee-gray?logo=buy-me-a-coffee" alt="Buy Me A Coffee"/></a>
</p>
