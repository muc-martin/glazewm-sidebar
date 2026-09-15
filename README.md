# Native Sidebar for GlazeWM

A vertical workspace bar for Windows, written in C++ with Win32. It runs as a
single native process and connects directly to GlazeWM.

Click a workspace to switch to it. The clock and date sit at the bottom, with
optional CPU, RAM, battery and Windows theme controls above them.

![Native Sidebar on a Windows desktop](docs/images/sidebar-desktop.png)

## Install

Requires Windows x64 and GlazeWM.

1. Install GlazeWM and run it once to create its configuration.
2. Open the latest successful [Windows build](https://github.com/muc-martin/glazewm-sidebar/actions/workflows/build.yml)
   and download **native-sidebar-windows-x64** under **Artifacts**. GitHub requires
   you to sign in to download build artifacts.
3. Extract the artifact, then extract `native-sidebar-0.1.0-windows-x64.zip` inside it.
4. Run **Install.cmd**. No administrator rights are needed.

The installer starts the sidebar and adds it to the Start menu, Windows Startup
and **Settings > Apps > Installed apps**. Files are installed in
`%LOCALAPPDATA%\Programs\NativeSidebar`.

### Changes to GlazeWM

Installation automatically configures GlazeWM to use the sidebar:

- Backs up the original configuration.
- Removes recognized Zebar and previous sidebar startup/shutdown commands.
- Adds a window-ignore rule and sets the outer gaps to 52 px left and 8 px top.
- Stops a running Zebar. Its files and widget settings stay installed.

Other commands, keybindings and settings are preserved. Disable any separate
Zebar autostart entry you have created to prevent both bars from starting.
GlazeWM integration is part of every installation; there is no opt-out setting.

For custom paths:

```powershell
.\Install.ps1 -GlazeExe 'C:\path\to\glazewm.exe' -ConfigPath 'C:\path\to\config.yaml'
```

The installer also reads `GLAZEWM_CONFIG_PATH`. It supports standard GlazeWM YAML
with inline or block command lists. Unsupported layouts, including YAML anchors,
are rejected before making changes. Workspace names can contain letters, digits,
underscores, periods and hyphens.

## Workspaces

The 40-pixel bar appears on the left of each monitor. It shows occupied workspaces
and those currently displayed on a monitor. The focused workspace is bold and
highlighted; workspaces displayed on other monitors have a subtler highlight.

A click switches to that workspace. Fullscreen windows hide the bar. If the
connection to GlazeWM drops, the bar shows `!` and reconnects automatically.

Workspace names are copied into `sidebar.ini` during installation. After changing
your GlazeWM workspace list, update this file and restart the sidebar.

## Widgets

Use the sidebar's notification-area icon to enable or disable widgets. All are
enabled by default, and your selections are saved between runs and updates.

| Widget | Function |
| --- | --- |
| Sun / moon | Switches Windows app and system themes. The sidebar keeps its dark background. |
| CPU | Busy processor time averaged over five seconds. |
| RAM | Physical memory usage, refreshed every five seconds. |
| Battery | Charge percentage inside the battery. Green fill and a lightning bolt mean a power adapter is connected, including at full charge. |

The battery updates every minute and when Windows reports a power change.
`--` indicates an unavailable reading; CPU also shows it during its first sample.

Widgets use native Windows APIs in the sidebar process. Disabled widgets stop
sampling. With CPU, RAM and battery disabled, the sampling timer stops entirely.

You can also edit `sidebar.ini` and restart the sidebar. Set a value to `0` to
disable that widget:

```ini
[widgets]
theme=1
cpu=1
ram=1
battery=1
```

## Startup and tray menu

Click the notification-area icon to show the sidebar, toggle **Start with Windows**
or exit. Menu labels are currently in German. If the icon is hidden, open the
notification area's overflow menu.

Launch **Native Sidebar** from the Start menu to open it again. At Windows sign-in,
the startup script starts GlazeWM if needed, starts the sidebar, then exits.

## Update or uninstall

To update, extract a new package and run **Install.cmd**. The installer preserves
widget settings and the original GlazeWM backup, and archives the previous install.

To uninstall, select **Native Sidebar > Uninstall** in Windows **Installed apps**.
This removes the startup and Start menu shortcuts, restores the original GlazeWM
configuration and starts Zebar if it was previously configured and is on PATH.
Installation files and backups remain on disk for recovery.

Updates and uninstallation stop if your GlazeWM configuration has changed since
installation. Reconcile those edits with `original-config.yaml` before proceeding.

## Limitations

- Windows 10 compatibility and multi-monitor/mixed-DPI behavior have not been tested.
- Workspace buttons that exceed the available screen height are not displayed.
- CPU reports busy time, which differs from Task Manager's frequency-adjusted metric.
  On systems with more than 64 logical processors, it covers the calling thread's
  processor group.

## Build

Requires CMake 3.24+, Visual Studio 2022 C++ desktop tools and a Windows SDK.

```powershell
cmake -S . -B build -A x64
cmake --build build --config Release
ctest --test-dir build -C Release --output-on-failure
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Package.ps1
```

The ZIP is written to `dist/`. Release builds statically link the C++ runtime;
the JSON parser is vendored in the repository.

GitHub Actions runs the build, tests and packaging on Windows. See
[testing](docs/TESTING.md) for the automated tests and desktop checks.

## License

[MIT](LICENSE). Dependencies are listed in [third-party notices](THIRD_PARTY_NOTICES.md).
