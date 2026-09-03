/* Prototype — does the desktop kernel library actually answer?
 *
 * dlopen + dlsym, exactly as frontend/lib/ffi/native_lib.dart does it, then
 * one call into each kernel. Run by tools/desktop/build_native.sh and by the
 * Linux CI job straight after the link, because everything this catches is
 * invisible at link time: an archive that contributed no objects, a version
 * script that hid what it should have exported, a forgotten --whole-archive.
 * All three link cleanly and produce a library the app reports as missing.
 *
 * Prints one verdict line. The caller greps for it rather than trusting the
 * exit code — same discipline as the OCCT and QCAD smokes in the iOS CI, and
 * for the same reason: a process that dies inside a kernel has an exit code
 * that says nothing about how far it got.
 */
#include <stdio.h>
#include <string.h>

/* The two loaders, behind one pair of names. Dart's own FFI does the same
 * thing one layer up (DynamicLibrary.open), so keeping the smoke on the
 * platform's real loader is what makes it the same test on both. */
#if defined(_WIN32)
#include <windows.h>
typedef HMODULE lib_t;
#define LIB_OPEN(p) LoadLibraryA(p)
#define LIB_SYM(h, s) ((void*)GetProcAddress((h), (s)))
#define LIB_DEFAULT "prototype_native.dll"
static const char* lib_error(void) {
  /* Good enough for a build gate: the code, not a localised sentence. */
  static char buf[64];
  snprintf(buf, sizeof buf, "GetLastError=%lu", (unsigned long)GetLastError());
  return buf;
}
#else
#include <dlfcn.h>
typedef void* lib_t;
#define LIB_OPEN(p) dlopen((p), RTLD_NOW | RTLD_LOCAL)
#define LIB_SYM(h, s) dlsym((h), (s))
#define LIB_DEFAULT "./libprototype_native.so"
static const char* lib_error(void) { return dlerror(); }
#endif

static lib_t lib;
static int failures;

static void* need(const char* symbol) {
  void* p = LIB_SYM(lib, symbol);
  if (p == NULL) {
    printf("  MISSING %s\n", symbol);
    failures++;
  }
  return p;
}

int main(int argc, char** argv) {
  const char* path = argc > 1 ? argv[1] : LIB_DEFAULT;
  lib = LIB_OPEN(path);
  if (lib == NULL) {
    printf("NATIVE SMOKE: FAIL (open %s: %s)\n", path, lib_error());
    return 1;
  }

  /* ---- QCAD: version, a document, a line, and the line back out ---- */
  void (*qcad_init)(void) = (void (*)(void))need("qcad_init");
  const char* (*qcad_version)(void) = (const char* (*)(void))need("qcad_version");
  void* (*doc_new)(void) = (void* (*)(void))need("qcad_document_new");
  void (*doc_free)(void*) = (void (*)(void*))need("qcad_document_free");
  int (*add_line)(void*, double, double, double, double) =
      (int (*)(void*, double, double, double, double))need("qcad_add_line");
  int (*count)(void*) = (int (*)(void*))need("qcad_entity_count");

  if (failures == 0) {
    qcad_init();
    printf("  qcad_version: %s\n", qcad_version());
    void* doc = doc_new();
    if (doc == NULL) {
      printf("  qcad_document_new returned NULL\n");
      failures++;
    } else {
      add_line(doc, 0, 0, 10, 10);
      const int n = count(doc);
      printf("  qcad entities after one line: %d\n", n);
      if (n != 1) failures++;
      doc_free(doc);
    }
  }

  /* ---- libslvs: the shim's own version ---- */
  int (*slvs_shim_version)(void) = (int (*)(void))need("slvs_shim_version");
  if (slvs_shim_version != NULL) {
    const int v = slvs_shim_version();
    printf("  slvs_shim_version: %d\n", v);
    if (v <= 0) failures++;
  }

  /* ---- OCCT: the shim's version, and a real solid ---- */
  void* occt_shim = dlsym(lib, "occt_shim_version");
  if (occt_shim == NULL) {
    /* A deliberate -DPROTOTYPE_WITH_OCCT=OFF build. Reported, never silent:
     * "no 3D kernel" has to be a thing you can read, not a thing you infer. */
    printf("  occt: NOT IN THIS BUILD\n");
  } else {
    int (*shim_version)(void) = (int (*)(void))occt_shim;
    const char* (*occt_version)(void) =
        (const char* (*)(void))need("occt_version");
    void* (*make_box)(double, double, double) =
        (void* (*)(double, double, double))need("occt_make_box");
    void (*free_shape)(void*) = (void (*)(void*))need("occt_free_shape");
    double (*volume)(void*) = (double (*)(void*))need("occt_shape_volume");
    printf("  occt_shim_version: %d\n", shim_version());
    if (occt_version != NULL) printf("  occt_version: %s\n", occt_version());
    if (make_box != NULL && volume != NULL && free_shape != NULL) {
      void* box = make_box(2, 3, 4);
      if (box == NULL) {
        printf("  occt_make_box returned NULL\n");
        failures++;
      } else {
        const double v = volume(box);
        printf("  occt box 2x3x4 volume: %g (expected 24)\n", v);
        /* Loose on purpose: this checks that a real B-Rep was built and
         * measured, not OCCT's accuracy, which its own suite owns. */
        if (v < 23.9 || v > 24.1) failures++;
        free_shape(box);
      }
    }
  }

  printf(failures == 0 ? "NATIVE SMOKE: PASS\n"
                       : "NATIVE SMOKE: FAIL (%d)\n",
         failures);
  return failures == 0 ? 0 : 1;
}
