#include "bench_stats.h"

#include <algorithm>
#include <cmath>

namespace bench {

Stats summarise(std::vector<double> xs)
{
    Stats s;
    if (xs.empty())
        return s;
    std::sort(xs.begin(), xs.end());
    s.n = static_cast<int>(xs.size());
    s.min = xs.front();
    s.max = xs.back();
    for (double v : xs)
        s.total += v;
    s.mean = s.total / s.n;
    if (s.n > 1) {
        double acc = 0.0;
        for (double v : xs)
            acc += (v - s.mean) * (v - s.mean);
        s.sd = std::sqrt(acc / (s.n - 1));
    }
    s.cv = s.mean > 0.0 ? s.sd / s.mean : 0.0;

    /* Nearest-rank percentiles on the sorted sample: p95 of n observations is
     * the ceil(0.95n)-th, which for small n is simply the largest value. That
     * is honest — with n = 5 there is no 95th percentile distinct from the
     * maximum, and pretending otherwise by interpolating invents a number. */
    auto rank = [&](double q) {
        int i = static_cast<int>(std::ceil(q * s.n)) - 1;
        if (i < 0)
            i = 0;
        if (i >= s.n)
            i = s.n - 1;
        return xs[static_cast<size_t>(i)];
    };
    s.p50 = rank(0.50);
    s.p95 = rank(0.95);
    return s;
}

Fit fitPowerLaw(const std::vector<std::pair<double, double>> &points)
{
    Fit f;
    std::vector<std::pair<double, double>> pts;
    for (const auto &p : points)
        if (p.first > 0.0 && p.second > 0.0)
            pts.push_back(p);
    std::sort(pts.begin(), pts.end());
    if (pts.size() < 2)
        return f;

    const int n = static_cast<int>(pts.size());
    std::vector<double> xs, ys;
    xs.reserve(pts.size());
    ys.reserve(pts.size());
    for (const auto &p : pts) {
        xs.push_back(std::log(p.first));
        ys.push_back(std::log(p.second));
    }
    double mx = 0.0, my = 0.0;
    for (int i = 0; i < n; ++i) {
        mx += xs[i];
        my += ys[i];
    }
    mx /= n;
    my /= n;

    double sxx = 0.0, sxy = 0.0;
    for (int i = 0; i < n; ++i) {
        sxx += (xs[i] - mx) * (xs[i] - mx);
        sxy += (xs[i] - mx) * (ys[i] - my);
    }
    if (sxx <= 0.0)
        return f;

    f.ok = true;
    f.n = n;
    f.k = sxy / sxx;
    f.b = my - f.k * mx;

    double ss_res = 0.0, ss_tot = 0.0;
    for (int i = 0; i < n; ++i) {
        const double r = ys[i] - (f.k * xs[i] + f.b);
        ss_res += r * r;
        ss_tot += (ys[i] - my) * (ys[i] - my);
    }
    f.r2 = ss_tot > 0.0 ? 1.0 - ss_res / ss_tot : NAN;

    if (n > 2 && ss_res > 0.0) {
        f.have_se = true;
        f.se = std::sqrt(ss_res / (n - 2) / sxx);
        f.lo = f.k - 1.96 * f.se;
        f.hi = f.k + 1.96 * f.se;
    }
    return f;
}

bool intervalsOverlap(double a_lo, double a_hi, double b_lo, double b_hi)
{
    return a_lo <= b_hi && b_lo <= a_hi;
}

} /* namespace bench */
