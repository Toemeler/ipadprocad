# The Win32 half of the in-repo `native_menu` plugin.
#
# It implements the FILE surfaces only — Save a copy, Open, Open with, the
# mesh-import question, and the OS performance probe. The MENU surfaces
# (context menus, alerts, action sheets, the Settings form) are deliberately
# absent: the app already draws every one of them in Flutter for any host that
# is not iOS, and those fallbacks are the app's own design system rather than
# a Win32 approximation of it. See lib/native_menu.dart (`isSupported` vs
# `hasFileSurfaces`) for which half is which and why.
cmake_minimum_required(VERSION 3.14)
set(PROJECT_NAME "native_menu")
project(${PROJECT_NAME} LANGUAGES CXX)

# This value is used when generating builds using this plugin, so it must
# not be changed.
set(PLUGIN_NAME "native_menu_plugin")

add_library(${PLUGIN_NAME} SHARED
  "native_menu_plugin.cpp"
  "grabcad_bridge.cpp"
)
apply_standard_settings(${PLUGIN_NAME})
set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)
target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_link_libraries(${PLUGIN_NAME} PRIVATE flutter flutter_wrapper_plugin)
# Shell32 for the "Open with" verb, Comctl32 for TaskDialogIndirect, Psapi for
# the process footprint the perf probe reports.
target_link_libraries(${PLUGIN_NAME} PRIVATE shell32 comctl32 psapi)

# List of absolute paths to libraries that should be bundled with the plugin.
set(native_menu_bundled_libraries
  ""
  PARENT_SCOPE
)

# Pinned Microsoft SDK. The static loader avoids another DLL to deploy;
# the installed Evergreen WebView2 runtime owns the browser/cookie store.
set(WEBVIEW2_VERSION "1.0.2903.40")
set(WEBVIEW2_ROOT "${CMAKE_CURRENT_BINARY_DIR}/webview2-${WEBVIEW2_VERSION}")
if(NOT EXISTS "${WEBVIEW2_ROOT}/build/native/include/WebView2.h")
  file(MAKE_DIRECTORY "${WEBVIEW2_ROOT}")
  file(DOWNLOAD
    "https://api.nuget.org/v3-flatcontainer/microsoft.web.webview2/${WEBVIEW2_VERSION}/microsoft.web.webview2.${WEBVIEW2_VERSION}.nupkg"
    "${WEBVIEW2_ROOT}/sdk.zip"
    EXPECTED_HASH SHA256=ef128016dd1e51c59178c827ed5b8aa3322c57afa8675d930f8109505542ad74
    TLS_VERIFY ON)
  execute_process(COMMAND "${CMAKE_COMMAND}" -E tar xf sdk.zip
    WORKING_DIRECTORY "${WEBVIEW2_ROOT}" RESULT_VARIABLE WEBVIEW2_EXTRACT_RESULT)
  if(NOT WEBVIEW2_EXTRACT_RESULT EQUAL 0)
    message(FATAL_ERROR "Unable to unpack WebView2 SDK")
  endif()
endif()
set(WEBVIEW2_ARCH "x64")
if(CMAKE_GENERATOR_PLATFORM MATCHES "[Aa][Rr][Mm]64")
  set(WEBVIEW2_ARCH "arm64")
elseif(CMAKE_SIZEOF_VOID_P EQUAL 4)
  set(WEBVIEW2_ARCH "x86")
endif()
target_include_directories(${PLUGIN_NAME} PRIVATE "${WEBVIEW2_ROOT}/build/native/include")
target_link_libraries(${PLUGIN_NAME} PRIVATE
  "${WEBVIEW2_ROOT}/build/native/${WEBVIEW2_ARCH}/WebView2LoaderStatic.lib"
  ole32 version shlwapi)
