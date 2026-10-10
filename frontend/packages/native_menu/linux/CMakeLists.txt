# The GTK half of the in-repo `native_menu` plugin.
#
# It implements the FILE surfaces only — Save a copy, Open, Open with, the
# mesh-import question, and the OS performance probe. The MENU surfaces
# (context menus, alerts, action sheets, the Settings form) are deliberately
# absent: the app already draws every one of them in Flutter for any host that
# is not iOS, and those fallbacks are the app's own design system rather than
# a GTK approximation of it. See lib/native_menu.dart (`isSupported` vs
# `hasFileSurfaces`) for which half is which and why.
cmake_minimum_required(VERSION 3.13)
set(PROJECT_NAME "native_menu")
project(${PROJECT_NAME} LANGUAGES CXX)

# This value is used when generating builds using this plugin, so it must
# not be changed.
set(PLUGIN_NAME "native_menu_plugin")

add_library(${PLUGIN_NAME} SHARED
  "native_menu_plugin.cc"
  "grabcad_bridge.cc"
)
apply_standard_settings(${PLUGIN_NAME})
set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)
target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_link_libraries(${PLUGIN_NAME} PRIVATE flutter)
target_link_libraries(${PLUGIN_NAME} PRIVATE PkgConfig::GTK)

# List of absolute paths to libraries that should be bundled with the plugin.
set(native_menu_bundled_libraries
  ""
  PARENT_SCOPE
)

# API headers only; dlopen makes the browser an optional runtime dependency so
# a host without WebKit can still launch and use the CAD app.
pkg_check_modules(WEBKIT REQUIRED webkit2gtk-4.1)
target_include_directories(${PLUGIN_NAME} PRIVATE ${WEBKIT_INCLUDE_DIRS})
target_compile_features(${PLUGIN_NAME} PRIVATE cxx_std_17)
set_source_files_properties("grabcad_bridge.cc" PROPERTIES
  COMPILE_OPTIONS "-Wno-deprecated-declarations")
target_link_libraries(${PLUGIN_NAME} PRIVATE ${CMAKE_DL_LIBS})
