# Validation

## Automated (no desktop changes)

`ctest --test-dir build -C Release --output-on-failure` covers:

- Configuration preservation and removal of Zebar launch commands.
- Inline and block YAML command arrays, idempotence and unsupported-input rejection.
- Installation into a path containing spaces, startup shortcut and workspace import.
- Update preserving the first original backup.
- Uninstall refusing to overwrite user edits, then restoring exact original content.

Temporary fixtures are retained under `.test-output/` for inspection and ignored
by Git. No live GlazeWM configuration is used in these tests.

## Desktop acceptance

With a test GlazeWM setup:

1. Click an occupied and an empty configured workspace; verify focus highlighting.
2. Shift-click: verify it only switches and does not move a window.
3. Scroll and right-click the bar: verify no workspace switch or menu.
4. Verify date/time around a minute boundary.
5. Reconnect after restarting GlazeWM; check the disconnected indicator.
6. Connect/remove monitors, test mixed DPI, and fullscreen/unfullscreen.
7. Sign out/in and verify exactly one sidebar and one window manager start.
8. Uninstall; verify original bar/configuration and startup state.
