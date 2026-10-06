// Prototype — the GTK window the Flutter view lives in.
//
// Kept as close to `flutter create`'s runner as it can be, so that a future
// Flutter upgrade is a diff against a template rather than an archaeology
// exercise. Everything this app adds is marked and explained below.
#include "my_application.h"

#include <cstring>

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"

// The iPad Pro 13" in landscape, in logical points. Not a round desktop number
// on purpose: every layout constant in this app was chosen against that stage,
// so a window that size is the one place the desktop build is pixel-for-pixel
// the iPad build. It is a DEFAULT — the window is freely resizable and the
// layout is responsive; it is simply where it starts.
#define PROTOTYPE_DEFAULT_WIDTH 1376
#define PROTOTYPE_DEFAULT_HEIGHT 1032

// Below this the ribbon has to wrap and the model browser has nowhere to go.
// The app still runs; it stops being the app the screenshots are of.
#define PROTOTYPE_MIN_WIDTH 1024
#define PROTOTYPE_MIN_HEIGHT 700

// The channel the app answers `willClose` on. See lib/platform/desktop_shell.dart.
#define PROTOTYPE_DESKTOP_CHANNEL "prototype/desktop"

// How long the close waits for the app to finish writing before going ahead.
// A window that cannot be closed is a worse bug than a document that was not
// saved, and this is the number that guarantees the first can never happen.
#define PROTOTYPE_CLOSE_TIMEOUT_MS 2500

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
};

// State for one window's close handshake. Lives as long as the request does.
typedef struct {
  GtkWindow* window;  // weak: NULL once the window is gone by any other route
  guint timeout_id;
  gboolean done;  // the window has been told to close; ignore the loser
} CloseRequest;

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

// F11 toggles fullscreen, which is what this app is on the device and what a
// desktop user expects of a canvas. Handled here rather than in Dart because
// the window is not Flutter's to resize: `SystemChrome.setEnabledSystemUIMode`
// is an iOS/Android call and does nothing on a GTK window, so a Dart-side
// implementation would be a shortcut that silently never fires.
static gboolean key_press_cb(GtkWidget* widget, GdkEventKey* event,
                             gpointer user_data) {
  if (event->keyval != GDK_KEY_F11) return FALSE;
  GdkWindow* gdk_window = gtk_widget_get_window(widget);
  const gboolean fullscreen =
      gdk_window != nullptr &&
      (gdk_window_get_state(gdk_window) & GDK_WINDOW_STATE_FULLSCREEN) != 0;
  if (fullscreen) {
    gtk_window_unfullscreen(GTK_WINDOW(widget));
  } else {
    gtk_window_fullscreen(GTK_WINDOW(widget));
  }
  return TRUE;  // never let F11 reach Dart as a key event as well
}

// ---------------------------------------------------------------------------
// Closing the window without losing the open document.
//
// The app writes the document it has open whenever it leaves one — Home, close
// tab, and on iOS when the system suspends it. Closing a DESKTOP window is a
// fourth way out and the only one nobody can be told about in time: GTK
// destroys the window, the engine is torn down, and the lifecycle event the
// app would have saved on (`hidden`) arrives with no time left to act on it.
// Measured, not assumed: the save started there got as far as writing the DXF
// and the process was gone before the document file was packed.
//
// So the close is BLOCKED — `delete-event` returns TRUE — the app is asked
// `willClose`, and the window is destroyed in the reply callback. The timeout
// is not optional: an app that is wedged, or a build with no handler for the
// method, must not produce a window that refuses to close.
// ---------------------------------------------------------------------------
static void close_request_finish(CloseRequest* request) {
  if (request->done) return;
  request->done = TRUE;
  if (request->timeout_id != 0) {
    g_source_remove(request->timeout_id);
    request->timeout_id = 0;
  }
  if (request->window != nullptr) {
    // The weak pointer is dropped BEFORE the destroy, or GTK clears a field of
    // a struct this function is about to free.
    GtkWindow* window = request->window;
    g_object_remove_weak_pointer(G_OBJECT(window),
                                 reinterpret_cast<gpointer*>(&request->window));
    // `delete-event` said TRUE and stopped the close, so nothing else will
    // destroy this window: it has to be done here, and exactly once.
    gtk_widget_destroy(GTK_WIDGET(window));
  }
  g_free(request);
}

