# DexBar

A lightweight macOS menu bar app that displays your Dexcom CGM glucose readings at a glance.

![macOS](https://img.shields.io/badge/macOS-menu%20bar%20app-blue)
![Swift](https://img.shields.io/badge/Swift-SwiftUI%20%2B%20AppKit-orange)

## Features

- Live glucose reading and trend arrow in the menu bar, updated every 60 seconds
- Popover chart showing up to 24 hours of readings
- Low glucose warning (highlighted in red below 4.0 mmol/L)
- Credentials stored securely in the system Keychain
- Optional launch at login

## Requirements

- macOS (Apple Silicon or Intel)
- A [Dexcom Share](https://www.dexcom.com/en-us/dexcom-share) account

> **Note:** DexBar currently only works for users **outside the United States and Asia-Pacific** regions. This is a limitation of the Dexcom Share API endpoint used (`shareous1.dexcom.com`). US and Asia-Pacific users connect through a different regional endpoint which is not yet supported.

## Getting Started

1. Clone the repository and open `DexBar.xcodeproj` in Xcode.
2. Build and run the app.
3. Right-click the status bar icon and choose **Preferences**.
4. Sign in with your Dexcom account credentials (or the account owner's credentials if you are a follower).

## Authentication

Authentication is performed against the Dexcom Share API using a two-step flow: account credentials are exchanged for an account ID, which is then exchanged for a session ID used for all subsequent data requests.

This project's authentication implementation was informed by [**pydexcom**](https://github.com/gagebenne/pydexcom?tab=readme-ov-file) — a Python wrapper for the Dexcom Share API. For a detailed explanation of how the authentication flow works and what the API endpoints expect, that project's documentation is an excellent reference.

## Contributing

Have an idea for a new feature or found a bug?

- **Feature request:** [Open an issue](../../issues/new) describing what you'd like to see and why it would be useful.
- **Bug report:** [Open an issue](../../issues/new) with steps to reproduce, your macOS version, and any relevant log output.
- **Pull request:** Contributions are welcome. Fork the repo, make your changes on a feature branch, and open a pull request with a clear description of what you changed and why.

## License

MIT License

Copyright (c) 2025 Oskar Hagberg

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
