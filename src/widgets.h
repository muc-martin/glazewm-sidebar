#pragma once
#include <windows.h>
#include <string>

namespace widgets {
enum Kind { Theme, Cpu, Ram, Battery, Count };
extern bool enabled[Count];
extern int cpu, ram, battery;
extern bool light;
extern bool pluggedIn;
void load(const std::wstring &path);
bool toggle(int kind);
bool sample(bool powerOnly = false);
void refreshTheme();
bool toggleTheme();
int cpuPercent(ULONGLONG idle, ULONGLONG kernel, ULONGLONG user);
} // namespace widgets
