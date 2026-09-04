// Prototype — the GTK half of `native_menu`.
//
// WHAT IS HERE, AND WHAT DELIBERATELY IS NOT
// ------------------------------------------
// The iOS plugin covers two very different jobs behind one channel: the
// SURFACES the app's design is made of (context menus, alerts, action sheets,
// the Settings form, the glass chrome) and the FILE ERRANDS only the OS can
// run (put this file where the user says, give me a file to open, tell me how
// hot the machine is).
//
// Only the second half is implemented here. The first half is not missing by
// omission — the app already draws every one of those surfaces in Flutter for
// any host that is not iOS, in its own design system, and those fallbacks are
// what makes the desktop build the SAME app rather than a GTK lookalike of
// it. Replacing them with GtkMenu would make the two builds diverge, which is
// the one thing this port is not allowed to do.
//
// The exception is `importChoice`. That question has no Flutter fallback (see
// AppState._importMesh: off iOS the app used to pick "convert" for the user
// without asking), it is asked from a place with no BuildContext, and it must
// be answered before a conversion that can take half a minute starts. A modal
// the platform owns is the honest shape for it.
#include "include/native_menu/native_menu_plugin.h"

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>
#include <unistd.h>  // sysconf, for the page size the footprint is counted in

#include <cstdio>
#include <cstring>

#define NATIVE_MENU_CHANNEL "prototype/native_menu"

G_DECLARE_FINAL_TYPE(NativeMenuPlugin, native_menu_plugin, NATIVE, MENU_PLUGIN,
                     GObject)

struct _NativeMenuPlugin {
  GObject parent_instance;
  FlPluginRegistrar* registrar;  // weak; the registrar outlives the plugin
  FlMethodChannel* channel;
};

G_DEFINE_TYPE(NativeMenuPlugin, native_menu_plugin, G_TYPE_OBJECT)

// ---------------------------------------------------------------------------
// small helpers
// ---------------------------------------------------------------------------

// The window our dialogs are modal to. A dialog with no parent is a separate
// entry in the task switcher that can end up BEHIND the app, which reads as a
// frozen app rather than as a question.
static GtkWindow* plugin_window(NativeMenuPlugin* self) {
  if (self->registrar == nullptr) return nullptr;
  FlView* view = fl_plugin_registrar_get_view(self->registrar);
  if (view == nullptr) return nullptr;
  GtkWidget* toplevel = gtk_widget_get_toplevel(GTK_WIDGET(view));
  if (toplevel == nullptr || !GTK_IS_WINDOW(toplevel)) return nullptr;
  return GTK_WINDOW(toplevel);
}

static const gchar* arg_string(FlValue* args, const char* key) {
  if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
    return nullptr;
  }
  FlValue* v = fl_value_lookup_string(args, key);
  if (v == nullptr || fl_value_get_type(v) != FL_VALUE_TYPE_STRING) {
    return nullptr;
  }
  return fl_value_get_string(v);
}

static FlMethodResponse* respond_bool(bool value) {
  g_autoptr(FlValue) result = fl_value_new_bool(value);
  return FL_METHOD_RESPONSE(fl_method_success_response_new(result));
}

static FlMethodResponse* respond_null() {
  return FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
}

// Copies [from] to [to], byte for byte. Used by Save a copy: EXPORT means the
// document stays where it is and a copy lands where the user pointed, which is
// exactly what the iOS Files exporter does.
static bool copy_file(const char* from, const char* to, GError** error) {
  g_autoptr(GFile) src = g_file_new_for_path(from);
  g_autoptr(GFile) dst = g_file_new_for_path(to);
  return g_file_copy(src, dst, G_FILE_COPY_OVERWRITE, nullptr, nullptr, nullptr,
                     error);
}

