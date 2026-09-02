#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  GtkWindow* window;
  FlView* view;
  GtkCssProvider* frame_css_provider;
  GtkWidget* maximize_button;
  GtkWidget* resize_outline;
  gboolean resize_active;
  GdkWindowEdge resize_edge;
  gint resize_start_root_x;
  gint resize_start_root_y;
  gint resize_start_x;
  gint resize_start_y;
  gint resize_start_width;
  gint resize_start_height;
  gint resize_x;
  gint resize_y;
  gint resize_width;
  gint resize_height;
  gint resize_overlay_x;
  gint resize_overlay_y;
  gdouble resize_r;
  gdouble resize_g;
  gdouble resize_b;
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

struct NativeThemeColors {
  const gchar* canvas;
  const gchar* surface;
  const gchar* base;
  const gchar* container;
  const gchar* flash;
  const gchar* flash_dark;
  const gchar* outline_variant;
  const gchar* rim;
  const gchar* accent;
  const gchar* foreground;
};

static gdouble control_foreground_r = 0.933;
static gdouble control_foreground_g = 0.918;
static gdouble control_foreground_b = 1.0;

static NativeThemeColors native_theme_colors(const gchar* name) {
  if (g_strcmp0(name, "darkRed") == 0) {
    return {"#1b0c10", "#27171b", "#a54e5f", "#6e3340", "#c95b73",
            "#81394a", "#583840", "#b96376", "#ff879a", "#eeeaff"};
  }
  if (g_strcmp0(name, "darkBlue") == 0) {
    return {"#090f1d", "#141c2b", "#4d6fa8", "#304a76", "#5c8bce",
            "#3c5d8e", "#38485f", "#638bc5", "#7faaff", "#eeeaff"};
  }
  if (g_strcmp0(name, "darkGreen") == 0) {
    return {"#0b160f", "#15241a", "#3f8b5c", "#285c3b", "#4eaa71",
            "#326e49", "#344d3c", "#58a875", "#71d998", "#eeeaff"};
  }
  if (g_strcmp0(name, "darkBlack") == 0) {
    return {"#0d0e11", "#191a1f", "#696e7a", "#444750", "#818690",
            "#555963", "#3c3f47", "#858a95", "#b5bac6", "#eeeaff"};
  }
  if (g_strcmp0(name, "darkBrown") == 0) {
    return {"#1a1008", "#281b12", "#9a6138", "#683f25", "#bd7644",
            "#7d4d2e", "#584130", "#b4794d", "#e0a264", "#eeeaff"};
  }
  if (g_strcmp0(name, "light") == 0) {
    return {"#f4f0fb", "#ffffff", "#7658bd", "#d8cbf1", "#c13e88",
            "#8c2c63", "#c9c0d4", "#7554c4", "#6244bd", "#211a2d"};
  }
  return {"#120d1c", "#1b1726", "#755da5", "#493970", "#8359ab",
          "#59407b", "#463955", "#8264b4", "#9f8aff", "#eeeaff"};
}

