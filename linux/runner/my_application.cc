#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

static void set_window_icon(GtkWindow* window) {
  g_autofree gchar* executable_path =
      g_file_read_link("/proc/self/exe", nullptr);
  if (executable_path == nullptr) {
    g_warning("Could not resolve the Inventorinator executable for its icon");
    return;
  }
  g_autofree gchar* executable_dir = g_path_get_dirname(executable_path);
  g_autofree gchar* icon_path =
      g_build_filename(executable_dir, "data", "app_icon.png", nullptr);
  g_autoptr(GError) icon_error = nullptr;
  g_autoptr(GdkPixbuf) app_icon = gdk_pixbuf_new_from_file_at_scale(
      icon_path, 256, 256, TRUE, &icon_error);
  if (app_icon == nullptr) {
    g_warning("Failed to load application icon: %s", icon_error->message);
    return;
  }

  // Some X11 task managers read the realized window property while others
  // resolve the GTK default. Set both so the raygun survives direct launches
  // as well as launches through the installed desktop entry.
  gtk_window_set_default_icon(app_icon);
  gtk_window_set_icon(window, app_icon);

#ifdef GDK_WINDOWING_X11
  GdkWindow* gdk_window = gtk_widget_get_window(GTK_WIDGET(window));
  if (gdk_window != nullptr && GDK_IS_X11_WINDOW(gdk_window)) {
    // A 256px CARDINAL payload can exceed the X11 request-size boundary once
    // GDK packs it. 128px is ample for process viewers and safely bounded.
    g_autoptr(GdkPixbuf) x11_icon = gdk_pixbuf_scale_simple(
        app_icon, 128, 128, GDK_INTERP_BILINEAR);
    const gint width = gdk_pixbuf_get_width(x11_icon);
    const gint height = gdk_pixbuf_get_height(x11_icon);
    const gint rowstride = gdk_pixbuf_get_rowstride(x11_icon);
    const gint channels = gdk_pixbuf_get_n_channels(x11_icon);
    const gboolean has_alpha = gdk_pixbuf_get_has_alpha(x11_icon);
    const guchar* pixels = gdk_pixbuf_get_pixels(x11_icon);
    const gsize pixel_count = static_cast<gsize>(width) * height;
    // GDK's 32-bit property API expects native unsigned-long storage on X11,
    // including on 64-bit hosts; it serializes the low 32 bits per element.
    g_autofree gulong* icon_data = g_new(gulong, pixel_count + 2);
    icon_data[0] = static_cast<gulong>(width);
    icon_data[1] = static_cast<gulong>(height);
    for (gint y = 0; y < height; ++y) {
      const guchar* row = pixels + y * rowstride;
      for (gint x = 0; x < width; ++x) {
        const guchar* pixel = row + x * channels;
        const gulong alpha = has_alpha ? pixel[3] : 0xff;
        icon_data[2 + static_cast<gsize>(y) * width + x] =
            (alpha << 24) | (static_cast<gulong>(pixel[0]) << 16) |
            (static_cast<gulong>(pixel[1]) << 8) | pixel[2];
      }
    }
    gdk_property_change(
        gdk_window, gdk_atom_intern_static_string("_NET_WM_ICON"),
        gdk_atom_intern_static_string("CARDINAL"), 32, GDK_PROP_MODE_REPLACE,
        reinterpret_cast<const guchar*>(icon_data), pixel_count + 2);
  }
#endif
}

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  GtkWidget* toplevel = gtk_widget_get_toplevel(GTK_WIDGET(view));
  gtk_widget_show(toplevel);
  set_window_icon(GTK_WINDOW(toplevel));
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  // Use a header bar when running in GNOME as this is the common style used
  // by applications and is the setup most users will be using (e.g. Ubuntu
  // desktop).
  // If running on X and not using GNOME then just use a traditional title bar
  // in case the window manager does more exotic layout, e.g. tiling.
  // If running on Wayland assume the header bar will work (may need changing
  // if future cases occur).
  gboolean use_header_bar = TRUE;
#ifdef GDK_WINDOWING_X11
  GdkScreen* screen = gtk_window_get_screen(window);
  if (GDK_IS_X11_SCREEN(screen)) {
    const gchar* wm_name = gdk_x11_screen_get_window_manager_name(screen);
    if (g_strcmp0(wm_name, "GNOME Shell") != 0) {
      use_header_bar = FALSE;
    }
  }
#endif
  if (use_header_bar) {
    GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, "Inventorinator");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "Inventorinator");
  }

  gtk_window_set_default_size(window, 1280, 720);

  set_window_icon(window);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  // Skia is measurably smoother than Impeller/OpenGL for continuous GTK
  // window resizing on Linux. Android keeps its platform renderer defaults.
  fl_dart_project_set_enable_impeller(project, FALSE);
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  // Background defaults to black, override it here if necessary, e.g. #00000000
  // for transparent.
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

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
  // Strip out the first argument as it is the binary name.
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
  // Keep the stable reverse-domain ID for desktop-file matching while giving
  // process viewers and accessibility tools the human-readable product name.
  g_set_application_name("Inventorinator");

  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_NON_UNIQUE, nullptr));
}
