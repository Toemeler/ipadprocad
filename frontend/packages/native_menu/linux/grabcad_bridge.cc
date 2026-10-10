#include "grabcad_bridge.h"
#include "../common/grabcad_protocol.h"
#include <chrono>
#include <deque>
#include <dlfcn.h>
#include <glib/gstdio.h>
#include <map>
#include <string>
#include <vector>
#include <webkit2/webkit2.h>

namespace {
// Load WebKit only when GrabCAD is used. A missing browser runtime must not
// make the CAD app fail to launch. Headers are a build-time dependency only.
#define GRABCAD_WEBKIT_API(X)                                                  \
  X(webkit_website_data_manager_new)                                           \
  X(webkit_web_context_new_with_website_data_manager) X(                       \
      webkit_web_context_get_cookie_manager)                                   \
      X(webkit_cookie_manager_set_persistent_storage) X(                       \
          webkit_user_content_manager_new)                                     \
          X(webkit_user_content_manager_register_script_message_handler) X(    \
              webkit_web_view_get_type) X(webkit_web_view_load_uri)            \
              X(webkit_web_view_get_uri) X(                                    \
                  webkit_web_view_evaluate_javascript)                         \
                  X(webkit_javascript_result_get_js_value) X(                  \
                      jsc_value_to_string) X(webkit_web_view_download_uri)     \
                      X(webkit_download_set_destination) X(                    \
                          webkit_download_get_response)                        \
                          X(webkit_uri_response_get_content_length) X(         \
                              webkit_uri_response_get_mime_type)               \
                              X(webkit_uri_response_get_status_code) X(        \
                                  webkit_download_get_received_data_length)    \
                                  X(webkit_download_cancel)                    \
                                      X(webkit_navigation_action_get_request)  \
                                          X(webkit_uri_request_get_uri)
struct Api {
  void *library = nullptr;
#define DECLARE(name) decltype(&name) name##_ = nullptr;
  GRABCAD_WEBKIT_API(DECLARE)
#undef DECLARE
  void Load() {
    if (library)
      return;
    library = dlopen("libwebkit2gtk-4.1.so.0", RTLD_NOW | RTLD_LOCAL);
#define LOAD(name)                                                             \
  name##_ = library ? reinterpret_cast<decltype(&name)>(dlsym(library, #name)) \
                    : nullptr;
    GRABCAD_WEBKIT_API(LOAD)
#undef LOAD
  }
  bool Ready() const {
    bool ready = library != nullptr;
#define CHECK(name) ready = ready && name##_ != nullptr;
    GRABCAD_WEBKIT_API(CHECK)
#undef CHECK
    return ready;
  }
  // Never dlclose: GTypes and asynchronous WebKit processes outlive a view.
};
Api &BrowserApi() {
  static Api api;
  return api;
}
using Clock = std::chrono::steady_clock;
constexpr guint64 kMaxBytes = 250ULL * 1024 * 1024;
const char *String(FlValue *args, const char *key) {
  if (!args || fl_value_get_type(args) != FL_VALUE_TYPE_MAP)
    return "";
  FlValue *value = fl_value_lookup_string(args, key);
  return value && fl_value_get_type(value) == FL_VALUE_TYPE_STRING
             ? fl_value_get_string(value)
             : "";
}
void Success(FlMethodCall *call, FlValue *value = nullptr) {
  fl_method_call_respond_success(call, value, nullptr);
}
void Error(FlMethodCall *call, const char *code) {
  fl_method_call_respond_error(call, code, nullptr, nullptr, nullptr);
}
void Field(FlValue *value, const char *key, const char *text) {
  fl_value_set_string_take(value, key, fl_value_new_string(text));
}
} // namespace
struct LinuxGrabCad::Impl : std::enable_shared_from_this<Impl> {
  Api &api = BrowserApi();
  GtkWidget *window = nullptr, *note = nullptr;
  WebKitWebView *web = nullptr;
  WebKitWebContext *context = nullptr;
  WebKitUserContentManager *manager = nullptr;
  WebKitDownload *download = nullptr;
  FlMethodCall *loginCall = nullptr, *downloadCall = nullptr;
  guint timer = 0;
  bool checking = false;
  Clock::time_point downloadDeadline, checkDeadline, downloadStarted;
  std::string help, unavailable, folder, file;
  std::deque<FlValue *> events;
  int dropped = 0;
  struct Request {
    FlMethodCall *call;
    Clock::time_point started;
    std::string path;
  };
  std::map<std::string, Request> requests;
  ~Impl() {
    if (timer)
      g_source_remove(timer);
    if (download) {
      g_signal_handlers_disconnect_by_data(download, this);
      api.webkit_download_cancel_(download);
      g_object_unref(download);
    }
    if (manager)
      g_signal_handlers_disconnect_by_data(manager, this);
    if (web)
      g_signal_handlers_disconnect_by_data(web, this);
    if (window) {
      g_signal_handlers_disconnect_by_data(window, this);
      gtk_widget_destroy(window);
    }
    if (manager)
      g_object_unref(manager);
    if (context)
      g_object_unref(context);
    g_clear_object(&loginCall);
    g_clear_object(&downloadCall);
    for (auto &request : requests)
      g_object_unref(request.second.call);
    for (auto *value : events)
      fl_value_unref(value);
  }
  void Record(const char *event, FlValue *fields = nullptr) {
    FlValue *value = fields ? fl_value_ref(fields) : fl_value_new_map();
    Field(value, "event", event);
    g_autoptr(GDateTime) now = g_date_time_new_now_utc();
    g_autofree gchar *time = g_date_time_format_iso8601(now);
    Field(value, "time", time);
    if (events.size() == 300) {
      fl_value_unref(events.front());
      events.pop_front();
      ++dropped;
    }
    events.push_back(value);
  }
  FlValue *Diagnostics() {
    FlValue *value = fl_value_new_map();
    Field(value, "backend", "WebKitGTK");
    fl_value_set_string_take(value, "schemaVersion", fl_value_new_int(1));
    fl_value_set_string_take(value, "droppedEvents", fl_value_new_int(dropped));
    fl_value_set_string_take(value, "loginActive",
                             fl_value_new_bool(loginCall != nullptr));
    fl_value_set_string_take(value, "downloadActive",
                             fl_value_new_bool(downloadCall != nullptr));
    fl_value_set_string_take(value, "metadataRequestsActive",
                             fl_value_new_int(requests.size()));
    fl_value_set_string_take(value, "browserReady",
                             fl_value_new_bool(web != nullptr));
    FlValue *history = fl_value_new_list();
    for (auto *event : events)
      fl_value_append(history, event);
    fl_value_set_string_take(value, "events", history);
    return value;
  }
  void Script(const std::string &script) {
    if (web)
      api.webkit_web_view_evaluate_javascript_(
          web, script.c_str(), -1, nullptr, nullptr, nullptr, nullptr, nullptr);
  }
  void FinishLogin(bool success, const char *error = nullptr) {
    if (!loginCall)
      return;
    g_autoptr(FlValue) fields = fl_value_new_map();
    fl_value_set_string_take(fields, "authenticated",
                             fl_value_new_bool(success));
    if (error)
      Field(fields, "errorCode", error);
    Record("login.finish", fields);
    if (window)
      gtk_widget_hide(window);
    auto *call = loginCall;
    loginCall = nullptr;
    checking = false;
    if (error)
      Error(call, error);
    else {
      g_autoptr(FlValue) value = fl_value_new_bool(success);
      Success(call, value);
    }
    g_object_unref(call);
  }
  void SignIn(GtkWindow *owner, FlMethodCall *call, FlValue *args) {
    if (loginCall || downloadCall || !requests.empty()) {
      Error(call, "busy");
      return;
    }
    loginCall = FL_METHOD_CALL(g_object_ref(call));
    help = String(args, "help");
    unavailable = String(args, "unavailable");
    Record("login.present");
    api.Load();
    if (!api.Ready()) {
      Record("browser.runtimeMissing");
      FinishLogin(false, "webkit_runtime_missing");
      return;
    }
    if (!window) {
      g_autofree gchar *data = g_build_filename(
          g_get_user_data_dir(), "prototype", "grabcad", nullptr);
      g_autofree gchar *cache = g_build_filename(
          g_get_user_cache_dir(), "prototype", "grabcad", nullptr);
      if (g_mkdir_with_parents(data, 0700) ||
          g_mkdir_with_parents(cache, 0700)) {
        FinishLogin(false, "browser_unavailable");
        return;
      }
      WebKitWebsiteDataManager *store = api.webkit_website_data_manager_new_(
          "base-data-directory", data, "base-cache-directory", cache, nullptr);
      context = api.webkit_web_context_new_with_website_data_manager_(store);
      g_object_unref(store);
      g_autofree gchar *cookies =
          g_build_filename(data, "cookies.sqlite", nullptr);
      api.webkit_cookie_manager_set_persistent_storage_(
          api.webkit_web_context_get_cookie_manager_(context), cookies,
          WEBKIT_COOKIE_PERSISTENT_STORAGE_SQLITE);
      manager = api.webkit_user_content_manager_new_();
      api.webkit_user_content_manager_register_script_message_handler_(
          manager, "prototype");
      g_signal_connect(
          manager, "script-message-received::prototype",
          G_CALLBACK(+[](WebKitUserContentManager *,
                         WebKitJavascriptResult *result, gpointer data) {
            auto *self = static_cast<Impl *>(data);
            auto keep = self->shared_from_this();
            const char *uri = self->api.webkit_web_view_get_uri_(self->web);
            if (!uri || !grabcad::GrabCadUrl(uri))
              return;
            g_autofree gchar *message = self->api.jsc_value_to_string_(
                self->api.webkit_javascript_result_get_js_value_(result));
            if (message)
              self->Message(message);
          }),
          this);
      web = reinterpret_cast<WebKitWebView *>(
          g_object_new(api.webkit_web_view_get_type_(), "web-context", context,
                       "user-content-manager", manager, nullptr));
      window = gtk_window_new(GTK_WINDOW_TOPLEVEL);
      gtk_window_set_default_size(GTK_WINDOW(window), 1050, 760);
      gtk_window_set_modal(GTK_WINDOW(window), TRUE);
      GtkWidget *column = gtk_box_new(GTK_ORIENTATION_VERTICAL, 8);
      gtk_container_add(GTK_CONTAINER(window), column);
      GtkWidget *row = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
      gtk_box_pack_start(GTK_BOX(column), row, FALSE, FALSE, 8);
      note = gtk_label_new(help.c_str());
      gtk_label_set_line_wrap(GTK_LABEL(note), TRUE);
      gtk_box_pack_start(GTK_BOX(row), note, TRUE, TRUE, 8);
      GtkWidget *done = gtk_button_new_with_label(String(args, "done"));
      gtk_box_pack_end(GTK_BOX(row), done, FALSE, FALSE, 8);
      g_signal_connect(done, "clicked",
                       G_CALLBACK(+[](GtkButton *, gpointer data) {
                         static_cast<Impl *>(data)->CheckLogin();
                       }),
                       this);
      gtk_box_pack_start(GTK_BOX(column), GTK_WIDGET(web), TRUE, TRUE, 0);
      g_signal_connect(
          window, "delete-event",
          G_CALLBACK(+[](GtkWidget *, GdkEvent *, gpointer data) -> gboolean {
            static_cast<Impl *>(data)->FinishLogin(false);
            return TRUE;
          }),
          this);
      g_signal_connect(web, "load-changed",
                       G_CALLBACK(+[](WebKitWebView *, WebKitLoadEvent event,
                                      gpointer data) {
                         auto *self = static_cast<Impl *>(data);
                         if (event == WEBKIT_LOAD_FINISHED) {
                           self->Record("browser.navigationFinished");
                           self->CheckLogin();
                         }
                       }),
                       this);
      g_signal_connect(
          web, "load-failed",
          G_CALLBACK(+[](WebKitWebView *, WebKitLoadEvent, const gchar *,
                         GError *error, gpointer data) -> gboolean {
            auto *self = static_cast<Impl *>(data);
            g_autoptr(FlValue) fields = fl_value_new_map();
            Field(fields, "domain", g_quark_to_string(error->domain));
            fl_value_set_string_take(fields, "code",
                                     fl_value_new_int(error->code));
            self->Record("browser.navigationError", fields);
            if (self->loginCall)
              gtk_label_set_text(GTK_LABEL(self->note),
                                 self->unavailable.c_str());
            return FALSE;
          }),
          this);
      g_signal_connect(web, "web-process-terminated",
                       G_CALLBACK(+[](WebKitWebView *,
                                      WebKitWebProcessTerminationReason reason,
                                      gpointer data) {
                         auto *self = static_cast<Impl *>(data);
                         g_autoptr(FlValue) fields = fl_value_new_map();
                         fl_value_set_string_take(fields, "reason",
                                                  fl_value_new_int(reason));
                         self->Record("browser.processFailed", fields);
                         self->FailRequests("unavailable");
                         self->FinishDownload("unavailable");
                         self->FinishLogin(false, "browser_unavailable");
                       }),
                       this);
      // Keep website popup logins inside the same native session.
      g_signal_connect(
          web, "create",
          G_CALLBACK(+[](WebKitWebView *, WebKitNavigationAction *action,
                         gpointer data) -> GtkWidget * {
            auto *self = static_cast<Impl *>(data);
            const char *uri = self->api.webkit_uri_request_get_uri_(
                self->api.webkit_navigation_action_get_request_(action));
            if (self->loginCall && uri &&
                std::string(uri).rfind("https://", 0) == 0)
              self->api.webkit_web_view_load_uri_(self->web, uri);
            return nullptr;
          }),
          this);
      timer = g_timeout_add_seconds(
          1,
          +[](gpointer data) -> gboolean {
            static_cast<Impl *>(data)->Tick();
            return G_SOURCE_CONTINUE;
          },
          this);
    }
    gtk_window_set_transient_for(GTK_WINDOW(window), owner);
    gtk_window_set_title(GTK_WINDOW(window), String(args, "title"));
    gtk_label_set_text(GTK_LABEL(note), help.c_str());
    gtk_widget_show_all(window);
    gtk_window_present(GTK_WINDOW(window));
    api.webkit_web_view_load_uri_(web, "https://grabcad.com/login");
  }
  void CheckLogin() {
    if (!loginCall || checking || !web)
      return;
    const char *uri = api.webkit_web_view_get_uri_(web);
    if (!uri || !grabcad::GrabCadUrl(uri))
      return;
    checking = true;
    checkDeadline = Clock::now() + std::chrono::seconds(10);
    Script(grabcad::LoginScript());
  }
  void Message(const std::string &message) {
    auto first = message.find('\n');
    if (first == std::string::npos)
      return;
    const auto id = message.substr(0, first);
    if (id == "auth") {
      checking = false;
      if (!loginCall)
        return;
      if (message.substr(first + 1) == "1")
        FinishLogin(true);
      else {
        Record("login.sessionUnauthenticated");
        if (message.substr(first + 1) == "error")
          gtk_label_set_text(GTK_LABEL(note), unavailable.c_str());
      }
      return;
    }
    auto it = requests.find(id);
    if (it == requests.end())
      return;
    auto second = message.find('\n', first + 1);
    if (second == std::string::npos)
      return;
    const auto statusText = message.substr(first + 1, second - first - 1);
    char *end = nullptr;
    const long status = strtol(statusText.c_str(), &end, 10);
    if (!end || *end || statusText.empty()) {
      CompleteRequest(id, "invalid_response");
      return;
    }
    if (status == -1) {
      CompleteRequest(id, message.substr(second + 1).c_str());
      return;
    }
    auto third = message.find('\n', second + 1);
    if (third == std::string::npos || message.size() > 9 * 1024 * 1024) {
      CompleteRequest(id, "invalid_response");
      return;
    }
    g_autoptr(FlValue) response = fl_value_new_map();
    fl_value_set_string_take(response, "status", fl_value_new_int(status));
    Field(response, "contentType",
          message.substr(second + 1, third - second - 1).c_str());
    Field(response, "body", message.substr(third + 1).c_str());
    g_autoptr(FlValue) fields = fl_value_new_map();
    Field(fields, "path", it->second.path.c_str());
    fl_value_set_string_take(fields, "status", fl_value_new_int(status));
    fl_value_set_string_take(
        fields, "elapsedMs",
        fl_value_new_int(std::chrono::duration_cast<std::chrono::milliseconds>(
                             Clock::now() - it->second.started)
                             .count()));
    Record("metadata.finish", fields);
    FlMethodCall *call = it->second.call;
    requests.erase(it);
    Success(call, response);
    g_object_unref(call);
  }
  void RequestMetadata(FlMethodCall *call, FlValue *args) {
    std::string id = String(args, "id"), path = String(args, "path"),
                body = String(args, "body");
    FlValue *bodyValue = args && fl_value_get_type(args) == FL_VALUE_TYPE_MAP
                             ? fl_value_lookup_string(args, "body")
                             : nullptr;
    bool post =
        bodyValue && fl_value_get_type(bodyValue) == FL_VALUE_TYPE_STRING;
    if (id.empty() || id.size() > 100 ||
        id.find_first_of("\r\n") != std::string::npos || requests.count(id) ||
        !grabcad::MetadataPath(path) ||
        (post && (path != "models" || body.size() > 65536))) {
      Error(call, "invalid_request");
      return;
    }
    if (!web || loginCall || downloadCall) {
      Error(call, "access_denied");
      return;
    }
    g_autoptr(FlValue) fields = fl_value_new_map();
    Field(fields, "path", path.substr(0, path.find('?')).c_str());
    Field(fields, "method", post ? "POST" : "GET");
    Record("metadata.start", fields);
    requests.emplace(id, Request{FL_METHOD_CALL(g_object_ref(call)),
                                 Clock::now(), path.substr(0, path.find('?'))});
    Script(grabcad::RequestScript(id, path, post ? &body : nullptr));
  }
  void CompleteRequest(const std::string &id, const char *error) {
    auto it = requests.find(id);
    if (it == requests.end())
      return;
    g_autoptr(FlValue) fields = fl_value_new_map();
    Field(fields, "path", it->second.path.c_str());
    Field(fields, "errorCode", error);
    Record("metadata.finish", fields);
    auto *call = it->second.call;
    requests.erase(it);
    Error(call, error);
    g_object_unref(call);
  }
  void FailRequests(const char *error) {
    while (!requests.empty())
      CompleteRequest(requests.begin()->first, error);
  }
  void CancelRequests(FlValue *args) {
    FlValue *ids = args && fl_value_get_type(args) == FL_VALUE_TYPE_MAP
                       ? fl_value_lookup_string(args, "ids")
                       : nullptr;
    if (!ids || fl_value_get_type(ids) != FL_VALUE_TYPE_LIST)
      return;
    for (size_t i = 0; i < fl_value_get_length(ids); ++i) {
      auto *value = fl_value_get_list_value(ids, i);
      if (fl_value_get_type(value) != FL_VALUE_TYPE_STRING)
        continue;
      std::string id = fl_value_get_string(value);
      if (!requests.count(id))
        continue;
      Script("window.__prototypeRequests?.[" + grabcad::Quote(id) +
             "]?.abort();");
      CompleteRequest(id, "cancelled");
    }
  }
  void Download(FlMethodCall *call, FlValue *args) {
    const std::string url = String(args, "url"), name = String(args, "name");
    if (downloadCall || loginCall || !requests.empty()) {
      Error(call, "busy");
      return;
    }
    if (!web) {
      Error(call, "sign_in_required");
      return;
    }
    if (!grabcad::GrabCadUrl(url) || !grabcad::FileName(name)) {
      Error(call, "invalid_download");
      return;
    }
    g_autoptr(GError) error = nullptr;
    g_autofree gchar *directory = g_dir_make_tmp("grabcad_XXXXXX", &error);
    if (!directory) {
      Error(call, "invalid_download");
      return;
    }
    folder = directory;
    file = folder + "/" + name;
    downloadCall = FL_METHOD_CALL(g_object_ref(call));
    downloadStarted = Clock::now();
    downloadDeadline = downloadStarted + std::chrono::minutes(5);
    g_autoptr(FlValue) fields = fl_value_new_map();
    Field(fields, "name", name.c_str());
    Record("download.start", fields);
    download = api.webkit_web_view_download_uri_(web, url.c_str());
    if (!download) {
      FinishDownload("unavailable");
      return;
    }
    g_signal_connect(
        download, "decide-destination",
        G_CALLBACK(+[](WebKitDownload *d, const gchar *,
                       gpointer data) -> gboolean {
          auto *self = static_cast<Impl *>(data);
          auto *response = self->api.webkit_download_get_response_(d);
          guint64 total =
              response
                  ? self->api.webkit_uri_response_get_content_length_(response)
                  : 0;
          guint status =
              response
                  ? self->api.webkit_uri_response_get_status_code_(response)
                  : 0;
          const char *mime =
              response ? self->api.webkit_uri_response_get_mime_type_(response)
                       : nullptr;
          g_autoptr(FlValue) fields = fl_value_new_map();
          fl_value_set_string_take(fields, "status", fl_value_new_int(status));
          fl_value_set_string_take(fields, "expectedBytes",
                                   fl_value_new_int(total));
          Field(fields, "contentType", mime ? mime : "");
          self->Record("download.response", fields);
          std::string type = mime ? mime : "";
          if (total > kMaxBytes || status != 200 ||
              type.find("text/html") != std::string::npos ||
              type.find("application/json") != std::string::npos) {
            self->FinishDownload(total > kMaxBytes ? "too_large"
                                 : status == 401 || status == 403 ||
                                         type.find("text/html") !=
                                             std::string::npos
                                     ? "sign_in_required"
                                     : "invalid_download");
            return TRUE;
          }
          g_autofree gchar *destination =
              g_filename_to_uri(self->file.c_str(), nullptr, nullptr);
          self->api.webkit_download_set_destination_(d, destination);
          return TRUE;
        }),
        this);
    g_signal_connect(download, "received-data",
                     G_CALLBACK(+[](WebKitDownload *d, guint64, gpointer data) {
                       auto *self = static_cast<Impl *>(data);
                       if (self->api.webkit_download_get_received_data_length_(
                               d) > kMaxBytes)
                         self->FinishDownload("too_large");
                     }),
                     this);
    g_signal_connect(
        download, "failed",
        G_CALLBACK(+[](WebKitDownload *, GError *error, gpointer data) {
          auto *self = static_cast<Impl *>(data);
          g_autoptr(FlValue) fields = fl_value_new_map();
          Field(fields, "domain", g_quark_to_string(error->domain));
          fl_value_set_string_take(fields, "code",
                                   fl_value_new_int(error->code));
          self->Record("download.networkError", fields);
          self->FinishDownload("unavailable");
        }),
        this);
    g_signal_connect(
        download, "finished", G_CALLBACK(+[](WebKitDownload *d, gpointer data) {
          auto *self = static_cast<Impl *>(data);
          guint64 bytes =
              self->api.webkit_download_get_received_data_length_(d);
          g_autoptr(FlValue) fields = fl_value_new_map();
          fl_value_set_string_take(fields, "bytes", fl_value_new_int(bytes));
          self->Record("download.received", fields);
          self->FinishDownload(
              bytes == 0 || bytes > kMaxBytes ? "invalid_download" : nullptr);
        }),
        this);
  }
  void FinishDownload(const char *error) {
    if (!downloadCall)
      return;
    if (download) {
      g_signal_handlers_disconnect_by_data(download, this);
      if (error)
        api.webkit_download_cancel_(download);
      g_clear_object(&download);
    }
    g_autoptr(FlValue) fields = fl_value_new_map();
    fl_value_set_string_take(fields, "success", fl_value_new_bool(!error));
    if (error)
      Field(fields, "errorCode", error);
    Record("download.finish", fields);
    auto *call = downloadCall;
    downloadCall = nullptr;
    if (error) {
      GDir *entries = g_dir_open(folder.c_str(), 0, nullptr);
      if (entries) {
        const char *name = nullptr;
        while ((name = g_dir_read_name(entries)))
          g_remove((folder + "/" + name).c_str());
        g_dir_close(entries);
      }
      g_rmdir(folder.c_str());
      Error(call, error);
    } else {
      g_autoptr(FlValue) value = fl_value_new_string(file.c_str());
      Success(call, value);
    }
    g_object_unref(call);
    file.clear();
    folder.clear();
  }
  void Tick() {
    const auto now = Clock::now();
    if (checking && now > checkDeadline) {
      checking = false;
      Record("login.sessionCheckTimeout");
    }
    if (downloadCall && now > downloadDeadline)
      FinishDownload("timeout");
    std::vector<std::string> expired;
    for (const auto &request : requests)
      if (now - request.second.started > std::chrono::seconds(25))
        expired.push_back(request.first);
    for (const auto &id : expired) {
      Script("window.__prototypeRequests?.[" + grabcad::Quote(id) +
             "]?.abort();");
      CompleteRequest(id, "timeout");
    }
  }
};
LinuxGrabCad::LinuxGrabCad() : impl_(std::make_shared<Impl>()) {}
LinuxGrabCad::~LinuxGrabCad() = default;
bool LinuxGrabCad::Handle(GtkWindow *owner, FlMethodCall *call) {
  const std::string method = fl_method_call_get_name(call);
  auto *args = fl_method_call_get_args(call);
  if (method == "grabcadSignIn")
    impl_->SignIn(owner, call, args);
  else if (method == "grabcadRequest")
    impl_->RequestMetadata(call, args);
  else if (method == "grabcadCancelRequests") {
    impl_->CancelRequests(args);
    Success(call);
  } else if (method == "grabcadDownload")
    impl_->Download(call, args);
  else if (method == "grabcadCancelDownload") {
    impl_->FinishDownload("cancelled");
    Success(call);
  } else if (method == "grabcadDiagnostics") {
    g_autoptr(FlValue) value = impl_->Diagnostics();
    Success(call, value);
  } else
    return false;
  return true;
}
