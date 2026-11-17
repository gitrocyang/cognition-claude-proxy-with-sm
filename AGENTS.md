# Repository guidance

This fork contains a zero-dependency Node.js proxy for the Anthropic Messages
API and a macOS 14+ SwiftUI menu bar app, Devin Proxy Manager. The proxy must
remain usable without the app.

## Code layout

- `src/` contains the proxy, protocol translation, model catalog, and Devin
  CLI credential lookup.
- `bin/dclaude` is the macOS/Linux Claude Code wrapper. `bin/dclaude.bat` is
  the Windows wrapper.
- `macos/DevinProxyManager/` contains the native menu bar app.
- `scripts/build-macos.sh` builds the local `.app`; `scripts/build-dmg.sh`
  packages it into a local DMG.

## Service and safety rules

- The manager owns only its user LaunchAgent label
  `com.gitrocyang.devin-proxy-manager.proxy`. Never terminate processes by a
  broad name such as `node` or `server.js`.
- Check launchd state, process ownership, and `/health` before reporting a
  healthy managed proxy. Do not treat an occupied port as proof of ownership.
- `dclaude` must not start a separate proxy while the managed LaunchAgent is
  installed, including after the user explicitly stops the service.
- Keep the default listener on loopback. Do not modify official Claude Code,
  Devin CLI, or other model configurations.
- Never commit credentials, API keys, authentication headers, request dumps,
  or machine-specific paths. Environment checks may check credential file
  access but must not display its contents.

## Verification

- Run `npm run test:unit` for the proxy and wrapper tests.
- Run `swift test` from `macos/DevinProxyManager` for Swift unit tests.
- The opt-in LaunchAgent integration test runs on port `18765` with
  `CCP_MANAGER_INTEGRATION=1 swift test --filter testLaunchAgentLifecycleOnIsolatedPort`.
  Confirm that label and port are free before running it.
- Run `./scripts/build-macos.sh` or `./scripts/build-dmg.sh` for local artifacts.
- Do not use a real Devin inference request as a routine automated test.