static void install_custom_frame_css(MyApplication* self,
                                     const NativeThemeColors& colors) {
  if (self->frame_css_provider != nullptr) {
    gtk_style_context_remove_provider_for_screen(
        gdk_screen_get_default(),
        GTK_STYLE_PROVIDER(self->frame_css_provider));
    g_clear_object(&self->frame_css_provider);
  }
  self->frame_css_provider = gtk_css_provider_new();
  g_autofree gchar* css = g_strdup_printf(
      "@define-color inventorinator_canvas %s;"
      "@define-color inventorinator_surface %s;"
      "@define-color inventorinator_base %s;"
      "@define-color inventorinator_container %s;"
      "@define-color inventorinator_flash %s;"
      "@define-color inventorinator_flash_dark %s;"
      "@define-color inventorinator_outline %s;"
      "@define-color inventorinator_rim %s;"
      "#inventorinator-frame { background: @inventorinator_canvas; border: 1px solid @inventorinator_outline; }"
      "#inventorinator-titlebar { background: @inventorinator_canvas; }"
      "#inventorinator-window-button {"
      " background-color: @inventorinator_surface;"
      " background-image: linear-gradient(to bottom right, rgba(255,255,255,0.38), alpha(@inventorinator_base,0.16));"
      " border: 1px solid @inventorinator_outline; border-radius: 10px;"
      " box-shadow: inset 0 1px rgba(255,255,255,0.46), 0 2px 7px rgba(0,0,0,0.20);"
      " margin: 5px 3px; padding: 0; color: %s; font-size: 18px; text-shadow: none;"
      "}"
      "#inventorinator-window-button:hover {"
      " background-color: @inventorinator_base;"
      " background-image: linear-gradient(to bottom right, @inventorinator_flash, @inventorinator_flash_dark);"
      " border-color: @inventorinator_rim;"
      " box-shadow: inset 0 1px alpha(@inventorinator_rim,0.42), 0 4px 12px alpha(@inventorinator_container,0.48);"
      "}"
      "#inventorinator-window-button:active {"
      " background-color: @inventorinator_container;"
      " background-image: linear-gradient(to bottom right, alpha(@inventorinator_container,0.78), alpha(@inventorinator_base,0.48));"
      " box-shadow: inset 0 2px 5px rgba(0,0,0,0.34);"
      "}"
      "#inventorinator-close-button {"
      " background-color: @inventorinator_surface;"
      " background-image: linear-gradient(to bottom right, rgba(255,255,255,0.38), alpha(@inventorinator_base,0.16));"
      " border: 1px solid @inventorinator_outline; border-radius: 10px;"
      " box-shadow: inset 0 1px rgba(255,255,255,0.46), 0 2px 7px rgba(0,0,0,0.20);"
      " margin: 5px 3px; padding: 0; color: %s; font-size: 19px; text-shadow: none;"
      "}"
      "#inventorinator-close-button:hover {"
      " background-color: @inventorinator_base;"
      " background-image: linear-gradient(to bottom right, @inventorinator_flash, @inventorinator_flash_dark);"
      " border-color: @inventorinator_rim; color: white;"
      " box-shadow: inset 0 1px alpha(@inventorinator_rim,0.42), 0 4px 12px alpha(@inventorinator_container,0.48);"
      "}"
      "#inventorinator-close-button:active {"
      " background-color: @inventorinator_container;"
      " background-image: linear-gradient(to bottom right, alpha(@inventorinator_container,0.78), alpha(@inventorinator_base,0.48));"
      " box-shadow: inset 0 2px 5px rgba(0,0,0,0.38);"
      "}",
      colors.canvas, colors.surface, colors.base, colors.container,
      colors.flash, colors.flash_dark, colors.outline_variant, colors.rim,
      colors.foreground, colors.foreground);
  gtk_css_provider_load_from_data(
      self->frame_css_provider, css, -1, nullptr);
  gtk_style_context_add_provider_for_screen(
      gdk_screen_get_default(), GTK_STYLE_PROVIDER(self->frame_css_provider),
      GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);

  GdkRGBA accent;
  if (gdk_rgba_parse(&accent, colors.accent)) {
    self->resize_r = accent.red;
    self->resize_g = accent.green;
    self->resize_b = accent.blue;
  }
  GdkRGBA foreground;
  if (gdk_rgba_parse(&foreground, colors.foreground)) {
    control_foreground_r = foreground.red;
    control_foreground_g = foreground.green;
    control_foreground_b = foreground.blue;
  }
  if (self->view != nullptr) {
    GdkRGBA background;
    if (gdk_rgba_parse(&background, colors.canvas)) {
      fl_view_set_background_color(self->view, &background);
    }
  }
}

