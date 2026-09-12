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

// 首页内容实测高度 549（含上下内边距）+ 底部 chrome 154（导航栏 38 + 迷你播放器 78
// + 各处间隙）= 703，低于这个高度首页就要滚动，所以它是默认窗口高度的硬下限。
// （实测方式见 test/home_content_height_test.dart。）
constexpr int kHomeContentHeight = 704;
// 在内容下限之上再留出的呼吸余量。
constexpr int kBreathingRoom = 76;
// 桌面端默认高度 = 首页内容下限 + 呼吸余量。按「刚好装下首页且不局促」定，
// 而不是按屏幕高度的百分比——百分比在高分辨率屏上会开出一个几乎顶满整屏的窗口。
constexpr int kComfortableContentHeight = kHomeContentHeight + kBreathingRoom;
// 但小屏上不能顶满：最多占工作区高度的这个比例，其余留给桌面。
constexpr double kMaxWorkAreaFraction = 0.85;
// 屏幕实在放不下时的保底高度；再矮就交给首页自身滚动。
constexpr int kMinContentHeight = 560;
// 内容宽度下限（逻辑单位）。首页快捷功能卡片是「图标 + 标题/副标题 + 箭头」的
// 横向布局，宽度再窄副标题就会被省略号截断（最长副标题 8 个汉字，11pt 下约 88pt）。
constexpr int kMinContentWidth = 420;
// 上下留出的空隙，避免窗口贴死工作区边缘（标题栏由窗口管理器额外占用）。
constexpr int kVerticalClearance = 80;
// iPhone 17 竖屏比例：1206 x 2622 像素。只有在屏幕足够高时才会用到；
// 多数情况宽度下限先一步生效，窗口会比手机略宽一点（仍是竖屏）。
constexpr double kPortraitWidthPerHeight = 1206.0 / 2622.0;

// 宽度取 iPhone 17 的比例，但不低于 kMinContentWidth。
static int portrait_width_for(int height) {
  const int scaled_width = static_cast<int>(height * kPortraitWidthPerHeight);
  return scaled_width < kMinContentWidth ? kMinContentWidth : scaled_width;
}

// 默认高度按首页内容定（见上方常数），窗口放不下时再按显示器工作区收缩。
// gtk_window_set_default_size 收的是内容区尺寸，所以这里不需要补偿标题栏。
static void set_default_window_size(GtkWindow* window) {
  int height = kComfortableContentHeight;

  GdkDisplay* display = gtk_widget_get_display(GTK_WIDGET(window));
  if (display == nullptr) {
    display = gdk_display_get_default();
  }
  if (display != nullptr) {
    // 主显示器在 GDK 中固定为索引 0。
    GdkMonitor* monitor = gdk_display_get_monitor(display, 0);
    if (monitor != nullptr) {
      GdkRectangle workarea = {0, 0, 0, 0};
      gdk_monitor_get_workarea(monitor, &workarea);
      if (workarea.height > 0) {
        // 三重约束取最小：舒适高度 / 工作区占比上限 / 实际能放下的高度。
        const int max_height = workarea.height - kVerticalClearance;
        height = static_cast<int>(workarea.height * kMaxWorkAreaFraction);
        if (height > kComfortableContentHeight) {
          height = kComfortableContentHeight;
        }
        if (height > max_height) {
          height = max_height;
        }
      }
    }
  }

  if (height < kMinContentHeight) {
    height = kMinContentHeight;
  }

  gtk_window_set_default_size(window, portrait_width_for(height), height);
}

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

static void set_application_icon(GtkWindow* window) {
  g_autoptr(GError) error = nullptr;
  g_autofree gchar* executable_path =
      g_file_read_link("/proc/self/exe", &error);
  if (executable_path == nullptr) {
    return;
  }

  g_autofree gchar* executable_dir = g_path_get_dirname(executable_path);
  g_autofree gchar* icon_path =
      g_build_filename(executable_dir, "data", "app_icon.png", nullptr);
  gtk_window_set_icon_from_file(window, icon_path, nullptr);
  gtk_window_set_default_icon_from_file(icon_path, nullptr);
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
    gtk_header_bar_set_title(header_bar, "Koyze");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "Koyze");
  }

  set_default_window_size(window);
  set_application_icon(window);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
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
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_NON_UNIQUE, nullptr));
}
