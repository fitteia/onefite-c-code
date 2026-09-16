#include <stdio.h>
#include <stdlib.h>
#include "Florence_c.h"

/* One (FREQ, FLAG) combination per process invocation - deliberately, so the
 * legacy count-based cache in the OLD FlorenceN/FlorenceN4LS/Florence4 is
 * exercised under its own intended calling convention (index 0 immediately
 * followed by 1,2,3,4 for the SAME evaluation point, with the process's
 * static counters starting fresh at zero) rather than being tripped by an
 * outer loop that changes FREQ/FLAG between evaluations - a pattern the old
 * cache does not handle correctly (see the separate stale-cache
 * demonstration driver). */
int main(int argc, char **argv) {
    double SI = 0.5, GAMMAI = 2.675222e8, SPIN = 2.5, IREL = 1;
    double DELTA2 = 0.0236, TAURM = 2.88e-11, TAUVM = 2.86e-12, TAUMM = 0.0;
    double DPARAM = 0.0, EPARAM = 0.0, S4M = 0.0;
    double GXM = 2.003, GYM = 2.003, GZM = 2.003;
    double AXM = 0.0, AYM = 0.0, AZM = 0.0;
    double DM = 0.0, DDM = 0.0, CONCM = 0.001, ACQ = 1;
    double AMOLFRAM = 12, RKM = 2.767, ACONTM = 0.748, THETAM = 0, PHIM = 0;
    double FREQ = argc > 1 ? atof(argv[1]) : 1e6;
    double FLAG = argc > 2 ? atof(argv[2]) : 1.0;
    int idx;

    printf("Florence  freq=%.6e flag=%.0f -> %.15e\n", FREQ, FLAG,
        Florence(FREQ, SI, GAMMAI, SPIN, IREL, DELTA2, TAURM, TAUVM, TAUMM,
                 DPARAM, EPARAM, S4M, GXM, GYM, GZM, AXM, AYM, AZM, DM, DDM,
                 CONCM, ACQ, AMOLFRAM, RKM, ACONTM, THETAM, PHIM, FLAG));
    for (idx = 0; idx <= 4; ++idx) {
        printf("Florence4 idx=%d -> %.15e\n", idx,
            Florence4((double)idx, FREQ, SI, GAMMAI, SPIN, IREL, DELTA2, TAURM,
                      TAUVM, TAUMM, DPARAM, EPARAM, S4M, GXM, GYM, GZM, AXM, AYM,
                      AZM, DM, DDM, CONCM, ACQ, AMOLFRAM, RKM, ACONTM, THETAM,
                      PHIM, FLAG));
    }
    for (idx = 0; idx <= 4; ++idx) {
        printf("FlorenceN idx=%d -> %.15e\n", idx,
            FlorenceN((double)idx, 5.0, FREQ, SI, GAMMAI, SPIN, IREL, DELTA2,
                      TAURM, TAUVM, TAUMM, DPARAM, EPARAM, S4M, GXM, GYM, GZM,
                      AXM, AYM, AZM, DM, DDM, CONCM, ACQ, AMOLFRAM, RKM, ACONTM,
                      THETAM, PHIM, FLAG));
    }
    for (idx = 0; idx <= 4; ++idx) {
        printf("FlorenceN4LS idx=%d -> %.15e\n", idx,
            FlorenceN4LS((double)idx, 5.0, FREQ, SI, GAMMAI, SPIN, IREL, DELTA2,
                      TAURM, TAUVM, TAUMM, DPARAM, EPARAM, S4M, GXM, GYM, GZM,
                      AXM, AYM, AZM, DM, DDM, CONCM, ACQ, AMOLFRAM, RKM, ACONTM,
                      THETAM, PHIM, FLAG));
    }
    return 0;
}
