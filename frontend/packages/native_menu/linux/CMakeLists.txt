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