static gboolean close_request_timed_out(gpointer user_data) {
  CloseRequest* request = static_cast<CloseRequest*>(user_data);
  g_warning("prototype: the app did not answer willClose in %d ms — closing",
            PROTOTYPE_CLOSE_TIMEOUT_MS);
  request->timeout_id = 0;
  close_request_finish(request);
  return G_SOURCE_REMOVE;
}

static void close_request_replied(GObject* source, GAsyncResult* result,
                                  gpointer user_data) {
  CloseRequest* request = static_cast<CloseRequest*>(user_data);
  g_autoptr(GError) error = nullptr;
  g_autoptr(FlMethodResponse) response = fl_method_channel_invoke_method_finish(
      FL_METHOD_CHANNEL(source), result, &error);
  if (response == nullptr) {
    // No handler in this build, or the engine is already going down. Either
    // way the close proceeds — this handshake buys a save, it does not gate
    // the window on one.
    g_debug("prototype: willClose was not answered (%s)",
            error != nullptr ? error->message : "no error given");
  }
  close_request_finish(request);
}

static gboolean window_delete_cb(GtkWidget* widget, GdkEvent* event,
                                 gpointer user_data) {
  FlMethodChannel* channel = FL_METHOD_CHANNEL(user_data);

  CloseRequest* request = g_new0(CloseRequest, 1);
  request->window = GTK_WINDOW(widget);
  // A weak pointer, so that a window torn down by some other route (the
  // application quitting while this request is in flight) leaves NULL here
  // rather than a pointer the timeout would then destroy a second time.
  g_object_add_weak_pointer(G_OBJECT(widget),
                            reinterpret_cast<gpointer*>(&request->window));
  request->timeout_id = g_timeout_add(PROTOTYPE_CLOSE_TIMEOUT_MS,
                                      close_request_timed_out, request);

  // Hide it now. The save takes a few milliseconds on any real document, and
  // a window that visibly lingers after the close button reads as a hang.
  gtk_widget_hide(widget);

  fl_method_channel_invoke_method(channel, "willClose", nullptr, nullptr,
                                  close_request_replied, request);
  return TRUE;  // not yet; close_request_finish does it
}

// ---------------------------------------------------------------------------
// The window's own titlebar, as on Windows.
//
// The window manager draws no caption: the window is given an EMPTY titlebar
// widget, never shown, which makes GTK draw the decoration itself (client-side)
// with nothing in the caption's place — the theme's resize edges and shadow
// stay, the title bar goes. What is left at the top is the strip Flutter draws
// (lib/widgets/window_titlebar.dart), and these are the calls its drag and its
// three buttons make, the same names flutter_window.cpp answers on Windows.
//
// A drag has to be handed to the window manager with the button press that
// started it — Wayland refuses a move without a real event serial — so the
// last press anywhere in the window is kept, by an emission hook rather than a
// handler, because the Flutter view consumes the press before it would ever
// propagate up to the window.
// ---------------------------------------------------------------------------
static GdkEvent* last_press = nullptr;

static gboolean remember_press_hook(GSignalInvocationHint* hint,
                                    guint n_param_values,
                                    const GValue* param_values,
                                    gpointer user_data) {
  if (n_param_values < 2) return TRUE;
  GdkEvent* event =
      static_cast<GdkEvent*>(g_value_get_boxed(&param_values[1]));
  if (event == nullptr || event->type != GDK_BUTTON_PRESS) return TRUE;
  if (last_press != nullptr) gdk_event_free(last_press);
  last_press = gdk_event_copy(event);
  return TRUE;  // stay installed
}

static gboolean window_is_maximized(GtkWindow* window) {
  GdkWindow* gdk_window = gtk_widget_get_window(GTK_WIDGET(window));
  return gdk_window != nullptr &&
         (gdk_window_get_state(gdk_window) & GDK_WINDOW_STATE_MAXIMIZED) != 0;
}

