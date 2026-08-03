# Shared engine lifecycle smoke checklist

Run this checklist on an iOS 18 or newer simulator after regenerating the FFI
artifact from `RadrootsFFI/source.lock`. Use a disposable app installation and
do not enter a production identity.

## Automated prerequisite

- Run the `Radroots` scheme unit tests on an arm64 simulator.
- Confirm the app and `SharedEngineLifecycleTests` both pass.
- Confirm the generated binding has no post-stream start, next, or stop API.

## Host custody and prompts

- Create a local identity and accept the Apple user-presence prompt.
- Background and foreground the app; confirm the identity remains locked until
  the Apple prompt succeeds and no secret appears in logs or diagnostics.
- Cancel the prompt once; confirm the UI reports a bounded error and does not
  replace the selected Keychain item.
- Sign out; confirm the runtime identity is cleared while the Keychain-backed
  identity remains available for a later unlock.
- Reset local identity; confirm the Keychain item, public metadata, pending
  background work, and in-memory signer are all removed.

## Relay, cancellation, and background behavior

- Configure one valid relay and confirm read/write operations report
  `Available`; no connection count is displayed or exported.
- Open and close the feed; confirm polling stops on disappearance and resumes
  with bounded fetches when reopened.
- Send the app to the background during a fetch; confirm Apple background task
  scheduling remains host-owned and the app returns without a stuck spinner.
- Terminate the app from the simulator switcher; confirm the next launch starts
  a fresh runtime and requires host restoration of the selected identity.

## Logging and error presentation

- Exercise invalid secret, invalid relay, and unavailable network paths.
- Confirm SDK errors are presented through their secret-safe message and
  capability category, with no secret, raw event payload, or private path in
  unified logging, file logging, diagnostics JSON, or the UI.
- Export diagnostics and confirm format
  `radroots_field_ios_diagnostics_v2` contains only configured relays,
  categorical source/sink availability, and the bounded last error.
