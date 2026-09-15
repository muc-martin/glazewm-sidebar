# Native Sidebar for GlazeWM

A 40-pixel vertical Windows sidebar showing workspaces, time and date, with
optional Windows theme, CPU, RAM and battery widgets. Click a workspace to
switch, or the sun/moon icon to toggle Windows light/dark mode. There are no scroll
switching, modifier gestures, sidebar context menus or window-moving actions.

Written in C++ using Win32/GDI and the Windows WebSocket client. No browser,
Python, .NET application runtime, animation loop or persistent CLI helper.
Validation instructions are in [testing](docs/TESTING.md). There are no additional processes for the widgets.

## Status

Version 0.1.0, prepared for a first public release. Requires Windows x64 and GlazeWM.
Windows 10 1703+ APIs are used; Windows 10 compatibility remains unverified. Multi-monitor/mixed-DPI support and automatic WebSocket
reconnection are implemented; a multi-monitor acceptance test remains pending.

This replaces **Zebar's bar**, not GlazeWM's window manager. It deliberately
does not replace Zebar's general widget platform, tray widgets or media controls.

## Install

1. Install GlazeWM and run it once to create its configuration.
2. Extract the `native-sidebar-0.1.0-windows-x64.zip` package into a temporary folder.
3. Double-click **Install.cmd**. No administrator rights are needed.

Installation copies the app into `%LOCALAPPDATA%\Programs\NativeSidebar`,
creates Windows Startup and Start menu shortcuts and starts the new bar. The one-shot startup
script starts GlazeWM if necessary, then the sidebar, and exits. The sidebar
reconnects if the window manager is not ready yet.

The installer backs up the original GlazeWM configuration, removes Zebar/old
sidebar commands from its startup and shutdown lists, adds an ignore rule for
the native bar and sets the outer gaps to 52 px left / 8 px top. Other commands,
keybindings and settings are retained. A running Zebar is stopped at switch-over;
Zebar itself and its widget settings remain installed.

There is no independently configured automatic restart of Zebar. If you have
created another Zebar startup entry, scheduled task or service yourself, disable
that separately to avoid running two bars. The installer only owns the GlazeWM
integration and its own Windows Startup shortcut.

Advanced installation:

```powershell
.\Install.ps1 -GlazeExe 'C:\path\to\glazewm.exe' -ConfigPath 'C:\path\to\config.yaml'
```

The standard GlazeWM YAML layout is supported, including quoted inline command
lists and block command lists. YAML anchors, unusual mapping layouts and workspace
names containing whitespace/punctuation beyond `_.-` are rejected before changes.
The installer fails with an actionable message rather than guessing at unfamiliar
configuration. `GLAZEWM_CONFIG_PATH` is honored when set.

## Use

- A bar is placed on the left of every connected monitor.
- Only occupied workspaces and currently displayed/focused workspaces appear. Empty inactive workspaces are hidden.
- One click switches to that workspace. The focused workspace is highlighted.
- Workspaces visible on another monitor get a subtler highlight. There are no
  additional occupancy dots.
- Windows time/date sit at the very bottom and update at minute boundaries. Optional widgets are grouped above them.
- `!` means the connection to GlazeWM is unavailable; reconnect is automatic.
- Fullscreen windows covering a monitor hide its sidebar.
- Normal GlazeWM keyboard shortcuts continue to work.

Workspace names are copied to `sidebar.ini` during installation. If you change
the GlazeWM workspace list later, update that INI file and restart the sidebar.
The original dark charcoal sidebar palette works with light and dark Windows themes.
Segoe UI Variable gives workspace labels (12 px) and the stacked clock (16 px) a clear, consistent shape; Windows supplies a font fallback on older systems. The hand cursor appears only on workspace
buttons and the theme button; the rest uses the standard arrow.

### Optional widgets

The notification-area menu enables each widget independently. All four are on by
default; selections are saved in the installation's `sidebar.ini` and survive updates.

- **Sun/moon:** click to toggle Windows app and system light/dark preferences.
  The sun offers light mode; the moon offers dark mode. The sidebar palette
  stays fixed. Apps with their own theme setting may need to follow the system;
  a separate theme scheduler may later override a manual change.
- **CPU:** percentage of busy processor time averaged over the last five seconds.
  This time-based metric can differ from Task Manager's frequency-adjusted value.
  On systems with more than 64 logical processors, `GetSystemTimes` covers the
  calling thread's processor group.
- **RAM:** percentage of physical memory in use, refreshed every five seconds.
- **Battery symbol:** battery charge percentage as a bold number inside the compact icon, refreshed every minute and on Windows power
  notifications. `--` means unavailable or no battery; CPU also shows `--` before
  its first complete sampling interval.

One shared timer samples native Windows APIs for all monitors. Disabled widgets
are not sampled; disabling CPU, RAM and battery removes the sampling timer. Only
changed values invalidate the widget area. The theme button has no polling timer.
No WMI, shell commands, animations or extra worker threads are used for widgets.

```ini
[widgets]
theme=1
cpu=1
ram=1
battery=1
```

Use `0` to disable a widget; restart after manually editing the INI. Changes made
through the tray menu apply immediately. Metrics are display-only.

All active workspaces are available on each monitor; selection follows GlazeWM's
normal monitor-assignment behavior. Buttons beyond the available vertical space
are not shown; this version is intended for a small workspace list (e.g. 1–9).

## Tray icon and startup

The Windows notification area contains a Native Sidebar icon. Click or right-click
it for **Show sidebar**, **Start with Windows**, and **Exit** (menu labels currently
in German). The startup toggle uses the same shortcut as the installer. A **Native
Sidebar** Start menu entry lets you launch it again after exiting. Explorer restart
re-registers the tray icon. Windows may initially put the icon in its overflow area.

## Uninstall or update

Run **Uninstall.ps1** from the installation directory:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\Programs\NativeSidebar\Uninstall.ps1"
```

This removes its Startup and Start menu shortcuts, stops the installed sidebar, restores the
original GlazeWM config and starts Zebar when it was previously configured and
can be found on PATH. The installation files and backup remain for recovery.
If the GlazeWM config has changed since installation, uninstall stops before
modifying anything: merge `original-config.yaml` with your edits first.

To update, extract a new package elsewhere and run its installer. Updates preserve
the first original config and archive the previous installation. Modified GlazeWM
configs require manual merging before an update. Backups are never committed
to this repository or included in release packages.

## Build and test

Requirements: CMake 3.24+, Visual Studio 2022 C++ desktop tools and a Windows SDK.

```powershell
cmake -S . -B build -A x64
cmake --build build --config Release
ctest --test-dir build -C Release --output-on-failure
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Package.ps1
```

Release builds statically link the C++ runtime and optimize for size. The pinned
JSON parser is vendored, so building does not download dependencies.

Installer tests use isolated temporary configuration, install and startup
directories. They do not change the real GlazeWM config, start GlazeWM, or stop
Zebar. See [testing](docs/TESTING.md) for the separate live desktop checklist.

The GitHub Actions workflow builds, tests and uploads a ZIP as a CI artifact.
It does **not** create a GitHub Release or publish anything automatically.

## License

MIT. See [LICENSE](LICENSE) and [third-party notices](THIRD_PARTY_NOTICES.md).
Independent project; not an official GlazeWM or Zebar product.
