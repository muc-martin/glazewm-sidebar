#define UNICODE
#define _UNICODE
#define WIN32_LEAN_AND_MEAN
#include "tray.h"
#include <shellapi.h>
#include <shlobj.h>
#include <shobjidl.h>

namespace tray {
static NOTIFYICONDATAW data{};
static std::wstring base;
static bool registered = false;

static std::wstring startupPath() {
  PWSTR folder = nullptr;
  if (FAILED(SHGetKnownFolderPath(FOLDERID_Startup, 0, nullptr, &folder)))
    return {};
  std::wstring path = std::wstring(folder) + L"\\Native Sidebar.lnk";
  CoTaskMemFree(folder);
  return path;
}
bool startupEnabled() {
  auto path = startupPath();
  return !path.empty() &&
         GetFileAttributesW(path.c_str()) != INVALID_FILE_ATTRIBUTES;
}
bool setStartup(bool enabled) {
  auto path = startupPath();
  if (path.empty())
    return false;
  if (!enabled)
    return DeleteFileW(path.c_str()) || GetLastError() == ERROR_FILE_NOT_FOUND;
  IShellLinkW *link = nullptr;
  HRESULT hr = CoCreateInstance(CLSID_ShellLink, nullptr, CLSCTX_INPROC_SERVER,
                                IID_PPV_ARGS(&link));
  if (FAILED(hr))
    return false;
  auto exe = base + L"native-sidebar.exe";
  if (GetFileAttributesW((base + L"installation.json").c_str()) !=
          INVALID_FILE_ATTRIBUTES &&
      GetFileAttributesW((base + L"Start-Sidebar.ps1").c_str()) !=
          INVALID_FILE_ATTRIBUTES) {
    wchar_t system[MAX_PATH];
    GetSystemDirectoryW(system, MAX_PATH);
    hr = link->SetPath(
        (std::wstring(system) + L"\\WindowsPowerShell\\v1.0\\powershell.exe")
            .c_str());
    auto args =
        L"-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"" +
        base + L"Start-Sidebar.ps1\"";
    if (SUCCEEDED(hr))
      hr = link->SetArguments(args.c_str());
  } else
    hr = link->SetPath(exe.c_str());
  if (SUCCEEDED(hr))
    hr = link->SetWorkingDirectory(base.c_str());
  if (SUCCEEDED(hr))
    hr = link->SetIconLocation(exe.c_str(), 0);
  if (SUCCEEDED(hr))
    hr = link->SetDescription(L"Native Sidebar for GlazeWM");
  if (SUCCEEDED(hr))
    hr = link->SetShowCmd(SW_SHOWNOACTIVATE);
  IPersistFile *file = nullptr;
  if (SUCCEEDED(hr))
    hr = link->QueryInterface(IID_PPV_ARGS(&file));
  if (SUCCEEDED(hr)) {
    hr = file->Save(path.c_str(), TRUE);
    file->Release();
  }
  link->Release();
  return SUCCEEDED(hr);
}
static HICON makeIcon() {
  // A small opaque slate tile stays readable on both Windows taskbar themes.
  BITMAPINFO info{};
  info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  info.bmiHeader.biWidth = 16;
  info.bmiHeader.biHeight = -16;
  info.bmiHeader.biPlanes = 1;
  info.bmiHeader.biBitCount = 32;
  info.bmiHeader.biCompression = BI_RGB;
  DWORD *pixels = nullptr;
  HBITMAP color = CreateDIBSection(nullptr, &info, DIB_RGB_COLORS,
                                   (void **)&pixels, nullptr, 0);
  if (!color)
    return nullptr;
  for (int y = 0; y < 16; y++)
    for (int x = 0; x < 16; x++) {
      DWORD c = 0;
      if (x >= 1 && x <= 14 && y >= 1 && y <= 14)
        c = 0xff596779;
      if (x >= 4 && x <= 6 && y >= 4 && y <= 11)
        c = 0xffeff3f8;
      if (x >= 9 && x <= 11 && ((y >= 4 && y <= 6) || (y >= 9 && y <= 11)))
        c = 0xffb4c9df;
      pixels[y * 16 + x] = c;
    }
  WORD mask[16] = {};
  HBITMAP mono = CreateBitmap(16, 16, 1, 1, mask);
  ICONINFO icon{};
  icon.fIcon = TRUE;
  icon.hbmColor = color;
  icon.hbmMask = mono;
  HICON result = CreateIconIndirect(&icon);
  DeleteObject(color);
  DeleteObject(mono);
  return result;
}
bool initialize(HWND owner, const std::wstring &directory) {
  base = directory;
  data.cbSize = sizeof(data);
  data.hWnd = owner;
  data.uID = 1;
  data.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP | NIF_SHOWTIP;
  data.uCallbackMessage = Callback;
  data.hIcon = makeIcon();
  wcscpy_s(data.szTip, L"Native Sidebar");
  restore();
  return registered;
}
void restore() {
  registered = Shell_NotifyIconW(NIM_ADD, &data) != FALSE;
  if (registered) {
    data.uVersion = NOTIFYICON_VERSION_4;
    Shell_NotifyIconW(NIM_SETVERSION, &data);
  }
}
void remove() {
  if (registered)
    Shell_NotifyIconW(NIM_DELETE, &data);
  registered = false;
  if (data.hIcon) {
    DestroyIcon(data.hIcon);
    data.hIcon = nullptr;
  }
}
void menu() {
  HMENU popup = CreatePopupMenu();
  AppendMenuW(popup, MF_STRING, Show, L"Sidebar anzeigen");
  AppendMenuW(popup, MF_STRING | (startupEnabled() ? MF_CHECKED : MF_UNCHECKED),
              Startup, L"Mit Windows starten");
  AppendMenuW(popup, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(popup, MF_STRING, Exit, L"Beenden");
  POINT point;
  GetCursorPos(&point);
  SetForegroundWindow(data.hWnd);
  UINT command =
      TrackPopupMenu(popup, TPM_RETURNCMD | TPM_NONOTIFY | TPM_RIGHTBUTTON,
                     point.x, point.y, 0, data.hWnd, nullptr);
  DestroyMenu(popup);
  if (command)
    PostMessageW(data.hWnd, WM_COMMAND, command, 0);
  PostMessageW(data.hWnd, WM_NULL, 0, 0);
  Shell_NotifyIconW(NIM_SETFOCUS, &data);
}
} // namespace tray