// ---------------------------------------------------------------------------
// export — "Save a copy"
// ---------------------------------------------------------------------------
static FlMethodResponse* handle_export(NativeMenuPlugin* self, FlValue* args) {
  const gchar* path = arg_string(args, "path");
  if (path == nullptr || !g_file_test(path, G_FILE_TEST_EXISTS)) {
    // Same contract as iOS: false means "nothing was presented", and the Dart
    // side logs REFUSED rather than pretending a file went somewhere.
    return respond_bool(false);
  }

  g_autofree gchar* base = g_path_get_basename(path);
  // The title comes from Dart, where the app's ARB catalogue is. The app is
  // natively German; a dialog that says "Save a copy" over a ribbon that says
  // "Exportieren" is the seam the user sees. The English here is a fallback
  // for an older app build, not the intended string. GTK localises the two
  // BUTTONS itself from the stock ids.
  const gchar* save_title = arg_string(args, "saveTitle");
  GtkWidget* dialog = gtk_file_chooser_dialog_new(
      save_title != nullptr ? save_title : "Save a copy", plugin_window(self),
      GTK_FILE_CHOOSER_ACTION_SAVE, "_Cancel", GTK_RESPONSE_CANCEL, "_Save",
      GTK_RESPONSE_ACCEPT, nullptr);
  gtk_file_chooser_set_do_overwrite_confirmation(GTK_FILE_CHOOSER(dialog), TRUE);
  gtk_file_chooser_set_current_name(GTK_FILE_CHOOSER(dialog), base);
  // ~/Documents when the desktop has one, the home directory otherwise —
  // never the process's working directory, which is what GTK defaults to and
  // is a meaningless place: an app started from a menu inherits whatever the
  // session manager was in, and one started from a terminal offers to save
  // into the source tree. `g_get_user_special_dir` returns null on a system
  // without xdg-user-dirs, which is common enough to be worth handling rather
  // than discovering.
  const gchar* start = g_get_user_special_dir(G_USER_DIRECTORY_DOCUMENTS);
  if (start == nullptr) start = g_get_home_dir();
  if (start != nullptr) {
    gtk_file_chooser_set_current_folder(GTK_FILE_CHOOSER(dialog), start);
  }

  bool ok = false;
  if (gtk_dialog_run(GTK_DIALOG(dialog)) == GTK_RESPONSE_ACCEPT) {
    g_autofree gchar* target =
        gtk_file_chooser_get_filename(GTK_FILE_CHOOSER(dialog));
    if (target != nullptr) {
      g_autoptr(GError) error = nullptr;
      ok = copy_file(path, target, &error);
      if (!ok && error != nullptr) {
        g_warning("native_menu: export failed: %s", error->message);
      }
    }
  }
  gtk_widget_destroy(dialog);
  return respond_bool(ok);
}

// ---------------------------------------------------------------------------
// share — "Open with…"
// ---------------------------------------------------------------------------
//
// There is no share sheet on a Linux desktop, and inventing one would be a
// worse answer than the true one: what the user wants from Share is the file
// in another program. `g_app_info_launch_default_for_uri` is the desktop's own
// verb for that, and the portal (xdg-desktop-portal) picks it up inside a
// sandbox. When nothing is registered for the type we say so by returning
// false, which is the same "nothing was presented" the iOS side returns.
static FlMethodResponse* handle_share(NativeMenuPlugin* self, FlValue* args) {
  const gchar* path = arg_string(args, "path");
  if (path == nullptr || !g_file_test(path, G_FILE_TEST_EXISTS)) {
    return respond_bool(false);
  }
  g_autoptr(GFile) file = g_file_new_for_path(path);
  g_autofree gchar* uri = g_file_get_uri(file);
  g_autoptr(GError) error = nullptr;
  gboolean ok = g_app_info_launch_default_for_uri(uri, nullptr, &error);
  if (!ok) {
    // Nothing handles a .ptp or a .step on a bare desktop. Falling back to the
    // exporter keeps Share useful instead of silently doing nothing — the user
    // asked to get the file OUT of the app, and this is the other way to.
    if (error != nullptr) {
      g_message("native_menu: no handler for %s (%s) — offering Save a copy",
                uri, error->message);
    }
    return handle_export(self, args);
  }
  return respond_bool(true);
}

