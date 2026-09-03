// Prototype — the GTK window the Flutter view lives in.
//
// Kept as close to `flutter create`'s runner as it can be, so that a future
// Flutter upgrade is a diff against a template rather than an archaeology
// exercise. Everything this app adds is marked and explained below.
#include "my_application.h"

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

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
};

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

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  // A PLAIN TITLE BAR, never a GNOME header bar.
  //
  // The template picks a header bar under GNOME because most apps put their
  // controls in one. This app's top edge is its own full-width ribbon, drawn
  // by Flutter, with its own tabs and its own material; a header bar above it
  // is a second, competing chrome that steals 46 points from the canvas and
  // makes the ribbon look like it is floating inside someone else's window.
  gtk_window_set_title(window, "Prototype");

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
