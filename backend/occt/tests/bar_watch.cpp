/* Samples occt_mesh_overall() from a second thread for the whole of one
 * conversion, exactly as the busy card does, and prints what a person would
 * have seen. */
#include "occt_capi.h"
#include <atomic>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <thread>
#include <vector>
#include <string>
#include <fstream>
#include <sstream>

static bool LoadStl(const char *path, std::vector<double> &xyz,
                    std::vector<int> &tri);

int main(int argc, char **argv)
{
    if (argc < 2) { std::fprintf(stderr, "usage: barwatch mesh.stl [mode]\n"); return 2; }
    std::vector<double> xyz; std::vector<int> tri;
    if (!LoadStl(argv[1], xyz, tri)) { std::fprintf(stderr, "cannot read\n"); return 2; }
    const int mode = argc > 2 ? std::atoi(argv[2]) : 1;
    std::atomic<bool> go(true);
    std::thread watch([&]{
        const auto t0 = std::chrono::steady_clock::now();
        double shown = 0, stageStarted = 0; int lastStage = -1; int lastPct = -1;
        while (go.load()) {
            int p = 0, c = 0, st = 0, dn = 0, tt = 0;
            occt_mesh_overall(&p, &c);
            occt_mesh_progress(&st, &dn, &tt);
            const double now = std::chrono::duration<double>(
                std::chrono::steady_clock::now() - t0).count();
            if (st != lastStage) { lastStage = st; stageStarted = now; }
            double want = p / 1000.0;
            if (tt <= 0 && c > p)
                want = p / 1000.0 + (c - p) / 1000.0 *
                       (1.0 - std::exp(-(now - stageStarted) / 2.5));
            if (want > shown) shown = want < 0.999 ? want : 0.999;
            const int pct = (int)(shown * 100 + 0.5);
            if (pct != lastPct) {
                lastPct = pct;
                std::printf("  %6.2fs  %3d%%  stage %d (%s)\n", now, pct, st,
                            occt_mesh_stage_name(st));
                std::fflush(stdout);
            }
            std::this_thread::sleep_for(std::chrono::milliseconds(20));
        }
    });
    int ri[OCCT_MESH_REPORT_INTS]; double rr[OCCT_MESH_REPORT_REALS];
    occt_shape *s = occt_brep_from_mesh(xyz.data(), (int)(xyz.size()/3),
                                        tri.data(), (int)(tri.size()/3),
                                        mode, 0.002, 22.0, 200000, ri, rr);
    go.store(false); watch.join();
    std::printf("  done: %s\n", s ? "ok" : occt_last_error());
    return 0;
}

static bool LoadStl(const char *path, std::vector<double> &xyz,
                    std::vector<int> &tri)
{
    std::ifstream f(path, std::ios::binary);
    if (!f) return false;
    char hdr[80]; f.read(hdr, 80);
    unsigned n = 0; f.read((char *)&n, 4);
    if (!f) return false;
    for (unsigned i = 0; i < n; ++i) {
        float v[12]; unsigned short a;
        f.read((char *)v, 48); f.read((char *)&a, 2);
        if (!f) return i > 0;
        for (int k = 0; k < 3; ++k) {
            tri.push_back((int)(xyz.size() / 3));
            xyz.push_back(v[3 + k * 3]);
            xyz.push_back(v[4 + k * 3]);
            xyz.push_back(v[5 + k * 3]);
        }
    }
    return !tri.empty();
}