// ---------------------------------------------------------------------------
// openInPlace
// ---------------------------------------------------------------------------
//
// On iOS a path is not a durable handle and a security-scoped bookmark is; on
// Linux the path IS the durable handle, so the bookmark we hand back is the
// path itself. That keeps DocRef's contract intact — something opaque that
// resolves to a current path on a later launch — without pretending the two
// platforms have the same file model.
static FlMethodResponse* handle_open_in_place(NativeMenuPlugin* self,
                                              FlValue* args) {
  // Title and filter names from Dart — see handle_export for why.
  const gchar* open_title = arg_string(args, "title");
  GtkWidget* dialog = gtk_file_chooser_dialog_new(
      open_title != nullptr ? open_title : "Open", plugin_window(self),
      GTK_FILE_CHOOSER_ACTION_OPEN, "_Cancel", GTK_RESPONSE_CANCEL, "_Open",
      GTK_RESPONSE_ACCEPT, nullptr);

  // One filter listing every extension the app can open, plus All files. The
  // extensions arrive from Dart (kOpenableExtensions) so this can never offer
  // a kind Open would then refuse.
  FlValue* exts = args != nullptr &&
                          fl_value_get_type(args) == FL_VALUE_TYPE_MAP
                      ? fl_value_lookup_string(args, "extensions")
                      : nullptr;
  if (exts != nullptr && fl_value_get_type(exts) == FL_VALUE_TYPE_LIST &&
      fl_value_get_length(exts) > 0) {
    const gchar* known_name = arg_string(args, "knownFilterName");
    GtkFileFilter* known = gtk_file_filter_new();
    gtk_file_filter_set_name(
        known, known_name != nullptr ? known_name
                                     : "Documents this app can open");
    for (size_t i = 0; i < fl_value_get_length(exts); i++) {
      FlValue* e = fl_value_get_list_value(exts, i);
      if (fl_value_get_type(e) != FL_VALUE_TYPE_STRING) continue;
      // Case-insensitive: a file saved by another tool as .STEP is the same
      // file, and a filter that hides it looks like a missing document.
      g_autofree gchar* lower = g_ascii_strdown(fl_value_get_string(e), -1);
      g_autofree gchar* upper = g_ascii_strup(fl_value_get_string(e), -1);
      g_autofree gchar* pat_lower = g_strdup_printf("*.%s", lower);
      g_autofree gchar* pat_upper = g_strdup_printf("*.%s", upper);
      gtk_file_filter_add_pattern(known, pat_lower);
      gtk_file_filter_add_pattern(known, pat_upper);
    }
    gtk_file_chooser_add_filter(GTK_FILE_CHOOSER(dialog), known);
  }
  const gchar* all_name = arg_string(args, "allFilesFilterName");
  GtkFileFilter* all = gtk_file_filter_new();
  gtk_file_filter_set_name(all, all_name != nullptr ? all_name : "All files");
  gtk_file_filter_add_pattern(all, "*");
  gtk_file_chooser_add_filter(GTK_FILE_CHOOSER(dialog), all);

  // Same starting point as Save, and for the same reason. GTK remembers where
  // the user last was within a session, so this only decides the first Open.
  const gchar* start = g_get_user_special_dir(G_USER_DIRECTORY_DOCUMENTS);
  if (start == nullptr) start = g_get_home_dir();
  if (start != nullptr) {
    gtk_file_chooser_set_current_folder(GTK_FILE_CHOOSER(dialog), start);
  }

  g_autofree gchar* chosen = nullptr;
  if (gtk_dialog_run(GTK_DIALOG(dialog)) == GTK_RESPONSE_ACCEPT) {
    chosen = gtk_file_chooser_get_filename(GTK_FILE_CHOOSER(dialog));
  }
  gtk_widget_destroy(dialog);

  if (chosen == nullptr) return respond_null();
  g_autoptr(FlValue) result = fl_value_new_map();
  fl_value_set_string_take(result, "path", fl_value_new_string(chosen));
  fl_value_set_string_take(result, "bookmark", fl_value_new_string(chosen));
  return FL_METHOD_RESPONSE(fl_method_success_response_new(result));
}

// The bookmark is the path (see above), so resolving one is asking whether the
// file is still there. Null when it is not — which the app reads as "could not
// re-open", leaving the gallery entry alone rather than forgetting it.
static FlMethodResponse* handle_resolve_bookmark(FlValue* args) {
  const gchar* bookmark = arg_string(args, "bookmark");
  if (bookmark == nullptr || !g_file_test(bookmark, G_FILE_TEST_EXISTS)) {
    return respond_null();
  }
  g_autoptr(FlValue) result = fl_value_new_map();
  fl_value_set_string_take(result, "path", fl_value_new_string(bookmark));
  fl_value_set_string_take(result, "bookmark", fl_value_new_string(bookmark));
  return FL_METHOD_RESPONSE(fl_method_success_response_new(result));
}

