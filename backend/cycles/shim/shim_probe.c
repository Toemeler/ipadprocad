/* M296 — the smallest program that uses the shim.
 *
 * SPDX-License-Identifier: Apache-2.0
 *
 * It exists to be LINKED, not run: building it in CI proves the shim's headers
 * compile, its symbols resolve against the nine Cycles archives and their
 * dependencies, and the whole set closes into an iOS executable. That is the
 * question the app cannot answer without being rebuilt.
 *
 * It calls the two entry points that need no scene, so it is also runnable on
 * a device or in the simulator to report which Cycles device came up.
 */
#include <stdio.h>

#include "cycles_shim.h"

int main(void)
{
  printf("cycles available: %d\n", cy_available());
  printf("device: %s\n", cy_device_name());
  return 0;
}