static void theme_method_call_cb(FlMethodChannel* channel,
                                 FlMethodCall* method_call,
                                 gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  const gchar* method = fl_method_call_get_name(method_call);
  if (g_strcmp0(method, "setTheme") != 0) {
    g_autoptr(FlMethodResponse) response = FL_METHOD_RESPONSE(
        fl_method_not_implemented_response_new());
    fl_method_call_respond(method_call, response, nullptr);
    return;
  }
  const gchar* theme_name = "darkPurple";
  FlValue* args = fl_method_call_get_args(method_call);
  if (args != nullptr && fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
    FlValue* theme = fl_value_lookup_string(args, "theme");
    if (theme != nullptr && fl_value_get_type(theme) == FL_VALUE_TYPE_STRING) {
      theme_name = fl_value_get_string(theme);
    }
  }
  NativeThemeColors colors = native_theme_colors(theme_name);
  if (args != nullptr && fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
    FlValue* value = nullptr;
#define READ_THEME_COLOR(key, field)                                      \
  value = fl_value_lookup_string(args, key);                              \
  if (value != nullptr && fl_value_get_type(value) == FL_VALUE_TYPE_STRING) \
    colors.field = fl_value_get_string(value)
    READ_THEME_COLOR("canvas", canvas);
    READ_THEME_COLOR("surface", surface);
    READ_THEME_COLOR("base", base);
    READ_THEME_COLOR("container", container);
    READ_THEME_COLOR("flash", flash);
    READ_THEME_COLOR("flashDark", flash_dark);
    READ_THEME_COLOR("outlineVariant", outline_variant);
    READ_THEME_COLOR("rim", rim);
    READ_THEME_COLOR("accent", accent);
    READ_THEME_COLOR("foreground", foreground);
#undef READ_THEME_COLOR
  }
  install_custom_frame_css(self, colors);
  if (self->resize_outline != nullptr) {
    gtk_widget_queue_draw(self->resize_outline);
  }
  g_autoptr(FlMethodResponse) response =
      FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  fl_method_call_respond(method_call, response, nullptr);
}

static void minimize_window_cb(GtkButton* button, gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  gtk_window_iconify(self->window);
}

enum WindowControlIcon {
  kWindowControlMinimize = 1,
  kWindowControlMaximize = 2,
  kWindowControlRestore = 3,
  kWindowControlClose = 4,
};

static gboolean draw_window_control_icon_cb(GtkWidget* widget, cairo_t* cr,
                                            gpointer user_data) {
  GtkWidget* button = GTK_WIDGET(user_data);
  const gdouble origin_x =
      (gtk_widget_get_allocated_width(widget) - 16.0) / 2.0;
  const gdouble origin_y =
      (gtk_widget_get_allocated_height(widget) - 16.0) / 2.0;
  cairo_translate(cr, origin_x, origin_y);
  const WindowControlIcon icon = static_cast<WindowControlIcon>(
      GPOINTER_TO_INT(g_object_get_data(G_OBJECT(button),
                                       "inventorinator-control-icon")));
  const GtkStateFlags state = gtk_widget_get_state_flags(button);
  if ((state & GTK_STATE_FLAG_PRELIGHT) != 0 ||
      (state & GTK_STATE_FLAG_ACTIVE) != 0) {
    cairo_set_source_rgba(cr, 0.933, 0.918, 1.0, 1.0);
  } else {
    cairo_set_source_rgba(cr, control_foreground_r, control_foreground_g,
                          control_foreground_b, 1.0);
  }
  cairo_set_antialias(cr, CAIRO_ANTIALIAS_BEST);
  cairo_set_line_width(cr, 1.5);
  cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND);
  cairo_set_line_join(cr, CAIRO_LINE_JOIN_ROUND);

  switch (icon) {
    case kWindowControlMinimize:
      cairo_move_to(cr, 3.5, 12.5);
      cairo_line_to(cr, 12.5, 12.5);
      break;
    case kWindowControlMaximize:
      cairo_rectangle(cr, 3.5, 3.5, 9.0, 9.0);
      break;
    case kWindowControlRestore:
      cairo_rectangle(cr, 5.0, 3.5, 7.5, 7.5);
      cairo_move_to(cr, 3.5, 5.0);
      cairo_line_to(cr, 11.0, 5.0);
      cairo_line_to(cr, 11.0, 12.5);
      cairo_line_to(cr, 3.5, 12.5);
      cairo_close_path(cr);
      break;
    case kWindowControlClose:
      cairo_move_to(cr, 3.5, 3.5);
      cairo_line_to(cr, 12.5, 12.5);
      cairo_move_to(cr, 12.5, 3.5);
      cairo_line_to(cr, 3.5, 12.5);
      break;
  }
  cairo_stroke(cr);
  return TRUE;
}