// ---------------------------------------------------------------------------
// importChoice
// ---------------------------------------------------------------------------
static FlMethodResponse* handle_import_choice(NativeMenuPlugin* self,
                                              FlValue* args) {
  const gchar* title = arg_string(args, "title");
  const gchar* message = arg_string(args, "message");
  const gchar* convert_label = arg_string(args, "convertLabel");
  const gchar* convert_detail = arg_string(args, "convertDetail");
  const gchar* faceted_label = arg_string(args, "facetedLabel");
  const gchar* faceted_detail = arg_string(args, "facetedDetail");
  const gchar* cancel_label = arg_string(args, "cancelLabel");

  GtkWidget* dialog = gtk_message_dialog_new(
      plugin_window(self), GTK_DIALOG_MODAL, GTK_MESSAGE_QUESTION,
      GTK_BUTTONS_NONE, "%s", title != nullptr ? title : "Import");

  // The two DETAIL strings carry the whole decision (editable CAD vs. every
  // triangle kept), so they belong in the body rather than being dropped —
  // this dialog has no room for a subtitle under each button the way UIKit's
  // does.
  GString* body = g_string_new(nullptr);
  if (message != nullptr && *message != '\0') g_string_append(body, message);
  if (convert_label != nullptr && convert_detail != nullptr) {
    if (body->len > 0) g_string_append(body, "\n\n");
    g_string_append_printf(body, "%s — %s", convert_label, convert_detail);
  }
  if (faceted_detail != nullptr && *faceted_detail != '\0') {
    if (body->len > 0) g_string_append(body, "\n\n");
    if (faceted_label != nullptr) {
      g_string_append_printf(body, "%s — %s", faceted_label, faceted_detail);
    } else {
      // No faceted button: the detail is then the REASON there is none.
      g_string_append(body, faceted_detail);
    }
  }
  if (body->len > 0) {
    gtk_message_dialog_format_secondary_text(GTK_MESSAGE_DIALOG(dialog), "%s",
                                             body->str);
  }
  g_string_free(body, TRUE);

  enum { kCancel = 1, kConvert = 2, kFaceted = 3 };
  gtk_dialog_add_button(GTK_DIALOG(dialog),
                        cancel_label != nullptr ? cancel_label : "Cancel",
                        kCancel);
  if (faceted_label != nullptr && *faceted_label != '\0') {
    gtk_dialog_add_button(GTK_DIALOG(dialog), faceted_label, kFaceted);
  }
  gtk_dialog_add_button(GTK_DIALOG(dialog),
                        convert_label != nullptr ? convert_label : "Convert",
                        kConvert);
  gtk_dialog_set_default_response(GTK_DIALOG(dialog), kConvert);

  gint answer = gtk_dialog_run(GTK_DIALOG(dialog));
  gtk_widget_destroy(dialog);

  // Anything that is not one of the two choices — Escape, the window closed,
  // Cancel — is a cancellation, and the app must not import on one.
  const char* id = answer == kConvert   ? "convert"
                   : answer == kFaceted ? "faceted"
                                        : nullptr;
  if (id == nullptr) return respond_null();
  g_autoptr(FlValue) result = fl_value_new_string(id);
  return FL_METHOD_RESPONSE(fl_method_success_response_new(result));
}

// ---------------------------------------------------------------------------
// perfProbe
// ---------------------------------------------------------------------------
//
// The same keys PerfProbe.swift reports, from the places Linux keeps them.
// Anything this machine cannot answer is simply absent from the map — the
// readers all treat a missing key as "unknown", and a zero would be a lie.
static double read_first_double(const char* path, double scale) {
  FILE* f = fopen(path, "r");
  if (f == nullptr) return -1;
  double v = -1;
  if (fscanf(f, "%lf", &v) != 1) v = -1;
  fclose(f);
  return v < 0 ? -1 : v * scale;
}

static gint64 read_meminfo_kb(const char* key) {
  FILE* f = fopen("/proc/meminfo", "r");
  if (f == nullptr) return -1;
  char line[256];
  const size_t key_len = strlen(key);
  gint64 out = -1;
  while (fgets(line, sizeof(line), f) != nullptr) {
    if (strncmp(line, key, key_len) == 0) {
      long long v = 0;
      if (sscanf(line + key_len, " %lld kB", &v) == 1) out = v;
      break;
    }
  }
  fclose(f);
  return out;
}

// The hottest zone the kernel exposes, in degrees Celsius. This is the closest
// Linux gets to `ProcessInfo.thermalState`, and it is the number that decides
// whether a benchmark on this machine means anything: a laptop that has been
// path-tracing for ten minutes is not the machine the first sample came from.
static double hottest_thermal_zone_c() {
  double hottest = -1;
  for (int i = 0; i < 32; i++) {
    g_autofree gchar* path =
        g_strdup_printf("/sys/class/thermal/thermal_zone%d/temp", i);
    if (!g_file_test(path, G_FILE_TEST_EXISTS)) continue;
    const double c = read_first_double(path, 0.001);  // millidegrees
    if (c > hottest) hottest = c;
  }
  return hottest;
}

