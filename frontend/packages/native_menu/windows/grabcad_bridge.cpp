#include "grabcad_bridge.h"
#include "../common/grabcad_protocol.h"
#include <WebView2.h>
#include <algorithm>
#include <charconv>
#include <chrono>
#include <cstdio>
#include <deque>
#include <map>
#include <shellapi.h>
#include <shlobj.h>
#include <string>
#include <vector>
#include <wrl.h>

using Microsoft::WRL::Callback;
using Microsoft::WRL::ComPtr;
using Value = flutter::EncodableValue;
using Map = flutter::EncodableMap;
using List = flutter::EncodableList;
using Result = flutter::MethodResult<Value>;
using Clock = std::chrono::steady_clock;
namespace {
std::wstring Wide(const std::string &s) {
  int n = MultiByteToWideChar(CP_UTF8, 0, s.data(), static_cast<int>(s.size()),
                              nullptr, 0);
  std::wstring out(n, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, s.data(), static_cast<int>(s.size()),
                      out.data(), n);
  return out;
}
std::string Narrow(const wchar_t *s) {
  if (!s)
    return {};
  int n = WideCharToMultiByte(CP_UTF8, 0, s, -1, nullptr, 0, nullptr, nullptr);
  std::string out(n, '\0');
  WideCharToMultiByte(CP_UTF8, 0, s, -1, out.data(), n, nullptr, nullptr);
  if (!out.empty())
    out.pop_back();
  return out;
}
std::string String(const Value *value, const char *key) {
  if (!value)
    return {};
  auto map = std::get_if<Map>(value);
  if (!map)
    return {};
  auto it = map->find(Value(key));
  if (it == map->end())
    return {};
  auto s = std::get_if<std::string>(&it->second);
  return s ? *s : std::string();
}
bool HasString(const Value *value, const char *key) {
  if (!value)
    return false;
  auto map = std::get_if<Map>(value);
  if (!map)
    return false;
  auto it = map->find(Value(key));
  return it != map->end() && std::holds_alternative<std::string>(it->second);
}
constexpr UINT_PTR kTimer = 701;
constexpr int kDone = 702;
constexpr int64_t kMaxBytes = 250LL * 1024 * 1024;
} // namespace

struct WindowsGrabCad::Impl : std::enable_shared_from_this<Impl> {
  explicit Impl(HWND parent) : owner(parent) {}
  HWND owner = nullptr, window = nullptr, note = nullptr, done = nullptr;
  ComPtr<ICoreWebView2Environment> environment;
  ComPtr<ICoreWebView2Controller> controller;
  ComPtr<ICoreWebView2> web;
  ComPtr<ICoreWebView2DownloadOperation> operation;
  EventRegistrationToken bytesToken{}, stateToken{};
  std::unique_ptr<Result> loginResult, downloadResult;
  std::string help, unavailable;
  std::wstring downloadFile, downloadFolder;
  Clock::time_point initDeadline, downloadDeadline, downloadStarted,
      checkDeadline;
  bool initializing = false, checkingLogin = false;
  int dropped = 0;
  std::deque<Value> events;
  struct Request {
    std::unique_ptr<Result> result;
    Clock::time_point started;
    std::string path;
  };
  std::map<std::string, Request> requests;