static void set_window_control_icon(GtkWidget* button,
                                    WindowControlIcon icon) {
  g_object_set_data(G_OBJECT(button), "inventorinator-control-icon",
                    GINT_TO_POINTER(icon));
  GtkWidget* drawing = gtk_bin_get_child(GTK_BIN(button));
  if (drawing != nullptr) {
    gtk_widget_queue_draw(drawing);
  }
}

static void toggle_maximize(MyApplication* self) {
  if (gtk_window_is_maximized(self->window)) {
    gtk_window_unmaximize(self->window);
    if (self->maximize_button != nullptr) {
      set_window_control_icon(self->maximize_button, kWindowControlMaximize);
    }
  } else {
    gtk_window_maximize(self->window);
    if (self->maximize_button != nullptr) {
      set_window_control_icon(self->maximize_button, kWindowControlRestore);
    }
  }
}

static void maximize_window_cb(GtkButton* button, gpointer user_data) {
  toggle_maximize(MY_APPLICATION(user_data));
}

static void close_window_cb(GtkButton* button, gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  gtk_window_close(self->window);
}

static gboolean titlebar_button_press_cb(GtkWidget* widget,
                                         GdkEventButton* event,
                                         gpointer user_data) {
  if (event->button != GDK_BUTTON_PRIMARY) {
    return FALSE;
  }
  MyApplication* self = MY_APPLICATION(user_data);
  if (event->type == GDK_2BUTTON_PRESS) {
    toggle_maximize(self);
    return TRUE;
  }
  gtk_window_begin_move_drag(self->window, event->button, event->x_root,
                             event->y_root, event->time);
  return TRUE;
}

static GtkWidget* create_window_button(WindowControlIcon icon,
                                       const gchar* tooltip,
                                       const gchar* widget_name,
                                       GCallback callback,
                                       MyApplication* self) {
  GtkWidget* button = gtk_button_new();
  GtkWidget* drawing = gtk_drawing_area_new();
  gtk_widget_set_size_request(drawing, 16, 16);
  gtk_container_add(GTK_CONTAINER(button), drawing);
  set_window_control_icon(button, icon);
  g_signal_connect(drawing, "draw", G_CALLBACK(draw_window_control_icon_cb),
                   button);
  gtk_widget_set_name(button, widget_name);
  gtk_widget_set_size_request(button, 40, 40);
  gtk_widget_set_tooltip_text(button, tooltip);
  gtk_widget_set_can_focus(button, FALSE);
  g_signal_connect(button, "clicked", callback, self);
  return button;
}

