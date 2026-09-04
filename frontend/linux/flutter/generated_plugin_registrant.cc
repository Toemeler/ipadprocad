//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <native_menu/native_menu_plugin.h>

void fl_register_plugins(FlPluginRegistry* registry) {
  g_autoptr(FlPluginRegistrar) native_menu_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "NativeMenuPlugin");
  native_menu_plugin_register_with_registrar(native_menu_registrar);
}
