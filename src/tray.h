#pragma once
#include <windows.h>
#include <string>

namespace tray {
constexpr UINT Callback = WM_APP + 10;
constexpr UINT Show = 4101, Startup = 4102, Exit = 4103;
bool initialize(HWND owner, const std::wstring &directory);
void restore();
void remove();
void menu();
bool startupEnabled();
bool setStartup(bool enabled);
} // namespace tray