static GtkWidget* create_custom_titlebar(MyApplication* self) {
  GtkWidget* titlebar = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0);
  gtk_widget_set_name(titlebar, "inventorinator-titlebar");
  gtk_widget_set_size_request(titlebar, -1, 40);

  GtkWidget* drag_area = gtk_event_box_new();
  gtk_widget_set_hexpand(drag_area, TRUE);
  gtk_widget_add_events(drag_area, GDK_BUTTON_PRESS_MASK);
  g_signal_connect(drag_area, "button-press-event",
                   G_CALLBACK(titlebar_button_press_cb), self);
  gtk_box_pack_start(GTK_BOX(titlebar), drag_area, TRUE, TRUE, 0);

  GtkWidget* minimize = create_window_button(
      kWindowControlMinimize, "Minimize", "inventorinator-window-button",
      G_CALLBACK(minimize_window_cb), self);
  GtkWidget* maximize = create_window_button(
      kWindowControlMaximize, "Maximize or restore",
      "inventorinator-window-button",
      G_CALLBACK(maximize_window_cb), self);
  self->maximize_button = maximize;
  GtkWidget* close = create_window_button(
      kWindowControlClose, "Close", "inventorinator-close-button",
      G_CALLBACK(close_window_cb), self);
  gtk_widget_set_margin_end(close, 4);
  gtk_box_pack_start(GTK_BOX(titlebar), minimize, FALSE, FALSE, 0);
  gtk_box_pack_start(GTK_BOX(titlebar), maximize, FALSE, FALSE, 0);
  gtk_box_pack_start(GTK_BOX(titlebar), close, FALSE, FALSE, 0);
  return titlebar;
}

static gboolean draw_resize_outline_cb(GtkWidget* widget, cairo_t* cr,
                                       gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  const gdouble border_thickness = 4.0;
  cairo_set_operator(cr, CAIRO_OPERATOR_SOURCE);
  cairo_set_source_rgba(cr, 0.0, 0.0, 0.0, 0.0);
  cairo_paint(cr);
  if (!self->resize_active) {
    return TRUE;
  }
  cairo_set_operator(cr, CAIRO_OPERATOR_OVER);
  cairo_set_line_join(cr, CAIRO_LINE_JOIN_ROUND);
  cairo_rectangle(
      cr,
      self->resize_x - self->resize_overlay_x + border_thickness / 2.0,
      self->resize_y - self->resize_overlay_y + border_thickness / 2.0,
      MAX(1.0, self->resize_width - border_thickness),
      MAX(1.0, self->resize_height - border_thickness));

  // Match the floating action bars: a restrained #6f54ff halo beneath the
  // #8e75ff rim. Layered strokes keep the resize path cheap and responsive.
  cairo_set_source_rgba(cr, self->resize_r, self->resize_g, self->resize_b,
                        0.07);
  cairo_set_line_width(cr, 18.0);
  cairo_stroke_preserve(cr);
  cairo_set_source_rgba(cr, self->resize_r, self->resize_g, self->resize_b,
                        0.14);
  cairo_set_line_width(cr, 10.0);
  cairo_stroke_preserve(cr);
  cairo_set_source_rgba(cr, self->resize_r, self->resize_g, self->resize_b,
                        0.92);
  cairo_set_line_width(cr, border_thickness);
  cairo_stroke(cr);
  return TRUE;
}

static void ensure_resize_outline(MyApplication* self) {
  if (self->resize_outline != nullptr) {
    return;
  }
  self->resize_outline = gtk_window_new(GTK_WINDOW_POPUP);
  gtk_window_set_decorated(GTK_WINDOW(self->resize_outline), FALSE);
  gtk_window_set_accept_focus(GTK_WINDOW(self->resize_outline), FALSE);
  gtk_window_set_skip_taskbar_hint(GTK_WINDOW(self->resize_outline), TRUE);
  gtk_window_set_skip_pager_hint(GTK_WINDOW(self->resize_outline), TRUE);
  gtk_window_set_keep_above(GTK_WINDOW(self->resize_outline), TRUE);
  gtk_widget_set_app_paintable(self->resize_outline, TRUE);
  GdkScreen* screen = gtk_widget_get_screen(self->resize_outline);
  GdkVisual* visual = gdk_screen_get_rgba_visual(screen);
  if (visual != nullptr) {
    gtk_widget_set_visual(self->resize_outline, visual);
  }
  g_signal_connect(self->resize_outline, "draw",
                   G_CALLBACK(draw_resize_outline_cb), self);
  gtk_widget_realize(self->resize_outline);
  GdkWindow* outline_window = gtk_widget_get_window(self->resize_outline);
  if (outline_window != nullptr) {
    gdk_window_set_pass_through(outline_window, TRUE);
  }
}

