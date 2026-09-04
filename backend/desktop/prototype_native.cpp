// Prototype — the desktop kernel library's own translation unit.
//
// It holds no logic. The three C APIs come in whole from their static archives
// (see --whole-archive in CMakeLists.txt); a shared library still needs at
// least one source of its own, and this is the useful thing to put in it: a
// version string that says WHICH build a .so found on a user's disk is.
//
// Same idea as the "Prototype C-API"/"Prototype OCCT shim" markers the iOS CI
// greps for in the Runner binary — `strings libprototype_native.so | grep
// "Prototype desktop"` answers "is this the library I think it is" without a
// debugger, and a bug bundle can carry the answer.
#include <cstddef>

// KEEPING THE MARKER, in the two dialects that need saying separately.
//
// GCC and Clang need `used`: nothing references this array, and a link that
// pulled the object out of an archive would be entitled to drop it.
//
// MSVC has no equivalent and needs none. This translation unit is compiled
// straight into the DLL rather than reached through an archive, so there is no
// step at which it could be discarded — and it does not export, because the
// .def derived in backend/desktop/windows_exports.cmake names only the three
// C-API prefixes. `/INCLUDE:` is the tool if that ever changes.
#if defined(__GNUC__) || defined(__clang__)
#  define PROTOTYPE_KEEP __attribute__((used))
#else
#  define PROTOTYPE_KEEP
#endif

extern "C" {

// The marker. No visibility attribute: the version script (and on Windows the
// .def) already makes everything that is not one of the three C-API prefixes
// local, and an attribute here would only be a second answer to the same
// question.
PROTOTYPE_KEEP
const char kPrototypeDesktopKernelMarker[] =
    "Prototype desktop kernels v1"
#ifdef PROTOTYPE_NO_OCCT
    " (no OCCT)"
#endif
    ;

}  // extern "C"
