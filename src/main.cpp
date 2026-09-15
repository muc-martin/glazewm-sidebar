#define UNICODE
#define _UNICODE
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include "vendor/json.hpp"
#include <algorithm>
#include <atomic>
#include <fstream>
#include <mutex>
#include <string>
#include <thread>
#include <vector>
#include <windows.h>
#include <windowsx.h>
#include <winhttp.h>
#include <shellapi.h>
#include <objbase.h>
#include "tray.h"
using json = nlohmann::json;
constexpr UINT UPDATE = WM_APP + 1, REBUILD = WM_APP + 2;
struct Workspace {
  std::string name, label;
  bool focused = false, displayed = false, occupied = false;
};
struct Snapshot {
  std::vector<Workspace> workspaces;
  bool connected = false;
};
struct Bar {
  HWND hwnd = nullptr, tip = nullptr;
  HMONITOR monitor = nullptr;
  int dpi = 96, hover = -1;
  HFONT font = nullptr, smallFont = nullptr;
};
std::vector<Bar *> bars;
Snapshot currentState, pending;
std::mutex stateMutex, socketMutex;
HINTERNET socketHandle = nullptr;
HWND controller = nullptr;
std::atomic<bool> stopping = false;
std::atomic<bool> updateQueued = false;
std::wstring baseDir;
std::vector<std::string> configured;
bool diagnostics = false;
UINT taskbarCreated = 0;
int px(Bar *b, int v) { return MulDiv(v, b->dpi, 96); }
std::wstring wide(const std::string &s) {
  int n = MultiByteToWideChar(CP_UTF8, 0, s.data(), (int)s.size(), nullptr, 0);
  std::wstring r(n, 0);
  MultiByteToWideChar(CP_UTF8, 0, s.data(), (int)s.size(), r.data(), n);
  return r;
}
std::string utf8(const std::wstring &s) {
  int n = WideCharToMultiByte(CP_UTF8, 0, s.data(), (int)s.size(), nullptr, 0,
                              nullptr, nullptr);
  std::string r(n, 0);
  WideCharToMultiByte(CP_UTF8, 0, s.data(), (int)s.size(), r.data(), n, nullptr,
                      nullptr);
  return r;
}
void loadConfig() {
  wchar_t text[4096];
  GetPrivateProfileStringW(L"sidebar", L"workspaces", L"1,2,3,4,5,6,7,8,9",
                           text, 4096, (baseDir + L"sidebar.ini").c_str());
  configured.clear();
  std::string s = utf8(text);
  size_t p = 0;
  while (p < s.size()) {
    auto e = s.find(',', p);
    auto v = s.substr(p, e == s.npos ? s.size() - p : e - p);
    if (!v.empty())
      configured.push_back(v);
    if (e == s.npos)
      break;
    p = e + 1;
  }
}
bool sendCommand(const std::string &cmd) {
  std::lock_guard<std::mutex> l(socketMutex);
  return socketHandle &&
         WinHttpWebSocketSend(
             socketHandle, WINHTTP_WEB_SOCKET_UTF8_MESSAGE_BUFFER_TYPE,
             (void *)cmd.data(), (DWORD)cmd.size()) == NO_ERROR;
}
void publish(Snapshot s) {
  {
    std::lock_guard<std::mutex> l(stateMutex);
    pending = std::move(s);
  }
  if (!updateQueued.exchange(true))
    PostMessageW(controller, UPDATE, 0, 0);
}
Snapshot decode(const json &j) {
  Snapshot s;
  s.connected = true;
  for (const auto &w : j.at("data").at("workspaces")) {
    Workspace v;
    v.name = w.at("name").get<std::string>();
    v.label = w.value("displayName", json()).is_string()
                  ? w["displayName"].get<std::string>()
                  : v.name;
    v.focused = w.value("hasFocus", false);
    v.displayed = w.value("isDisplayed", false);
    v.occupied = !w.value("children", json::array()).empty();
    if (v.occupied || v.focused || v.displayed)
      s.workspaces.push_back(v);
  }
  return s;
}
void connectionLoop() {
  while (!stopping) {
    HINTERNET session =
                  WinHttpOpen(L"NativeSidebar/1", WINHTTP_ACCESS_TYPE_NO_PROXY,
                              nullptr, nullptr, 0),
              conn = nullptr, req = nullptr, ws = nullptr;
    if (session) {
      WinHttpSetTimeouts(session, 2000, 2000, 2000, 0);
      conn = WinHttpConnect(session, L"127.0.0.1", 6123, 0);
    }
    if (conn)
      req =
          WinHttpOpenRequest(conn, L"GET", L"/", nullptr, nullptr, nullptr, 0);
    if (req &&
        WinHttpSetOption(req, WINHTTP_OPTION_UPGRADE_TO_WEB_SOCKET, nullptr,
                         0) &&
        WinHttpSendRequest(req, nullptr, 0, nullptr, 0, 0, 0) &&
        WinHttpReceiveResponse(req, nullptr))
      ws = WinHttpWebSocketCompleteUpgrade(req, 0);
    if (req)
      WinHttpCloseHandle(req);
    if (ws) {
      {
        std::lock_guard<std::mutex> l(socketMutex);
        socketHandle = ws;
      }
      sendCommand(
          "sub --events focus_changed focused_container_moved "
          "workspace_activated workspace_deactivated workspace_updated "
          "window_managed window_unmanaged monitor_added monitor_removed "
          "monitor_updated user_config_changed pause_changed");
      sendCommand("query workspaces");
      bool outstanding = true, dirty = false;
      std::string message;
      char buf[16384];
      while (!stopping) {
        DWORD count = 0;
        WINHTTP_WEB_SOCKET_BUFFER_TYPE type;
        auto error =
            WinHttpWebSocketReceive(ws, buf, sizeof(buf), &count, &type);
        if (error || type == WINHTTP_WEB_SOCKET_CLOSE_BUFFER_TYPE)
          break;
        message.append(buf, count);
        if (message.size() > 16 * 1024 * 1024)
          break;
        if (type != WINHTTP_WEB_SOCKET_UTF8_MESSAGE_BUFFER_TYPE)
          continue;
        try {
          auto j = json::parse(message);
          if (j.value("success", true) == false) {
            if (diagnostics) {
              std::ofstream f(baseDir + L"last-error.txt");
              f << j.dump(2);
            }
          }
          if (j.contains("data") && j["data"].is_object() &&
              j["data"].contains("workspaces")) {
            publish(decode(j));
            outstanding = false;
            if (dirty) {
              dirty = false;
              outstanding = sendCommand("query workspaces");
            }
          } else if (j.value("messageType", "") == "event_subscription") {
            if (outstanding)
              dirty = true;
            else
              outstanding = sendCommand("query workspaces");
          }
        } catch (const std::exception &) {
        }
        message.clear();
      }
      {
        std::lock_guard<std::mutex> l(socketMutex);
        socketHandle = nullptr;
        WinHttpCloseHandle(ws);
      }
    }
    if (conn)
      WinHttpCloseHandle(conn);
    if (session)
      WinHttpCloseHandle(session);
    publish(Snapshot{});
    for (int n = 0; n < 20 && !stopping; ++n)
      Sleep(100);
  }
}
void focusWorkspace(const std::string &name) {
  if (!currentState.connected)
    return;
  sendCommand("command focus --workspace " + name);
}
int rowAt(Bar *b, int y) {
  int n = (y - px(b, 8)) / px(b, 28);
  return y >= px(b, 8) && n >= 0 && n < (int)currentState.workspaces.size()
             ? n
             : -1;
}
int hitButton(Bar *b, int x, int y) {
  RECT rc;
  GetClientRect(b->hwnd, &rc);
  int n = rowAt(b, y);
  if (n < 0 || x < px(b, 3) || x >= rc.right - px(b, 3) ||
      y >= px(b, 32 + n * 28) || px(b, 32 + n * 28) > rc.bottom - px(b, 146))
    return -1;
  return n;
}
void text(HDC dc, const std::wstring &s, RECT r, COLORREF color, HFONT font) {
  SelectObject(dc, font);
  SetTextColor(dc, color);
  DrawTextW(dc, s.c_str(), (int)s.size(), &r,
            DT_CENTER | DT_VCENTER | DT_SINGLELINE | DT_END_ELLIPSIS |
                DT_NOPREFIX);
}
void paint(Bar *b) {
  PAINTSTRUCT ps;
  HDC dc = BeginPaint(b->hwnd, &ps);
  RECT rc;
  GetClientRect(b->hwnd, &rc);
  auto bg = CreateSolidBrush(RGB(66, 73, 84));
  FillRect(dc, &rc, bg);
  DeleteObject(bg);
  SetBkMode(dc, TRANSPARENT);
  for (int i = 0; i < (int)currentState.workspaces.size(); ++i) {
    const auto &w = currentState.workspaces[i];
    RECT r = {px(b, 3), px(b, 8 + i * 28), rc.right - px(b, 3),
              px(b, 32 + i * 28)};
    if (r.bottom > rc.bottom - px(b, 146))
      break;
    if (w.focused || w.displayed || b->hover == i) {
      auto brush =
          CreateSolidBrush(w.focused ? RGB(114, 137, 164) : RGB(83, 93, 107));
      auto old = SelectObject(dc, brush);
      auto pen = SelectObject(dc, GetStockObject(NULL_PEN));
      RoundRect(dc, r.left, r.top, r.right, r.bottom, px(b, 10), px(b, 10));
      SelectObject(dc, pen);
      SelectObject(dc, old);
      DeleteObject(brush);
    }
    text(dc, wide(w.label), r,
         w.focused ? RGB(255, 255, 255) : RGB(224, 230, 239), b->font);
  }
  if (!currentState.connected) {
    RECT r = {0, px(b, 8), rc.right, px(b, 36)};
    text(dc, L"!", r, RGB(235, 167, 92), b->font);
  }
  SYSTEMTIME now;
  GetLocalTime(&now);
  wchar_t hour[8], minute[8], day[8], month[32], weekday[32];
  swprintf_s(hour, L"%02u", now.wHour);
  swprintf_s(minute, L"%02u", now.wMinute);
  swprintf_s(day, L"%02u", now.wDay);
  GetDateFormatEx(LOCALE_NAME_USER_DEFAULT, 0, &now, L"MMM", month, 32,
                  nullptr);
  GetDateFormatEx(LOCALE_NAME_USER_DEFAULT, 0, &now, L"ddd", weekday, 32,
                  nullptr);
  int y = rc.bottom - px(b, 139);
  const wchar_t *parts[] = {hour, minute, L"", weekday, day, month};
  for (int i = 0; i < 6; i++) {
    RECT r = {0, y + px(b, i * 21), rc.right, y + px(b, (i + 1) * 21)};
    text(dc, parts[i], r, i < 2 ? RGB(235, 239, 245) : RGB(213, 221, 232),
         i < 2 ? b->font : b->smallFont);
  }
  EndPaint(b->hwnd, &ps);
}
void armClock(HWND h) {
  SYSTEMTIME t;
  GetLocalTime(&t);
  SetTimer(h, 1, 60000 - t.wSecond * 1000 - t.wMilliseconds, nullptr);
}
LRESULT CALLBACK barProc(HWND h, UINT msg, WPARAM w, LPARAM l) {
  Bar *b = (Bar *)GetWindowLongPtrW(h, GWLP_USERDATA);
  if (msg == WM_NCCREATE) {
    b = (Bar *)((CREATESTRUCT *)l)->lpCreateParams;
    b->hwnd = h;
    SetWindowLongPtrW(h, GWLP_USERDATA, (LONG_PTR)b);
  }
  if (!b)
    return DefWindowProcW(h, msg, w, l);
  switch (msg) {
  case WM_PAINT:
    paint(b);
    return 0;
  case WM_ERASEBKGND:
    return 1;
  case WM_MOUSEACTIVATE:
    return MA_NOACTIVATE;
  case WM_SETCURSOR:
    if (LOWORD(l) == HTCLIENT) {
      POINT p;
      GetCursorPos(&p);
      ScreenToClient(h, &p);
      SetCursor(LoadCursorW(nullptr, currentState.connected &&
                                             hitButton(b, p.x, p.y) >= 0
                                         ? IDC_HAND
                                         : IDC_ARROW));
      return TRUE;
    }
    break;
  case WM_LBUTTONUP: {
    int i = hitButton(b, GET_X_LPARAM(l), GET_Y_LPARAM(l));
    if (i >= 0)
      focusWorkspace(currentState.workspaces[i].name);
    return 0;
  }
  case WM_MOUSEWHEEL:
  case WM_CONTEXTMENU:
    return 0;
  case WM_MOUSEMOVE: {
    int i = hitButton(b, GET_X_LPARAM(l), GET_Y_LPARAM(l));
    if (i != b->hover) {
      b->hover = i;
      InvalidateRect(h, nullptr, FALSE);
    }
    TRACKMOUSEEVENT t = {sizeof(t), TME_LEAVE, h, 0};
    TrackMouseEvent(&t);
    return 0;
  }
  case WM_MOUSELEAVE:
    b->hover = -1;
    InvalidateRect(h, nullptr, FALSE);
    return 0;
  case WM_DISPLAYCHANGE:
  case WM_DPICHANGED:
    PostMessageW(controller, REBUILD, 0, 0);
    return 0;
  case WM_CLOSE:
    PostMessageW(controller, WM_CLOSE, 0, 0);
    return 0;
  }
  return DefWindowProcW(h, msg, w, l);
}
BOOL CALLBACK addMonitor(HMONITOR monitor, HDC, LPRECT, LPARAM) {
  auto *b = new Bar;
  b->monitor = monitor;
  MONITORINFO mi = {sizeof(mi)};
  GetMonitorInfoW(monitor, &mi);
  b->hwnd =
      CreateWindowExW(WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE, L"NativeSidebar",
                      L"Native Sidebar", WS_POPUP, mi.rcWork.left,
                      mi.rcWork.top, 28, mi.rcWork.bottom - mi.rcWork.top,
                      nullptr, nullptr, GetModuleHandleW(nullptr), b);
  b->dpi = GetDpiForWindow(b->hwnd);
  b->font =
      CreateFontW(-px(b, 11), 0, 0, 0, FW_MEDIUM, FALSE, FALSE, FALSE,
                  DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
                  CLEARTYPE_QUALITY, DEFAULT_PITCH, L"Segoe UI");
  b->smallFont =
      CreateFontW(-px(b, 10), 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
                  DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
                  CLEARTYPE_QUALITY, DEFAULT_PITCH, L"Segoe UI");
  SetWindowPos(b->hwnd, HWND_TOPMOST, mi.rcWork.left + px(b, 4),
               mi.rcWork.top + px(b, 4), px(b, 28),
               mi.rcWork.bottom - mi.rcWork.top - px(b, 8),
               SWP_NOACTIVATE | SWP_SHOWWINDOW);
  bars.push_back(b);
  return TRUE;
}
void rebuild() {
  for (auto *b : bars) {
    DestroyWindow(b->hwnd);
    DeleteObject(b->font);
    DeleteObject(b->smallFont);
    delete b;
  }
  bars.clear();
  EnumDisplayMonitors(nullptr, nullptr, addMonitor, 0);
}
void fullscreenVisibility() {
  HWND fg = GetForegroundWindow();
  RECT r = {};
  GetWindowRect(fg, &r);
  wchar_t cls[128] = {};
  GetClassNameW(fg, cls, 128);
  bool desktop = wcscmp(cls, L"Progman") == 0 || wcscmp(cls, L"WorkerW") == 0 ||
                 wcscmp(cls, L"Shell_TrayWnd") == 0;
  for (auto *b : bars) {
    MONITORINFO mi = {sizeof(mi)};
    GetMonitorInfoW(b->monitor, &mi);
    bool full = !desktop && fg != b->hwnd && IsWindowVisible(fg) &&
                r.left <= mi.rcMonitor.left && r.top <= mi.rcMonitor.top &&
                r.right >= mi.rcMonitor.right &&
                r.bottom >= mi.rcMonitor.bottom;
    ShowWindow(b->hwnd, full ? SW_HIDE : SW_SHOWNOACTIVATE);
  }
}
void CALLBACK foregroundEvent(HWINEVENTHOOK, DWORD, HWND hwnd, LONG object,
                              LONG, DWORD, DWORD) {
  if (object == OBJID_WINDOW && hwnd == GetForegroundWindow())
    PostMessageW(controller, WM_APP + 3, 0, 0);
}
LRESULT CALLBACK controlProc(HWND h, UINT msg, WPARAM w, LPARAM l) {
  if (taskbarCreated && msg == taskbarCreated) {
    tray::restore();
    return 0;
  }
  switch (msg) {
  case tray::Callback:
    if (LOWORD(l) == WM_CONTEXTMENU || LOWORD(l) == NIN_SELECT ||
        LOWORD(l) == NIN_KEYSELECT)
      tray::menu();
    return 0;
  case WM_COMMAND:
    if (LOWORD(w) == tray::Exit)
      PostMessageW(h, WM_CLOSE, 0, 0);
    else if (LOWORD(w) == tray::Show) {
      rebuild();
      fullscreenVisibility();
    } else if (LOWORD(w) == tray::Startup) {
      if (!tray::setStartup(!tray::startupEnabled()))
        MessageBoxW(
            h, L"Die Autostart-Verknuepfung konnte nicht aktualisiert werden.",
            L"Native Sidebar", MB_OK | MB_ICONERROR);
    }
    return 0;
  case UPDATE: {
    updateQueued = false;
    {
      std::lock_guard<std::mutex> g(stateMutex);
      currentState = pending;
    }
    std::stable_sort(
        currentState.workspaces.begin(), currentState.workspaces.end(),
        [](auto &a, auto &b) {
          auto ia = std::find(configured.begin(), configured.end(), a.name),
               ib = std::find(configured.begin(), configured.end(), b.name);
          return ia < ib;
        });
    for (auto *b : bars)
      InvalidateRect(b->hwnd, nullptr, FALSE);
    if (diagnostics) {
      json j;
      j["connected"] = currentState.connected;
      j["workspaces"] = json::array();
      for (auto &a : currentState.workspaces)
        j["workspaces"].push_back({{"name", a.name},
                                   {"focused", a.focused},
                                   {"occupied", a.occupied}});
      std::ofstream f(baseDir + L"state.json");
      f << j.dump(2);
    }
    return 0;
  }
  case WM_APP + 3:
    SetTimer(h, 2, 100, nullptr);
    return 0;
  case WM_TIMER:
    if (w == 2) {
      KillTimer(h, 2);
      fullscreenVisibility();
      return 0;
    }
    for (auto *b : bars)
      InvalidateRect(b->hwnd, nullptr, FALSE);
    armClock(h);
    return 0;
  case WM_TIMECHANGE:
    for (auto *b : bars)
      InvalidateRect(b->hwnd, nullptr, FALSE);
    armClock(h);
    return 0;
  case WM_SETTINGCHANGE:
  case REBUILD:
    rebuild();
    return 0;
  case WM_CLOSE:
    stopping = true;
    tray::remove();
    for (auto *b : bars)
      DestroyWindow(b->hwnd);
    DestroyWindow(h);
    return 0;
  case WM_DESTROY:
    PostQuitMessage(0);
    return 0;
  }
  return DefWindowProcW(h, msg, w, l);
}
int WINAPI wWinMain(HINSTANCE instance, HINSTANCE, PWSTR args, int) {
  if (wcsstr(args, L"--test-workspaces")) {
    configured = {"1", "2", "3", "9"};
    const auto result = decode(json::parse(R"({"data":{"workspaces":[
      {"name":"1","children":[{"type":"window"}]},
      {"name":"2","children":[],"hasFocus":true},
      {"name":"3","children":[],"isDisplayed":true},
      {"name":"4","children":[]}
    ]}})"));
    return result.workspaces.size() == 3 && result.workspaces[0].name == "1" &&
                   result.workspaces[1].name == "2" &&
                   result.workspaces[2].name == "3"
               ? 0
               : 1;
  }
  CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
  HANDLE singleton = CreateMutexW(nullptr, FALSE, L"Local\\NativeSidebar");
  if (GetLastError() == ERROR_ALREADY_EXISTS)
    return 0;
  wchar_t path[MAX_PATH];
  GetModuleFileNameW(nullptr, path, MAX_PATH);
  baseDir = path;
  baseDir = baseDir.substr(0, baseDir.find_last_of(L"\\/") + 1);
  diagnostics = wcsstr(args, L"--diagnostics") != nullptr;
  loadConfig();
  WNDCLASSW wc = {};
  wc.hInstance = instance;
  wc.lpfnWndProc = barProc;
  wc.lpszClassName = L"NativeSidebar";
  wc.hCursor = LoadCursorW(nullptr, IDC_ARROW);
  RegisterClassW(&wc);
  wc.lpfnWndProc = controlProc;
  wc.lpszClassName = L"NativeSidebarController";
  RegisterClassW(&wc);
  controller =
      CreateWindowExW(WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE, wc.lpszClassName,
                      L"Native Sidebar Controller", WS_POPUP, 0, 0, 0, 0,
                      nullptr, nullptr, instance, nullptr);
  taskbarCreated = RegisterWindowMessageW(L"TaskbarCreated");
  tray::initialize(controller, baseDir);
  rebuild();
  armClock(controller);
  SetWinEventHook(EVENT_SYSTEM_FOREGROUND, EVENT_SYSTEM_FOREGROUND, nullptr,
                  foregroundEvent, 0, 0,
                  WINEVENT_OUTOFCONTEXT | WINEVENT_SKIPOWNPROCESS);
  SetWinEventHook(EVENT_OBJECT_LOCATIONCHANGE, EVENT_OBJECT_LOCATIONCHANGE,
                  nullptr, foregroundEvent, 0, 0,
                  WINEVENT_OUTOFCONTEXT | WINEVENT_SKIPOWNPROCESS);
  fullscreenVisibility();
  std::thread(connectionLoop).detach();
  MSG msg;
  while (GetMessageW(&msg, nullptr, 0, 0) > 0) {
    TranslateMessage(&msg);
    DispatchMessageW(&msg);
  }
  CloseHandle(singleton);
  CoUninitialize();
  ExitProcess(0);
}