static void update_resize_geometry(MyApplication* self, gint root_x,
                                   gint root_y) {
  const gint minimum_width = 760;
  const gint minimum_height = 520;
  const gint delta_x = root_x - self->resize_start_root_x;
  const gint delta_y = root_y - self->resize_start_root_y;
  gint x = self->resize_start_x;
  gint y = self->resize_start_y;
  gint width = self->resize_start_width;
  gint height = self->resize_start_height;

  switch (self->resize_edge) {
    case GDK_WINDOW_EDGE_NORTH_WEST:
    case GDK_WINDOW_EDGE_WEST:
    case GDK_WINDOW_EDGE_SOUTH_WEST:
      width = MAX(minimum_width, self->resize_start_width - delta_x);
      x = self->resize_start_x + self->resize_start_width - width;
      break;
    case GDK_WINDOW_EDGE_NORTH_EAST:
    case GDK_WINDOW_EDGE_EAST:
    case GDK_WINDOW_EDGE_SOUTH_EAST:
      width = MAX(minimum_width, self->resize_start_width + delta_x);
      break;
    default:
      break;
  }
  switch (self->resize_edge) {
    case GDK_WINDOW_EDGE_NORTH_WEST:
    case GDK_WINDOW_EDGE_NORTH:
    case GDK_WINDOW_EDGE_NORTH_EAST:
      height = MAX(minimum_height, self->resize_start_height - delta_y);
      y = self->resize_start_y + self->resize_start_height - height;
      break;
    case GDK_WINDOW_EDGE_SOUTH_WEST:
    case GDK_WINDOW_EDGE_SOUTH:
    case GDK_WINDOW_EDGE_SOUTH_EAST:
      height = MAX(minimum_height, self->resize_start_height + delta_y);
      break;
    default:
      break;
  }
  self->resize_x = x;
  self->resize_y = y;
  self->resize_width = width;
  self->resize_height = height;
  // The transparent overlay stays fixed for the entire drag. Only its Cairo
  // drawing changes, preventing the compositor from dropping a configuring
  // popup for a frame during rapid movement.
  gtk_widget_queue_draw(self->resize_outline);
}

static gboolean resize_handle_press_cb(GtkWidget* widget,
                                       GdkEventButton* event,
                                       gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  if (event->button != GDK_BUTTON_PRIMARY ||
      gtk_window_is_maximized(self->window)) {
    return FALSE;
  }
  self->resize_edge = static_cast<GdkWindowEdge>(GPOINTER_TO_INT(
      g_object_get_data(G_OBJECT(widget), "inventorinator-resize-edge")));
  self->resize_start_root_x = event->x_root;
  self->resize_start_root_y = event->y_root;
  gtk_window_get_position(self->window, &self->resize_start_x,
                          &self->resize_start_y);
  gtk_window_get_size(self->window, &self->resize_start_width,
                      &self->resize_start_height);
  ensure_resize_outline(self);
  GdkScreen* screen = gtk_widget_get_screen(GTK_WIDGET(self->window));
  gint overlay_width = self->resize_start_width;
  gint overlay_height = self->resize_start_height;
  GdkWindow* root_window = gdk_screen_get_root_window(screen);
  if (root_window != nullptr) {
    gdk_window_get_geometry(root_window, nullptr, nullptr, &overlay_width,
                            &overlay_height);
  }
  self->resize_overlay_x = 0;
  self->resize_overlay_y = 0;
  gtk_window_move(GTK_WINDOW(self->resize_outline), self->resize_overlay_x,
                  self->resize_overlay_y);
  gtk_window_resize(GTK_WINDOW(self->resize_outline), overlay_width,
                    overlay_height);
  self->resize_active = TRUE;
  update_resize_geometry(self, event->x_root, event->y_root);
  gtk_widget_show(self->resize_outline);
  return TRUE;
}