static void desktop_method_cb(FlMethodChannel* channel,
                              FlMethodCall* method_call, gpointer user_data) {
  GtkWindow* window = GTK_WINDOW(user_data);
  const gchar* method = fl_method_call_get_name(method_call);
  g_autoptr(FlMethodResponse) response = nullptr;

  if (strcmp(method, "minimizeWindow") == 0) {
    gtk_window_iconify(window);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (strcmp(method, "toggleMaximizeWindow") == 0) {
    if (window_is_maximized(window)) {
      gtk_window_unmaximize(window);
    } else {
      gtk_window_maximize(window);
    }
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (strcmp(method, "closeWindow") == 0) {
    // Through delete-event, so it runs the willClose handshake exactly as the
    // window manager's own close button would have.
    gtk_window_close(window);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (strcmp(method, "startDrag") == 0) {
    if (last_press != nullptr) {
      gtk_window_begin_move_drag(
          window, static_cast<gint>(last_press->button.button),
          static_cast<gint>(last_press->button.x_root),
          static_cast<gint>(last_press->button.y_root),
          last_press->button.time);
    }
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (strcmp(method, "isMaximized") == 0) {
    g_autoptr(FlValue) value = fl_value_new_bool(window_is_maximized(window));
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(value));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }
  fl_method_call_respond(method_call, response, nullptr);
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  // NO TITLE BAR AT ALL, the same as Windows.
  //
  // The template picks a header bar under GNOME because most apps put their
  // controls in one. This app's top edge is its own full-width ribbon, drawn
  // by Flutter, with its own tabs and its own material; any caption above it
  // is a second, competing chrome that steals points from the canvas and
  // makes the ribbon look like it is floating inside someone else's window.
  // An empty titlebar that is never shown leaves GTK drawing the decoration
  // itself with nothing in the caption — see desktop_method_cb for the strip
  // that stands in for it.
  gtk_window_set_title(window, "Prototype");
  gtk_window_set_titlebar(window, gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0));

  gtk_window_set_default_size(window, PROTOTYPE_DEFAULT_WIDTH,
                              PROTOTYPE_DEFAULT_HEIGHT);
  GdkGeometry geometry;
  geometry.min_width = PROTOTYPE_MIN_WIDTH;
  geometry.min_height = PROTOTYPE_MIN_HEIGHT;
  gtk_window_set_geometry_hints(window, nullptr, &geometry,
                                static_cast<GdkWindowHints>(GDK_HINT_MIN_SIZE));

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  // FLUTTER GPU, which the 3D viewport is drawn with.
  //
  // Impeller is already the renderer; this is the separate switch that lets
  // Dart reach it directly (flutter_gpu / flutter_scene). It is per-PROJECT on
  // desktop rather than per-platform, so without this line the app builds, the
  // engine starts, and `GpuView.probe()` fails at the first buffer allocation
  // — the viewport then falls back to the CPU painter and says so in the log,
  // which is the one failure mode that looks like a rendering bug rather than
  // a missing flag.
  //
  // The command line has `--enable-flutter-gpu` for `flutter run`, and a
  // RELEASE build compiles the engine's environment switches out, so a shipped
  // build has no way to get this except from here.
  fl_dart_project_set_enable_flutter_gpu(project, TRUE);

  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  // The app paints its own ground on the first frame and the window is not
  // shown until then (see first_frame_cb), so this colour is only ever seen
  // during a resize. Black would flash against the light palette; this is the
  // dark palette's shell colour, which is neutral against both.
  gdk_rgba_parse(&background_color, "#1C1C1E");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  g_signal_connect(window, "key-press-event", G_CALLBACK(key_press_cb),
                   nullptr);

  // The close handshake. The channel is owned by the window: it lives exactly
  // as long as the thing whose closing it is about.
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  FlMethodChannel* desktop_channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)),
      PROTOTYPE_DESKTOP_CHANNEL, FL_METHOD_CODEC(codec));
  g_signal_connect_data(window, "delete-event", G_CALLBACK(window_delete_cb),
                        desktop_channel, (GClosureNotify)g_object_unref,
                        static_cast<GConnectFlags>(0));

  // The other direction on the same channel: the titlebar's drag and buttons.
  fl_method_channel_set_method_call_handler(desktop_channel, desktop_method_cb,
                                            window, nullptr);
  g_signal_add_emission_hook(
      g_signal_lookup("button-press-event", GTK_TYPE_WIDGET), 0,
      remember_press_hook, nullptr, nullptr);

  // Show the window when Flutter renders.
  // Requires the view to be realized so we can start rendering.
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name. What is left is
  // handed to Dart's `main(List<String> args)`, which is how a document
  // double-clicked in the file manager reaches the app: the .desktop file
  // passes the path as %f. See DesktopLaunch in lib/platform/.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application startup.

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application shutdown.

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {}

MyApplication* my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_NON_UNIQUE, nullptr));
}
