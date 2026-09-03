// Prototype — the Win32 half of `native_menu`.
//
// WHAT IS HERE, AND WHAT DELIBERATELY IS NOT
// ------------------------------------------
// The iOS plugin covers two very different jobs behind one channel: the
// SURFACES the app's design is made of (context menus, alerts, action sheets,
// the Settings form, the glass chrome) and the FILE ERRANDS only the OS can
// run (put this file where the user says, give me a file to open, tell me how
// much memory is left).
//
// Only the second half is implemented here. The first half is not missing by
// omission — the app already draws every one of those surfaces in Flutter for
// any host that is not iOS, in its own design system, and those fallbacks are
// what makes the desktop build the SAME app rather than a Win32 lookalike of
// it. Replacing them with menus from the shell would make the builds diverge,
// which is the one thing this port is not allowed to do.
//
// The exception is `importChoice`. That question has no Flutter fallback (see
// AppState._importMesh: off iOS the app used to pick "convert" for the user
// without asking), it is asked from a place with no BuildContext, and it must
// be answered before a conversion that can take half a minute starts. A modal
// the platform owns is the honest shape for it.
//
// This file is the GTK plugin's twin, method for method and contract for
// contract — same channel, same argument keys, same "false means nothing was
// presented". Where the two differ it is because the platforms differ, and
// each of those places says so.
#include "include/native_menu/native_menu_plugin_c_api.h"

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <windows.h>
// After windows.h, which they all need.
#include <commctrl.h>
#include <psapi.h>
#include <shellapi.h>
#include <shlobj.h>
#include <shobjidl.h>

#include <memory>
#include <string>
#include <vector>