static gboolean resize_handle_motion_cb(GtkWidget* widget,
                                        GdkEventMotion* event,
                                        gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  if (!self->resize_active) {
    return FALSE;
  }
  update_resize_geometry(self, event->x_root, event->y_root);
  return TRUE;
}

static gboolean resize_handle_release_cb(GtkWidget* widget,
                                         GdkEventButton* event,
                                         gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  if (!self->resize_active || event->button != GDK_BUTTON_PRIMARY) {
    return FALSE;
  }
  self->resize_active = FALSE;
  gtk_widget_hide(self->resize_outline);
  gtk_window_move(self->window, self->resize_x, self->resize_y);
  gtk_window_resize(self->window, self->resize_width, self->resize_height);
  return TRUE;
}

static gboolean resize_handle_enter_cb(GtkWidget* widget,
                                       GdkEventCrossing* event,
                                       gpointer user_data) {
  const gchar* cursor_name = static_cast<const gchar*>(
      g_object_get_data(G_OBJECT(widget), "inventorinator-resize-cursor"));
  g_autoptr(GdkCursor) cursor = gdk_cursor_new_from_name(
      gtk_widget_get_display(widget), cursor_name);
  gdk_window_set_cursor(gtk_widget_get_window(widget), cursor);
  return FALSE;
}

static GtkWidget* create_resize_handle(MyApplication* self,
                                       GdkWindowEdge edge,
                                       const gchar* cursor_name,
                                       gint width,
                                       gint height) {
  GtkWidget* handle = gtk_event_box_new();
  gtk_widget_set_size_request(handle, width, height);
  gtk_widget_add_events(handle, GDK_BUTTON_PRESS_MASK | GDK_BUTTON_RELEASE_MASK |
                                    GDK_POINTER_MOTION_MASK |
                                    GDK_ENTER_NOTIFY_MASK);
  g_object_set_data(G_OBJECT(handle), "inventorinator-resize-edge",
                    GINT_TO_POINTER(edge));
  g_object_set_data_full(G_OBJECT(handle), "inventorinator-resize-cursor",
                         g_strdup(cursor_name), g_free);
  g_signal_connect(handle, "button-press-event",
                   G_CALLBACK(resize_handle_press_cb), self);
  g_signal_connect(handle, "motion-notify-event",
                   G_CALLBACK(resize_handle_motion_cb), self);
  g_signal_connect(handle, "button-release-event",
                   G_CALLBACK(resize_handle_release_cb), self);
  g_signal_connect(handle, "enter-notify-event",
                   G_CALLBACK(resize_handle_enter_cb), self);
  return handle;
}