  ~Impl() {
    if (window)
      KillTimer(window, kTimer);
    if (operation)
      operation->Cancel();
    if (controller)
      controller->Close();
    if (loginResult)
      EnableWindow(owner, TRUE);
    if (window) {
      SetWindowLongPtr(window, GWLP_USERDATA, 0);
      DestroyWindow(window);
    }
  }
  void Record(const char *event, Map fields = {}) {
    SYSTEMTIME t{};
    GetSystemTime(&t);
    char time[40]{};
    snprintf(time, sizeof(time), "%04u-%02u-%02uT%02u:%02u:%02u.%03uZ", t.wYear,
             t.wMonth, t.wDay, t.wHour, t.wMinute, t.wSecond, t.wMilliseconds);
    fields[Value("time")] = Value(time);
    fields[Value("event")] = Value(event);
    if (events.size() == 300) {
      events.pop_front();
      ++dropped;
    }
    events.emplace_back(fields);
  }
  Value Diagnostics() const {
    return Value(
        Map{{Value("schemaVersion"), Value(1)},
            {Value("backend"), Value("WebView2")},
            {Value("events"), Value(List(events.begin(), events.end()))},
            {Value("droppedEvents"), Value(dropped)},
            {Value("loginActive"), Value(loginResult != nullptr)},
            {Value("downloadActive"), Value(downloadResult != nullptr)},
            {Value("metadataRequestsActive"),
             Value(static_cast<int>(requests.size()))},
            {Value("browserReady"), Value(web != nullptr)}});
  }
  static LRESULT CALLBACK WindowProc(HWND hwnd, UINT message, WPARAM wp,
                                     LPARAM lp) {
    Impl *self =
        reinterpret_cast<Impl *>(GetWindowLongPtr(hwnd, GWLP_USERDATA));
    if (message == WM_NCCREATE) {
      self = static_cast<Impl *>(
          reinterpret_cast<CREATESTRUCT *>(lp)->lpCreateParams);
      SetWindowLongPtr(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
    }
    if (self) {
      // COM event callbacks are weak; hold ownership while window events run.
      auto keepAlive = self->shared_from_this();
      if (message == WM_CLOSE) {
        self->FinishLogin(false);
        return 0;
      }
      if (message == WM_COMMAND && LOWORD(wp) == kDone) {
        self->CheckLogin();
        return 0;
      }
      if (message == WM_SIZE) {
        self->Resize();
        return 0;
      }
      if (message == WM_TIMER && wp == kTimer) {
        self->Tick();
        return 0;
      }
    }
    return DefWindowProc(hwnd, message, wp, lp);
  }
  void Resize() {
    if (!window)
      return;
    RECT r{};
    GetClientRect(window, &r);
    MoveWindow(note, 16, 8, std::max<LONG>(1, r.right - 150), 40, TRUE);
    MoveWindow(done, std::max<LONG>(1, r.right - 120), 10, 100, 28, TRUE);
    r.top = 52;
    if (controller)
      controller->put_Bounds(r);
  }
  void FinishLogin(bool success, const char *error = nullptr) {
    if (!loginResult)
      return;
    Record("login.finish", {{Value("authenticated"), Value(success)},
                            {Value("errorCode"), Value(error ? error : "")}});
    ShowWindow(window, SW_HIDE);
    EnableWindow(owner, TRUE);
    SetForegroundWindow(owner);
    checkingLogin = false;
    auto result = std::move(loginResult);
    if (error)
      result->Error(error);
    else
      result->Success(Value(success));
  }
  void InitFailed(HRESULT error) {
    initializing = false;
    Record("browser.initError",
           {{Value("hresult"), Value(static_cast<int64_t>(error))}});
    FinishLogin(false, "browser_unavailable");
  }
  void SignIn(const Value *args, std::unique_ptr<Result> result) {
    if (loginResult || downloadResult || !requests.empty()) {
      result->Error("busy");
      return;
    }
    loginResult = std::move(result);
    help = String(args, "help");
    unavailable = String(args, "unavailable");
    Record("login.present");
    if (!window) {
      WNDCLASS wc{};
      wc.lpfnWndProc = WindowProc;
      wc.hInstance = GetModuleHandle(nullptr);
      wc.lpszClassName = L"PrototypeGrabCad";
      wc.hCursor = LoadCursor(nullptr, IDC_ARROW);
      wc.hbrBackground = reinterpret_cast<HBRUSH>(COLOR_WINDOW + 1);
      RegisterClass(&wc);
      RECT parent{};
      GetWindowRect(owner, &parent);
      const int width = std::min(1100, GetSystemMetrics(SM_CXSCREEN) - 80);
      const int height = std::min(800, GetSystemMetrics(SM_CYSCREEN) - 100);
      window = CreateWindowEx(
          WS_EX_DLGMODALFRAME, wc.lpszClassName,
          Wide(String(args, "title")).c_str(), WS_OVERLAPPEDWINDOW,
          std::max(0L, parent.left + (parent.right - parent.left - width) / 2),
          std::max(0L, parent.top + (parent.bottom - parent.top - height) / 2),
          width, height, owner, nullptr, wc.hInstance, this);
      if (!window) {
        InitFailed(HRESULT_FROM_WIN32(GetLastError()));
        return;
      }
      note = CreateWindow(L"STATIC", Wide(help).c_str(), WS_CHILD | WS_VISIBLE,
                          16, 8, width - 150, 40, window, nullptr, wc.hInstance,
                          nullptr);
      done = CreateWindow(L"BUTTON", Wide(String(args, "done")).c_str(),
                          WS_CHILD | WS_VISIBLE | WS_TABSTOP, width - 120, 10,
                          100, 28, window, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kDone)),
                          wc.hInstance, nullptr);
      const auto font =
          reinterpret_cast<WPARAM>(GetStockObject(DEFAULT_GUI_FONT));
      SendMessage(note, WM_SETFONT, font, TRUE);
      SendMessage(done, WM_SETFONT, font, TRUE);
      SetTimer(window, kTimer, 1000, nullptr);
    }
    SetWindowText(window, Wide(String(args, "title")).c_str());
    SetWindowText(done, Wide(String(args, "done")).c_str());
    SetWindowText(note, Wide(help).c_str());
    EnableWindow(owner, FALSE);
    ShowWindow(window, SW_SHOW);
    SetForegroundWindow(window);
    if (web) {
      HRESULT navigate = web->Navigate(L"https://grabcad.com/login");
      if (SUCCEEDED(navigate))
        return;
      if (controller)
        controller->Close();
      web.Reset();
      controller.Reset();
      environment.Reset();
    }
    if (initializing)
      return;
    initializing = true;
    initDeadline = Clock::now() + std::chrono::seconds(30);
    PWSTR local = nullptr;
    if (FAILED(
            SHGetKnownFolderPath(FOLDERID_LocalAppData, 0, nullptr, &local))) {
      InitFailed(E_FAIL);
      return;
    }
    std::wstring userData = std::wstring(local) + L"\\prototype";
    CoTaskMemFree(local);
    CreateDirectory(userData.c_str(), nullptr);
    userData += L"\\GrabCADWebView";
    // The loader checks the installed Evergreen runtime, without starting a
    // second login stack.
    LPWSTR version = nullptr;
    HRESULT available =
        GetAvailableCoreWebView2BrowserVersionString(nullptr, &version);
    CoTaskMemFree(version);
    if (FAILED(available)) {
      initializing = false;
      Record("browser.runtimeMissing");
      FinishLogin(false, "webview_runtime_missing");
      return;
    }
    std::weak_ptr<Impl> weak = shared_from_this();
    const HRESULT hr = CreateCoreWebView2EnvironmentWithOptions(
        nullptr, userData.c_str(), nullptr,
        Callback<ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler>(
            [weak](HRESULT status, ICoreWebView2Environment *env) -> HRESULT {
              auto self = weak.lock();
              if (!self)
                return S_OK;
              if (FAILED(status) || !env) {
                self->InitFailed(status);
                return S_OK;
              }
              self->environment = env;
              HRESULT created = env->CreateCoreWebView2Controller(
                  self->window,
                  Callback<
                      ICoreWebView2CreateCoreWebView2ControllerCompletedHandler>(
                      [weak](HRESULT code,
                             ICoreWebView2Controller *controller) -> HRESULT {
                        auto self = weak.lock();
                        if (!self)
                          return S_OK;
                        if (FAILED(code) || !controller) {
                          self->InitFailed(code);
                          return S_OK;
                        }
                        self->initializing = false;
                        self->controller = controller;
                        controller->get_CoreWebView2(&self->web);
                        if (!self->web) {
                          self->InitFailed(E_FAIL);
                          return S_OK;
                        }
                        self->Configure();
                        self->Resize();
                        self->Record("browser.ready");
                        self->web->Navigate(L"https://grabcad.com/login");
                        return S_OK;
                      })
                      .Get());
              if (FAILED(created))
                self->InitFailed(created);
              return S_OK;
            })
            .Get());
    if (FAILED(hr))
      InitFailed(hr);
  }
  void Configure() {
    std::weak_ptr<Impl> weak = shared_from_this();
    EventRegistrationToken token{};
    web->add_WebMessageReceived(
        Callback<ICoreWebView2WebMessageReceivedEventHandler>(
            [weak](ICoreWebView2 *,
                   ICoreWebView2WebMessageReceivedEventArgs *args) -> HRESULT {
              auto self = weak.lock();
              if (!self)
                return S_OK;
              LPWSTR source = nullptr, message = nullptr;
              args->get_Source(&source);
              args->TryGetWebMessageAsString(&message);
              const auto url = Narrow(source);
              const auto data = Narrow(message);
              CoTaskMemFree(source);
              CoTaskMemFree(message);
              if (grabcad::GrabCadUrl(url))
                self->Message(data);
              return S_OK;
            })
            .Get(),
        &token);
    web->add_NavigationCompleted(
        Callback<ICoreWebView2NavigationCompletedEventHandler>(
            [weak](ICoreWebView2 *,
                   ICoreWebView2NavigationCompletedEventArgs *args) -> HRESULT {
              auto self = weak.lock();
              if (!self)
                return S_OK;
              BOOL success = FALSE;
              args->get_IsSuccess(&success);
              COREWEBVIEW2_WEB_ERROR_STATUS error{};
              args->get_WebErrorStatus(&error);
              self->Record(
                  "browser.navigation",
                  {{Value("success"), Value(success != FALSE)},
                   {Value("webErrorStatus"), Value(static_cast<int>(error))}});
              if (self->loginResult) {
                if (success)
                  self->CheckLogin();
                else
                  SetWindowText(self->note, Wide(self->unavailable).c_str());
              }
              // Attachment navigations can complete before DownloadStarting
              // fires. The startup timeout below distinguishes them from
              // login/error HTML.
              return S_OK;
            })
            .Get(),
        &token);
    web->add_ProcessFailed(
        Callback<ICoreWebView2ProcessFailedEventHandler>(
            [weak](ICoreWebView2 *,
                   ICoreWebView2ProcessFailedEventArgs *args) -> HRESULT {
              auto self = weak.lock();
              if (!self)
                return S_OK;
              COREWEBVIEW2_PROCESS_FAILED_KIND kind{};
              args->get_ProcessFailedKind(&kind);
              self->Record("browser.processFailed",
                           {{Value("kind"), Value(static_cast<int>(kind))}});
              self->FailRequests("unavailable");
              self->FinishDownload("unavailable");
              self->FinishLogin(false, "browser_unavailable");
              return S_OK;
            })
            .Get(),
        &token);
    ComPtr<ICoreWebView2_4> web4;
    if (SUCCEEDED(web.As(&web4))) {
      web4->add_DownloadStarting(
          Callback<ICoreWebView2DownloadStartingEventHandler>(
              [weak](ICoreWebView2 *,
                     ICoreWebView2DownloadStartingEventArgs *args) -> HRESULT {
                auto self = weak.lock();
                if (!self) {
                  args->put_Cancel(TRUE);
                  return S_OK;
                }
                self->DownloadStarting(args);
                return S_OK;
              })
              .Get(),
          &token);
    }
    // Account popup links remain in this browser session instead of silently
    // disappearing.
    web->add_NewWindowRequested(
        Callback<ICoreWebView2NewWindowRequestedEventHandler>(
            [weak](ICoreWebView2 *,
                   ICoreWebView2NewWindowRequestedEventArgs *args) -> HRESULT {
              auto self = weak.lock();
              if (!self)
                return S_OK;
              LPWSTR uri = nullptr;
              args->get_Uri(&uri);
              std::string url = Narrow(uri);
              CoTaskMemFree(uri);
              args->put_Handled(TRUE);
              if (self->loginResult && url.rfind("https://", 0) == 0)
                self->web->Navigate(Wide(url).c_str());
              return S_OK;
            })
            .Get(),
        &token);
  }
  void Script(const std::string &script) {
    if (web)
      web->ExecuteScript(Wide(script).c_str(), nullptr);
  }
  void CheckLogin() {
    if (!loginResult || checkingLogin || !web)
      return;
    LPWSTR uri = nullptr;
    web->get_Source(&uri);
    const auto source = Narrow(uri);
    CoTaskMemFree(uri);
    if (!grabcad::GrabCadUrl(source))
      return;
    checkingLogin = true;
    checkDeadline = Clock::now() + std::chrono::seconds(10);
    Script(grabcad::LoginScript());
  }
  void Message(const std::string &message) {
    const auto first = message.find('\n');
    if (first == std::string::npos)
      return;
    const std::string id = message.substr(0, first);
    if (id == "auth") {
      checkingLogin = false;
      if (!loginResult)
        return;
      if (message.substr(first + 1) == "1")
        FinishLogin(true);
      else {
        Record("login.sessionUnauthenticated");
        if (message.substr(first + 1) == "error")
          SetWindowText(note, Wide(unavailable).c_str());
      }
      return;
    }
    auto it = requests.find(id);
    if (it == requests.end())
      return;
    const auto second = message.find('\n', first + 1);
    if (second == std::string::npos)
      return;
    int status = 0;
    auto parsed = std::from_chars(message.data() + first + 1,
                                  message.data() + second, status);
    if (parsed.ec != std::errc()) {
      CompleteRequest(id, "invalid_response");
      return;
    }
    if (status == -1) {
      CompleteRequest(id, message.substr(second + 1).c_str());
      return;
    }
    const auto third = message.find('\n', second + 1);
    if (third == std::string::npos || message.size() > 9 * 1024 * 1024) {
      CompleteRequest(id, "invalid_response");
      return;
    }
    Map response{{Value("status"), Value(status)},
                 {Value("contentType"),
                  Value(message.substr(second + 1, third - second - 1))},
                 {Value("body"), Value(message.substr(third + 1))}};
    Record("metadata.finish",
           {{Value("status"), Value(status)},
            {Value("path"), Value(it->second.path)},
            {Value("elapsedMs"),
             Value(static_cast<int64_t>(
                 std::chrono::duration_cast<std::chrono::milliseconds>(
                     Clock::now() - it->second.started)
                     .count()))}});
    auto result = std::move(it->second.result);
    requests.erase(it);
    result->Success(Value(response));
  }
  void RequestMetadata(const Value *args, std::unique_ptr<Result> result) {
    const auto id = String(args, "id"), path = String(args, "path"),
               body = String(args, "body");
    const bool post = HasString(args, "body");
    if (id.empty() || id.size() > 100 ||
        id.find_first_of("\r\n") != std::string::npos || requests.count(id) ||
        !grabcad::MetadataPath(path) ||
        (post && (path != "models" || body.size() > 65536))) {
      result->Error("invalid_request");
      return;
    }
    if (!web || loginResult || downloadResult) {
      result->Error("access_denied");
      return;
    }
    Record("metadata.start",
           {{Value("path"), Value(path.substr(0, path.find('?')))},
            {Value("method"), Value(post ? "POST" : "GET")}});
    requests.emplace(id, Request{std::move(result), Clock::now(),
                                 path.substr(0, path.find('?'))});
    Script(grabcad::RequestScript(id, path, post ? &body : nullptr));
  }
  void CompleteRequest(const std::string &id, const char *error) {
    auto it = requests.find(id);
    if (it == requests.end())
      return;
    Record("metadata.finish", {{Value("path"), Value(it->second.path)},
                               {Value("errorCode"), Value(error)}});
    auto result = std::move(it->second.result);
    requests.erase(it);
    result->Error(error);
  }
  void CancelRequests(const Value *args) {
    if (!args)
      return;
    auto map = std::get_if<Map>(args);
    if (!map)
      return;
    auto ids = map->find(Value("ids"));
    if (ids == map->end())
      return;
    auto list = std::get_if<List>(&ids->second);
    if (!list)
      return;
    for (const auto &value : *list) {
      auto id = std::get_if<std::string>(&value);
      if (!id || !requests.count(*id))
        continue;
      Script("window.__prototypeRequests?.[" + grabcad::Quote(*id) +
             "]?.abort();");
      CompleteRequest(*id, "cancelled");
    }
  }
  void FailRequests(const char *error) {
    while (!requests.empty())
      CompleteRequest(requests.begin()->first, error);
  }
  void Download(const Value *args, std::unique_ptr<Result> result) {
    const auto url = String(args, "url"), name = String(args, "name");
    if (downloadResult || loginResult || !requests.empty()) {
      result->Error("busy");
      return;
    }
    if (!web) {
      result->Error("sign_in_required");
      return;
    }
    if (!grabcad::GrabCadUrl(url) || !grabcad::FileName(name)) {
      result->Error("invalid_download");
      return;
    }
    ComPtr<ICoreWebView2_4> web4;
    if (FAILED(web.As(&web4))) {
      result->Error("browser_unavailable");
      return;
    }
    wchar_t temp[MAX_PATH]{};
    if (!GetTempPath(MAX_PATH, temp)) {
      result->Error("invalid_download");
      return;
    }
    GUID guid{};
    CoCreateGuid(&guid);
    wchar_t identifier[40]{};
    StringFromGUID2(guid, identifier, 40);
    downloadFolder = std::wstring(temp) + L"grabcad_" + identifier;
    if (!CreateDirectory(downloadFolder.c_str(), nullptr)) {
      result->Error("invalid_download");
      return;
    }
    downloadFile = downloadFolder + L"\\" + Wide(name);
    downloadResult = std::move(result);
    downloadStarted = Clock::now();
    downloadDeadline = downloadStarted + std::chrono::minutes(5);
    Record("download.start", {{Value("name"), Value(name)}});
    const HRESULT hr = web->Navigate(Wide(url).c_str());
    if (FAILED(hr))
      FinishDownload("unavailable");
  }
  void DownloadStarting(ICoreWebView2DownloadStartingEventArgs *args) {
    args->put_Handled(TRUE);
    if (!downloadResult || operation) {
      args->put_Cancel(TRUE);
      return;
    }
    args->get_DownloadOperation(&operation);
    int64_t total = 0;
    operation->get_TotalBytesToReceive(&total);
    LPWSTR mime = nullptr;
    operation->get_MimeType(&mime);
    const auto type = Narrow(mime);
    CoTaskMemFree(mime);
    Record("download.response", {{Value("expectedBytes"), Value(total)},
                                 {Value("contentType"), Value(type)}});
    if (total > kMaxBytes || type.find("text/html") != std::string::npos ||
        type.find("application/json") != std::string::npos) {
      args->put_Cancel(TRUE);
      FinishDownload(total > kMaxBytes ? "too_large" : "invalid_download");
      return;
    }
    args->put_ResultFilePath(downloadFile.c_str());
    std::weak_ptr<Impl> weak = shared_from_this();
    operation->add_BytesReceivedChanged(
        Callback<ICoreWebView2BytesReceivedChangedEventHandler>(
            [weak](ICoreWebView2DownloadOperation *op, IUnknown *) -> HRESULT {
              auto self = weak.lock();
              if (!self || !self->downloadResult)
                return S_OK;
              int64_t bytes = 0;
              op->get_BytesReceived(&bytes);
              if (bytes > kMaxBytes) {
                self->FinishDownload("too_large");
              }
              return S_OK;
            })
            .Get(),
        &bytesToken);
    operation->add_StateChanged(
        Callback<ICoreWebView2StateChangedEventHandler>(
            [weak](ICoreWebView2DownloadOperation *op, IUnknown *) -> HRESULT {
              auto self = weak.lock();
              if (!self || !self->downloadResult)
                return S_OK;
              COREWEBVIEW2_DOWNLOAD_STATE state{};
              op->get_State(&state);
              int64_t bytes = 0;
              op->get_BytesReceived(&bytes);
              if (state == COREWEBVIEW2_DOWNLOAD_STATE_COMPLETED)
                self->FinishDownload(bytes <= 0 || bytes > kMaxBytes
                                         ? "invalid_download"
                                         : nullptr);
              else if (state == COREWEBVIEW2_DOWNLOAD_STATE_INTERRUPTED) {
                COREWEBVIEW2_DOWNLOAD_INTERRUPT_REASON reason{};
                op->get_InterruptReason(&reason);
                self->Record(
                    "download.interrupted",
                    {{Value("reason"), Value(static_cast<int>(reason))}});
                self->FinishDownload("unavailable");
              }
              return S_OK;
            })
            .Get(),
        &stateToken);
  }
  void FinishDownload(const char *error) {
    if (!downloadResult)
      return;
    if (operation) {
      operation->remove_BytesReceivedChanged(bytesToken);
      operation->remove_StateChanged(stateToken);
      if (error)
        operation->Cancel();
      operation.Reset();
    }
    Record("download.finish",
           {{Value("success"), Value(error == nullptr)},
            {Value("errorCode"), Value(error ? error : "")}});
    auto result = std::move(downloadResult);
    if (error) {
      WIN32_FIND_DATA entry{};
      HANDLE files = FindFirstFile((downloadFolder + L"\\*").c_str(), &entry);
      if (files != INVALID_HANDLE_VALUE) {
        do {
          if (!(entry.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY))
            DeleteFile((downloadFolder + L"\\" + entry.cFileName).c_str());
        } while (FindNextFile(files, &entry));
        FindClose(files);
      }
      RemoveDirectory(downloadFolder.c_str());
      result->Error(error);
    } else
      result->Success(Value(Narrow(downloadFile.c_str())));
    downloadFile.clear();
    downloadFolder.clear();
  }
  void Tick() {
    const auto now = Clock::now();
    if (initializing && now > initDeadline) {
      FinishLogin(false, "timeout");
    }
    if (checkingLogin && now > checkDeadline) {
      checkingLogin = false;
      Record("login.sessionCheckTimeout");
    }
    if (downloadResult && !operation &&
        now - downloadStarted > std::chrono::seconds(30))
      FinishDownload("sign_in_required");
    if (downloadResult && now > downloadDeadline)
      FinishDownload("timeout");
    std::vector<std::string> expired;
    for (const auto &entry : requests)
      if (now - entry.second.started > std::chrono::seconds(25))
        expired.push_back(entry.first);
    for (const auto &id : expired) {
      Script("window.__prototypeRequests?.[" + grabcad::Quote(id) +
             "]?.abort();");
      CompleteRequest(id, "timeout");
    }
  }
};

WindowsGrabCad::WindowsGrabCad(HWND owner)
    : impl_(std::make_shared<Impl>(owner)) {}
WindowsGrabCad::~WindowsGrabCad() = default;
bool WindowsGrabCad::Handle(const flutter::MethodCall<Value> &call,
                            std::unique_ptr<Result> &result) {
  const auto &method = call.method_name();
  const Value *args = call.arguments();
  if (method == "grabcadSignIn")
    impl_->SignIn(args, std::move(result));
  else if (method == "grabcadRequest")
    impl_->RequestMetadata(args, std::move(result));
  else if (method == "grabcadCancelRequests") {
    impl_->CancelRequests(args);
    result->Success();
  } else if (method == "grabcadDownload")
    impl_->Download(args, std::move(result));
  else if (method == "grabcadCancelDownload") {
    impl_->FinishDownload("cancelled");
    result->Success();
  } else if (method == "grabcadDiagnostics")
    result->Success(impl_->Diagnostics());
  else if (method == "grabcadInstallRuntime") {
    ShellExecute(impl_->owner, L"open",
                 L"https://developer.microsoft.com/microsoft-edge/webview2/",
                 nullptr, nullptr, SW_SHOWNORMAL);
    result->Success();
  } else
    return false;
  return true;
}