static FlMethodResponse* handle_perf_probe() {
  g_autoptr(FlValue) map = fl_value_new_map();

  // Resident set, the number that matters when a conversion is about to
  // allocate a hundred megabytes of triangles.
  long rss_pages = 0, total_pages = 0;
  FILE* statm = fopen("/proc/self/statm", "r");
  if (statm != nullptr) {
    if (fscanf(statm, "%ld %ld", &total_pages, &rss_pages) != 2) rss_pages = 0;
    fclose(statm);
  }
  if (rss_pages > 0) {
    const long page = sysconf(_SC_PAGESIZE);
    fl_value_set_string_take(map, "footprintBytes",
                             fl_value_new_int((int64_t)rss_pages * page));
  }

  const gint64 available_kb = read_meminfo_kb("MemAvailable:");
  if (available_kb > 0) {
    fl_value_set_string_take(map, "availableBytes",
                             fl_value_new_int(available_kb * 1024));
  }
  const gint64 total_kb = read_meminfo_kb("MemTotal:");
  if (total_kb > 0) {
    fl_value_set_string_take(map, "physicalBytes",
                             fl_value_new_int(total_kb * 1024));
  }

  const double celsius = hottest_thermal_zone_c();
  if (celsius > 0) {
    fl_value_set_string_take(map, "thermalCelsius", fl_value_new_float(celsius));
  }

  fl_value_set_string_take(map, "processors",
                           fl_value_new_int(g_get_num_processors()));
  fl_value_set_string_take(map, "platform", fl_value_new_string("linux"));
  return FL_METHOD_RESPONSE(fl_method_success_response_new(map));
}

// ---------------------------------------------------------------------------
// dispatch
// ---------------------------------------------------------------------------
static void method_call_cb(FlMethodChannel* channel, FlMethodCall* call,
                           gpointer user_data) {
  NativeMenuPlugin* self = NATIVE_MENU_PLUGIN(user_data);
  const gchar* method = fl_method_call_get_name(call);
  FlValue* args = fl_method_call_get_args(call);

  g_autoptr(FlMethodResponse) response = nullptr;
  if (strcmp(method, "isSupported") == 0) {
    // The MENU surfaces, which this plugin does not provide. Answering true
    // here would switch the app off its Flutter chrome and leave it with
    // nothing to draw.
    response = respond_bool(false);
  } else if (strcmp(method, "export") == 0) {
    response = handle_export(self, args);
  } else if (strcmp(method, "share") == 0) {
    response = handle_share(self, args);
  } else if (strcmp(method, "openInPlace") == 0) {
    response = handle_open_in_place(self, args);
  } else if (strcmp(method, "resolveBookmark") == 0) {
    response = handle_resolve_bookmark(args);
  } else if (strcmp(method, "releaseDocument") == 0) {
    // Nothing to release: access to a path does not expire here.
    response = respond_bool(true);
  } else if (strcmp(method, "probeContentTypes") == 0) {
    // There is no equivalent of a dynamic UTI to warn about; the chooser takes
    // glob patterns and cannot be killed by one.
    g_autoptr(FlValue) empty = fl_value_new_list();
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(empty));
  } else if (strcmp(method, "importChoice") == 0) {
    response = handle_import_choice(self, args);
  } else if (strcmp(method, "perfProbe") == 0) {
    response = handle_perf_probe();
  } else {
    // Everything else is a surface the app draws itself off iOS. Not
    // implemented is the honest answer, and the Dart side already treats it
    // as one.
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }

  g_autoptr(GError) error = nullptr;
  if (!fl_method_call_respond(call, response, &error)) {
    g_warning("native_menu: failed to respond to %s: %s", method,
              error->message);
  }
}

static void native_menu_plugin_dispose(GObject* object) {
  NativeMenuPlugin* self = NATIVE_MENU_PLUGIN(object);
  g_clear_object(&self->channel);
  self->registrar = nullptr;
  G_OBJECT_CLASS(native_menu_plugin_parent_class)->dispose(object);
}

static void native_menu_plugin_class_init(NativeMenuPluginClass* klass) {
  G_OBJECT_CLASS(klass)->dispose = native_menu_plugin_dispose;
}

static void native_menu_plugin_init(NativeMenuPlugin* self) {}

void native_menu_plugin_register_with_registrar(FlPluginRegistrar* registrar) {
  NativeMenuPlugin* plugin = NATIVE_MENU_PLUGIN(
      g_object_new(native_menu_plugin_get_type(), nullptr));
  plugin->registrar = registrar;

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  plugin->channel = fl_method_channel_new(
      fl_plugin_registrar_get_messenger(registrar), NATIVE_MENU_CHANNEL,
      FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(
      plugin->channel, method_call_cb, g_object_ref(plugin), g_object_unref);

  g_object_unref(plugin);
}