namespace {

constexpr char kChannel[] = "prototype/native_menu";

using flutter::EncodableMap;
using flutter::EncodableValue;
using MethodResult = flutter::MethodResult<EncodableValue>;

// ---------------------------------------------------------------------------
// small helpers
// ---------------------------------------------------------------------------

std::wstring Utf16(const std::string& utf8) {
  if (utf8.empty()) return std::wstring();
  const int len = ::MultiByteToWideChar(CP_UTF8, 0, utf8.data(),
                                        static_cast<int>(utf8.size()), nullptr, 0);
  std::wstring out(len, L'\0');
  ::MultiByteToWideChar(CP_UTF8, 0, utf8.data(), static_cast<int>(utf8.size()),
                        out.data(), len);
  return out;
}

std::string Utf8(const std::wstring& utf16) {
  if (utf16.empty()) return std::string();
  const int len = ::WideCharToMultiByte(CP_UTF8, 0, utf16.data(),
                                        static_cast<int>(utf16.size()), nullptr,
                                        0, nullptr, nullptr);
  std::string out(len, '\0');
  ::WideCharToMultiByte(CP_UTF8, 0, utf16.data(), static_cast<int>(utf16.size()),
                        out.data(), len, nullptr, nullptr);
  return out;
}

const EncodableMap* AsMap(const EncodableValue* args) {
  return args == nullptr ? nullptr : std::get_if<EncodableMap>(args);
}

// Missing and wrong-typed are the same answer: the caller has a default.
std::string ArgString(const EncodableValue* args, const char* key) {
  const EncodableMap* map = AsMap(args);
  if (map == nullptr) return std::string();
  auto it = map->find(EncodableValue(std::string(key)));
  if (it == map->end()) return std::string();
  const auto* s = std::get_if<std::string>(&it->second);
  return s == nullptr ? std::string() : *s;
}

std::vector<std::string> ArgStringList(const EncodableValue* args,
                                       const char* key) {
  std::vector<std::string> out;
  const EncodableMap* map = AsMap(args);
  if (map == nullptr) return out;
  auto it = map->find(EncodableValue(std::string(key)));
  if (it == map->end()) return out;
  const auto* list = std::get_if<flutter::EncodableList>(&it->second);
  if (list == nullptr) return out;
  for (const auto& v : *list) {
    if (const auto* s = std::get_if<std::string>(&v)) out.push_back(*s);
  }
  return out;
}

bool FileExists(const std::wstring& path) {
  const DWORD attrs = ::GetFileAttributesW(path.c_str());
  return attrs != INVALID_FILE_ATTRIBUTES &&
         (attrs & FILE_ATTRIBUTE_DIRECTORY) == 0;
}

std::wstring BaseName(const std::wstring& path) {
  const size_t cut = path.find_last_of(L"\\/");
  return cut == std::wstring::npos ? path : path.substr(cut + 1);
}

// The window our dialogs are modal to. A dialog with no owner is a separate
// entry in the task switcher that can end up BEHIND the app, which reads as a
// frozen app rather than as a question.
HWND OwnerWindow(flutter::PluginRegistrarWindows* registrar) {
  if (registrar == nullptr || registrar->GetView() == nullptr) return nullptr;
  return registrar->GetView()->GetNativeWindow();
}

// ~/Documents, never the process's working directory — which is what the
// dialogs default to and is a meaningless place: an app started from a
// shortcut inherits whatever the shell was in, and one started from a terminal
// offers to save into the source tree.
void StartInDocuments(IFileDialog* dialog) {
  PWSTR docs = nullptr;
  if (FAILED(::SHGetKnownFolderPath(FOLDERID_Documents, 0, nullptr, &docs))) {
    return;
  }
  IShellItem* item = nullptr;
  if (SUCCEEDED(::SHCreateItemFromParsingName(docs, nullptr, IID_PPV_ARGS(&item)))) {
    // SetDefaultFolder, not SetFolder: this decides only the FIRST open. The
    // shell remembers where the user actually went, and overriding that every
    // time is the kind of help that reads as a bug.
    dialog->SetDefaultFolder(item);
    item->Release();
  }
  ::CoTaskMemFree(docs);
}

// The chosen path, or empty when the dialog was cancelled.
std::wstring ResultPath(IFileDialog* dialog) {
  IShellItem* item = nullptr;
  if (FAILED(dialog->GetResult(&item)) || item == nullptr) return std::wstring();
  PWSTR raw = nullptr;
  std::wstring out;
  if (SUCCEEDED(item->GetDisplayName(SIGDN_FILESYSPATH, &raw)) && raw != nullptr) {
    out = raw;
    ::CoTaskMemFree(raw);
  }
  item->Release();
  return out;
}

// ---------------------------------------------------------------------------
// export — "Save a copy"
// ---------------------------------------------------------------------------
bool HandleExport(flutter::PluginRegistrarWindows* registrar,
                  const EncodableValue* args) {
  const std::wstring path = Utf16(ArgString(args, "path"));
  if (path.empty() || !FileExists(path)) {
    // Same contract as iOS: false means "nothing was presented", and the Dart
    // side logs REFUSED rather than pretending a file went somewhere.
    return false;
  }

  IFileSaveDialog* dialog = nullptr;
  if (FAILED(::CoCreateInstance(CLSID_FileSaveDialog, nullptr, CLSCTX_INPROC_SERVER,
                                IID_PPV_ARGS(&dialog)))) {
    return false;
  }

  // The title comes from Dart, where the app's ARB catalogue is. The app is
  // natively German; a dialog that says "Save a copy" over a ribbon that says
  // "Exportieren" is the seam the user sees. The English here is a fallback
  // for an older app build, not the intended string. Windows localises the two
  // BUTTONS itself.
  const std::string title = ArgString(args, "saveTitle");
  dialog->SetTitle(title.empty() ? L"Save a copy" : Utf16(title).c_str());
  dialog->SetFileName(BaseName(path).c_str());

  // The extension the file already has, so the shell's overwrite prompt and
  // its "save as type" agree with what is actually being written.
  const std::wstring base = BaseName(path);
  const size_t dot = base.find_last_of(L'.');
  if (dot != std::wstring::npos && dot + 1 < base.size()) {
    dialog->SetDefaultExtension(base.substr(dot + 1).c_str());
  }

  DWORD options = 0;
  if (SUCCEEDED(dialog->GetOptions(&options))) {
    dialog->SetOptions(options | FOS_OVERWRITEPROMPT | FOS_PATHMUSTEXIST);
  }
  StartInDocuments(dialog);

  bool ok = false;
  if (SUCCEEDED(dialog->Show(OwnerWindow(registrar)))) {
    const std::wstring target = ResultPath(dialog);
    if (!target.empty()) {
      // FALSE = overwrite: the dialog already asked, and refusing here would
      // make Save a copy fail silently on the second export of the same name.
      ok = ::CopyFileW(path.c_str(), target.c_str(), FALSE) != 0;
      if (!ok) {
        ::OutputDebugStringW(L"native_menu: export failed to copy\n");
      }
    }
  }
  dialog->Release();
  return ok;
}

// ---------------------------------------------------------------------------
// share — "Open with…"
// ---------------------------------------------------------------------------
//
// There is no share sheet on Windows, and inventing one would be a worse
// answer than the true one: what the user wants from Share is the file in
// another program. `openas` is the shell's own verb for that — the same "Open
// with" dialog Explorer shows — and unlike a plain `open` it never silently
// launches the wrong registered handler for a .ptp.
bool HandleShare(flutter::PluginRegistrarWindows* registrar,
                 const EncodableValue* args) {
  const std::wstring path = Utf16(ArgString(args, "path"));
  if (path.empty() || !FileExists(path)) return false;

  SHELLEXECUTEINFOW info = {sizeof(SHELLEXECUTEINFOW)};
  info.fMask = SEE_MASK_INVOKEIDLIST | SEE_MASK_FLAG_NO_UI;
  info.hwnd = OwnerWindow(registrar);
  info.lpVerb = L"openas";
  info.lpFile = path.c_str();
  info.nShow = SW_SHOWNORMAL;
  if (::ShellExecuteExW(&info)) return true;

  // Nothing handles a .ptp or a .step on a bare Windows install, and some
  // shells refuse `openas` outright. Falling back to the exporter keeps Share
  // useful instead of silently doing nothing — the user asked to get the file
  // OUT of the app, and this is the other way to.
  ::OutputDebugStringW(L"native_menu: no 'Open with' — offering Save a copy\n");
  return HandleExport(registrar, args);
}

// ---------------------------------------------------------------------------
// openInPlace
// ---------------------------------------------------------------------------
//
// On iOS a path is not a durable handle and a security-scoped bookmark is; on
// Windows the path IS the durable handle, so the bookmark we hand back is the
// path itself. That keeps DocRef's contract intact — something opaque that
// resolves to a current path on a later launch — without pretending the two
// platforms have the same file model.
std::unique_ptr<EncodableValue> HandleOpenInPlace(
    flutter::PluginRegistrarWindows* registrar, const EncodableValue* args) {
  IFileOpenDialog* dialog = nullptr;
  if (FAILED(::CoCreateInstance(CLSID_FileOpenDialog, nullptr, CLSCTX_INPROC_SERVER,
                                IID_PPV_ARGS(&dialog)))) {
    return nullptr;
  }

  const std::string title = ArgString(args, "title");
  dialog->SetTitle(title.empty() ? L"Open" : Utf16(title).c_str());

  // One filter listing every extension the app can open, plus All files. The
  // extensions arrive from Dart (kOpenableExtensions) so this can never offer
  // a kind Open would then refuse. Windows matches its patterns
  // case-insensitively, so unlike GTK there is no second upper-case pattern
  // to add.
  const std::vector<std::string> exts = ArgStringList(args, "extensions");
  std::wstring known_pattern;
  for (const auto& e : exts) {
    if (!known_pattern.empty()) known_pattern += L";";
    known_pattern += L"*." + Utf16(e);
  }
  const std::wstring known_name =
      Utf16(ArgString(args, "knownFilterName")).empty()
          ? L"Documents this app can open"
          : Utf16(ArgString(args, "knownFilterName"));
  const std::wstring all_name = Utf16(ArgString(args, "allFilesFilterName")).empty()
                                    ? L"All files"
                                    : Utf16(ArgString(args, "allFilesFilterName"));
  std::vector<COMDLG_FILTERSPEC> filters;
  if (!known_pattern.empty()) {
    filters.push_back({known_name.c_str(), known_pattern.c_str()});
  }
  filters.push_back({all_name.c_str(), L"*.*"});
  dialog->SetFileTypes(static_cast<UINT>(filters.size()), filters.data());

  DWORD options = 0;
  if (SUCCEEDED(dialog->GetOptions(&options))) {
    dialog->SetOptions(options | FOS_FILEMUSTEXIST | FOS_PATHMUSTEXIST);
  }
  StartInDocuments(dialog);

  std::wstring chosen;
  if (SUCCEEDED(dialog->Show(OwnerWindow(registrar)))) {
    chosen = ResultPath(dialog);
  }
  dialog->Release();
  if (chosen.empty()) return nullptr;

  const std::string utf8 = Utf8(chosen);
  EncodableMap result;
  result[EncodableValue("path")] = EncodableValue(utf8);
  result[EncodableValue("bookmark")] = EncodableValue(utf8);
  return std::make_unique<EncodableValue>(result);
}

// The bookmark is the path (see above), so resolving one is asking whether the
// file is still there. Null when it is not — which the app reads as "could not
// re-open", leaving the gallery entry alone rather than forgetting it.
std::unique_ptr<EncodableValue> HandleResolveBookmark(const EncodableValue* args) {
  const std::string bookmark = ArgString(args, "bookmark");
  if (bookmark.empty() || !FileExists(Utf16(bookmark))) return nullptr;
  EncodableMap result;
  result[EncodableValue("path")] = EncodableValue(bookmark);
  result[EncodableValue("bookmark")] = EncodableValue(bookmark);
  return std::make_unique<EncodableValue>(result);
}

// ---------------------------------------------------------------------------
// importChoice
// ---------------------------------------------------------------------------
//
// A task dialog rather than a message box, because this question has two
// answers with REASONS: "editable CAD" against "every triangle kept". Command
// links are the one Win32 control that shows a label and its explanation
// together, which is the shape UIKit's action sheet has and the shape the
// decision needs.
std::unique_ptr<EncodableValue> HandleImportChoice(
    flutter::PluginRegistrarWindows* registrar, const EncodableValue* args) {
  const std::wstring title = Utf16(ArgString(args, "title"));
  const std::wstring message = Utf16(ArgString(args, "message"));
  const std::wstring convert_label = Utf16(ArgString(args, "convertLabel"));
  const std::wstring convert_detail = Utf16(ArgString(args, "convertDetail"));
  const std::wstring faceted_label = Utf16(ArgString(args, "facetedLabel"));
  const std::wstring faceted_detail = Utf16(ArgString(args, "facetedDetail"));

  // A command link's second line is separated from its label by a newline;
  // that is the control's own convention, not a hack.
  std::wstring convert_text = convert_label.empty() ? L"Convert" : convert_label;
  if (!convert_detail.empty()) convert_text += L"\n" + convert_detail;
  std::wstring faceted_text = faceted_label;
  if (!faceted_label.empty() && !faceted_detail.empty()) {
    faceted_text += L"\n" + faceted_detail;
  }

  enum { kConvert = 101, kFaceted = 102 };
  std::vector<TASKDIALOG_BUTTON> buttons;
  buttons.push_back({kConvert, convert_text.c_str()});
  if (!faceted_label.empty()) {
    buttons.push_back({kFaceted, faceted_text.c_str()});
  }

  // No faceted BUTTON but a faceted detail means the detail is the REASON
  // there is none, so it belongs in the body instead of being dropped.
  std::wstring body = message;
  if (faceted_label.empty() && !faceted_detail.empty()) {
    if (!body.empty()) body += L"\n\n";
    body += faceted_detail;
  }

  TASKDIALOGCONFIG config = {sizeof(TASKDIALOGCONFIG)};
  config.hwndParent = OwnerWindow(registrar);
  config.dwFlags = TDF_USE_COMMAND_LINKS | TDF_POSITION_RELATIVE_TO_WINDOW;
  // The system's own Cancel, so it carries the platform's wording in the
  // user's language rather than the app's guess at it, and so Escape and the
  // title bar's X both land on it.
  config.dwCommonButtons = TDCBF_CANCEL_BUTTON;
  config.pszWindowTitle = title.empty() ? L"Import" : title.c_str();
  config.pszMainInstruction = title.empty() ? L"Import" : title.c_str();
  config.pszContent = body.empty() ? nullptr : body.c_str();
  config.cButtons = static_cast<UINT>(buttons.size());
  config.pButtons = buttons.data();
  config.nDefaultButton = kConvert;

  int pressed = 0;
  if (FAILED(::TaskDialogIndirect(&config, &pressed, nullptr, nullptr))) {
    return nullptr;
  }

  // Anything that is not one of the two choices — Escape, the window closed,
  // Cancel — is a cancellation, and the app must not import on one.
  if (pressed == kConvert) {
    return std::make_unique<EncodableValue>(std::string("convert"));
  }
  if (pressed == kFaceted) {
    return std::make_unique<EncodableValue>(std::string("faceted"));
  }
  return nullptr;
}

// ---------------------------------------------------------------------------
// perfProbe
// ---------------------------------------------------------------------------
//
// The same keys PerfProbe.swift reports, from the places Windows keeps them.
// Anything this machine cannot answer is simply absent from the map — the
// readers all treat a missing key as "unknown", and a zero would be a lie.
// There is no thermalCelsius here: Windows exposes temperature only through
// WMI's OEM-optional MSAcpi_ThermalZoneTemperature, which on most laptops
// returns nothing, and a probe that is usually absent is worse than one that
// is honestly missing.
EncodableValue HandlePerfProbe() {
  EncodableMap map;

  PROCESS_MEMORY_COUNTERS_EX counters = {sizeof(counters)};
  if (::GetProcessMemoryInfo(::GetCurrentProcess(),
                             reinterpret_cast<PROCESS_MEMORY_COUNTERS*>(&counters),
                             sizeof(counters))) {
    // PrivateUsage, not WorkingSetSize: the number that matters when a
    // conversion is about to allocate a hundred megabytes of triangles is what
    // the process has COMMITTED, not what happens to be resident right now.
    map[EncodableValue("footprintBytes")] =
        EncodableValue(static_cast<int64_t>(counters.PrivateUsage));
  }

  MEMORYSTATUSEX status = {sizeof(MEMORYSTATUSEX)};
  if (::GlobalMemoryStatusEx(&status)) {
    map[EncodableValue("availableBytes")] =
        EncodableValue(static_cast<int64_t>(status.ullAvailPhys));
    map[EncodableValue("physicalBytes")] =
        EncodableValue(static_cast<int64_t>(status.ullTotalPhys));
  }

  SYSTEM_INFO info = {};
  ::GetNativeSystemInfo(&info);
  map[EncodableValue("processors")] =
      EncodableValue(static_cast<int64_t>(info.dwNumberOfProcessors));
  map[EncodableValue("platform")] = EncodableValue(std::string("windows"));
  return EncodableValue(map);
}

// ---------------------------------------------------------------------------
// the plugin
// ---------------------------------------------------------------------------
class NativeMenuPlugin : public flutter::Plugin {
 public:
  explicit NativeMenuPlugin(flutter::PluginRegistrarWindows* registrar)
      : registrar_(registrar) {}
  virtual ~NativeMenuPlugin() = default;