static GtkWidget* create_custom_x11_frame(MyApplication* self,
                                          GtkWidget* view) {
  GtkWidget* frame = gtk_grid_new();
  gtk_widget_set_name(frame, "inventorinator-frame");

  GtkWidget* center = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
  gtk_widget_set_hexpand(center, TRUE);
  gtk_widget_set_vexpand(center, TRUE);
  gtk_box_pack_start(GTK_BOX(center), create_custom_titlebar(self), FALSE,
                     FALSE, 0);
  gtk_box_pack_start(GTK_BOX(center), view, TRUE, TRUE, 0);

  GtkWidget* north_west = create_resize_handle(
      self, GDK_WINDOW_EDGE_NORTH_WEST, "nwse-resize", 8, 8);
  GtkWidget* north = create_resize_handle(
      self, GDK_WINDOW_EDGE_NORTH, "ns-resize", -1, 8);
  GtkWidget* north_east = create_resize_handle(
      self, GDK_WINDOW_EDGE_NORTH_EAST, "nesw-resize", 8, 8);
  GtkWidget* west = create_resize_handle(
      self, GDK_WINDOW_EDGE_WEST, "ew-resize", 8, -1);
  GtkWidget* east = create_resize_handle(
      self, GDK_WINDOW_EDGE_EAST, "ew-resize", 8, -1);
  GtkWidget* south_west = create_resize_handle(
      self, GDK_WINDOW_EDGE_SOUTH_WEST, "nesw-resize", 8, 8);
  GtkWidget* south = create_resize_handle(
      self, GDK_WINDOW_EDGE_SOUTH, "ns-resize", -1, 8);
  GtkWidget* south_east = create_resize_handle(
      self, GDK_WINDOW_EDGE_SOUTH_EAST, "nwse-resize", 8, 8);

  gtk_widget_set_hexpand(north, TRUE);
  gtk_widget_set_hexpand(south, TRUE);
  gtk_widget_set_vexpand(west, TRUE);
  gtk_widget_set_vexpand(east, TRUE);
  gtk_grid_attach(GTK_GRID(frame), north_west, 0, 0, 1, 1);
  gtk_grid_attach(GTK_GRID(frame), north, 1, 0, 1, 1);
  gtk_grid_attach(GTK_GRID(frame), north_east, 2, 0, 1, 1);
  gtk_grid_attach(GTK_GRID(frame), west, 0, 1, 1, 1);
  gtk_grid_attach(GTK_GRID(frame), center, 1, 1, 1, 1);
  gtk_grid_attach(GTK_GRID(frame), east, 2, 1, 1, 1);
  gtk_grid_attach(GTK_GRID(frame), south_west, 0, 2, 1, 1);
  gtk_grid_attach(GTK_GRID(frame), south, 1, 2, 1, 1);
  gtk_grid_attach(GTK_GRID(frame), south_east, 2, 2, 1, 1);
  return frame;
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
  self->window = window;

  // Use a header bar when running in GNOME as this is the common style used
  // by applications and is the setup most users will be using (e.g. Ubuntu
  // desktop).
  // If running on X and not using GNOME then just use a traditional title bar
  // in case the window manager does more exotic layout, e.g. tiling.
  // If running on Wayland assume the header bar will work (may need changing
  // if future cases occur).
  gboolean use_header_bar = TRUE;
  gboolean use_custom_x11_frame = FALSE;
#ifdef GDK_WINDOWING_X11
  GdkScreen* screen = gtk_window_get_screen(window);
  if (GDK_IS_X11_SCREEN(screen)) {
    use_header_bar = FALSE;
    use_custom_x11_frame = TRUE;
  }
#endif
  if (use_custom_x11_frame) {
    gtk_window_set_decorated(window, FALSE);
    install_custom_frame_css(self, native_theme_colors("darkPurple"));
  } else if (use_header_bar) {
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
  // Use Flutter's current Linux renderer on both GTK backends. GTK selects
  // X11 or Wayland from the user's desktop session at runtime.
  fl_dart_project_set_enable_impeller(project, TRUE);
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  self->view = view;
  FlBinaryMessenger* messenger =
      fl_engine_get_binary_messenger(fl_view_get_engine(view));
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) theme_channel = fl_method_channel_new(
      messenger, "media.everlasting.inventorinator/theme",
      FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(
      theme_channel, theme_method_call_cb, self, nullptr);
  GdkRGBA background_color;
  // Match the native render surface to the Flutter application background.
  gdk_rgba_parse(&background_color, "#120d1c");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  if (use_custom_x11_frame) {
    GtkWidget* frame = create_custom_x11_frame(self, GTK_WIDGET(view));
    gtk_widget_show_all(frame);
    gtk_container_add(GTK_CONTAINER(window), frame);
  } else {
    gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));
  }

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
  if (self->resize_outline != nullptr) {
    gtk_widget_destroy(self->resize_outline);
    self->resize_outline = nullptr;
  }
  if (self->frame_css_provider != nullptr) {
    gtk_style_context_remove_provider_for_screen(
        gdk_screen_get_default(),
        GTK_STYLE_PROVIDER(self->frame_css_provider));
    g_clear_object(&self->frame_css_provider);
  }
  self->view = nullptr;
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

static void my_application_init(MyApplication* self) {
  self->resize_r = 0.624;
  self->resize_g = 0.541;
  self->resize_b = 1.0;
}

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
