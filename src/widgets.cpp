#define UNICODE
#define _UNICODE
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include "widgets.h"
#include <algorithm>

namespace widgets {
bool enabled[Count] = {true, true, true, true};
int cpu = -1, ram = -1, battery = -1;
bool light = true;
static std::wstring ini;
static const wchar_t *keys[] = {L"theme", L"cpu", L"ram", L"battery"};
static constexpr auto personalize =
    L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize";
static ULONGLONG lastIdle = 0, lastKernel = 0, lastUser = 0, lastPower = 0;
static bool primed = false;

void load(const std::wstring &path) {
  ini = path;
  for (int i = 0; i < Count; ++i)
    enabled[i] =
        GetPrivateProfileIntW(L"widgets", keys[i], 1, ini.c_str()) != 0;
  refreshTheme();
}
bool toggle(int kind) {
  if (kind < 0 || kind >= Count)
    return false;
  if (!WritePrivateProfileStringW(L"widgets", keys[kind],
                                  enabled[kind] ? L"0" : L"1", ini.c_str()))
    return false;
  enabled[kind] = !enabled[kind];
  if (kind == Cpu) {
    primed = false;
    cpu = -1;
  }
  if (kind == Battery)
    lastPower = 0;
  return true;
}
int cpuPercent(ULONGLONG idle, ULONGLONG kernel, ULONGLONG user) {
  const auto total = kernel + user;
  if (!total || idle > total)
    return -1;
  return static_cast<int>((total - idle) * 100.0 / total + 0.5);
}
static ULONGLONG ticks(FILETIME t) {
  return (static_cast<ULONGLONG>(t.dwHighDateTime) << 32) | t.dwLowDateTime;
}
bool sample(bool powerOnly) {
  int oldCpu = cpu, oldRam = ram, oldBattery = battery;
  if (!powerOnly && enabled[Cpu]) {
    FILETIME idle{}, kernel{}, user{};
    if (GetSystemTimes(&idle, &kernel, &user)) {
      auto i = ticks(idle), k = ticks(kernel), u = ticks(user);
      if (primed && i >= lastIdle && k >= lastKernel && u >= lastUser)
        cpu = cpuPercent(i - lastIdle, k - lastKernel, u - lastUser);
      lastIdle = i;
      lastKernel = k;
      lastUser = u;
      primed = true;
    } else {
      cpu = -1;
      primed = false;
    }
  }
  if (!powerOnly && enabled[Ram]) {
    MEMORYSTATUSEX status{sizeof(status)};
    ram = GlobalMemoryStatusEx(&status) ? static_cast<int>(status.dwMemoryLoad)
                                        : -1;
  }
  auto now = GetTickCount64();
  if (enabled[Battery] &&
      (powerOnly || !lastPower || now - lastPower >= 60000)) {
    SYSTEM_POWER_STATUS status{};
    battery = GetSystemPowerStatus(&status) && status.BatteryFlag != 255 &&
                      !(status.BatteryFlag & 128) &&
                      status.BatteryLifePercent <= 100
                  ? status.BatteryLifePercent
                  : -1;
    lastPower = now;
  }
  return cpu != oldCpu || ram != oldRam || battery != oldBattery;
}
void refreshTheme() {
  DWORD value = 1, size = sizeof(value);
  RegGetValueW(HKEY_CURRENT_USER, personalize, L"AppsUseLightTheme",
               RRF_RT_REG_DWORD, nullptr, &value, &size);
  light = value != 0;
}
bool toggleTheme() {
  HKEY key;
  if (RegCreateKeyExW(HKEY_CURRENT_USER, personalize, 0, nullptr, 0,
                      KEY_QUERY_VALUE | KEY_SET_VALUE, nullptr, &key,
                      nullptr) != ERROR_SUCCESS)
    return false;
  DWORD old = 1, size = sizeof(old);
  auto read = RegGetValueW(key, nullptr, L"AppsUseLightTheme", RRF_RT_REG_DWORD,
                           nullptr, &old, &size);
  if (read != ERROR_SUCCESS && read != ERROR_FILE_NOT_FOUND) {
    RegCloseKey(key);
    return false;
  }
  DWORD value = old ? 0 : 1;
  auto result = RegSetValueExW(key, L"AppsUseLightTheme", 0, REG_DWORD,
                               reinterpret_cast<BYTE *>(&value), sizeof(value));
  if (result == ERROR_SUCCESS) {
    result = RegSetValueExW(key, L"SystemUsesLightTheme", 0, REG_DWORD,
                            reinterpret_cast<BYTE *>(&value), sizeof(value));
    if (result != ERROR_SUCCESS) {
      if (read == ERROR_FILE_NOT_FOUND)
        RegDeleteValueW(key, L"AppsUseLightTheme");
      else
        RegSetValueExW(key, L"AppsUseLightTheme", 0, REG_DWORD,
                       reinterpret_cast<BYTE *>(&old), sizeof(old));
    }
  }
  RegCloseKey(key);
  if (result != ERROR_SUCCESS)
    return false;
  refreshTheme();
  // Asynchronous broadcast avoids blocking the sidebar on unresponsive apps.
  // The string literal remains alive until process exit.
  SendNotifyMessageW(HWND_BROADCAST, WM_SETTINGCHANGE, 0,
                     reinterpret_cast<LPARAM>(L"ImmersiveColorSet"));
  return true;
}
} // namespace widgets