  NativeMenuPlugin(const NativeMenuPlugin&) = delete;
  NativeMenuPlugin& operator=(const NativeMenuPlugin&) = delete;

  void HandleMethodCall(const flutter::MethodCall<EncodableValue>& call,
                        std::unique_ptr<MethodResult> result) {
    const std::string& method = call.method_name();
    const EncodableValue* args = call.arguments();

    if (method == "isSupported") {
      // The MENU surfaces, which this plugin does not provide. Answering true
      // here would switch the app off its Flutter chrome and leave it with
      // nothing to draw.
      result->Success(EncodableValue(false));
    } else if (method == "export") {
      result->Success(EncodableValue(HandleExport(registrar_, args)));
    } else if (method == "share") {
      result->Success(EncodableValue(HandleShare(registrar_, args)));
    } else if (method == "openInPlace") {
      auto value = HandleOpenInPlace(registrar_, args);
      result->Success(value == nullptr ? EncodableValue() : *value);
    } else if (method == "resolveBookmark") {
      auto value = HandleResolveBookmark(args);
      result->Success(value == nullptr ? EncodableValue() : *value);
    } else if (method == "releaseDocument") {
      // Nothing to release: access to a path does not expire here.
      result->Success(EncodableValue(true));
    } else if (method == "probeContentTypes") {
      // There is no equivalent of a dynamic UTI to warn about; the dialog
      // takes glob patterns and cannot be killed by one.
      result->Success(EncodableValue(flutter::EncodableList()));
    } else if (method == "importChoice") {
      auto value = HandleImportChoice(registrar_, args);
      result->Success(value == nullptr ? EncodableValue() : *value);
    } else if (method == "perfProbe") {
      result->Success(HandlePerfProbe());
    } else {
      // Everything else is a surface the app draws itself off iOS. Not
      // implemented is the honest answer, and the Dart side already treats it
      // as one.
      result->NotImplemented();
    }
  }

 private:
  flutter::PluginRegistrarWindows* registrar_;
};

}  // namespace

void NativeMenuPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  auto* windows_registrar =
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar);

  auto channel = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      windows_registrar->messenger(), kChannel,
      &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<NativeMenuPlugin>(windows_registrar);
  channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto& call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });
  windows_registrar->AddPlugin(std::move(plugin));
}
