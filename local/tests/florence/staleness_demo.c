#include <stdio.h>
#include "Florence_c.h"

/* Demonstrates the old count-based cache's staleness bug: call FlorenceN's
 * full intended sequence (index 0,1,2,3,4) for freq1, then call it again for
 * a DIFFERENT freq2 but only ask for index 0 - the "next" evaluation point's
 * first, and often only-needed, query. The old cache's invalidation
 * condition (count<1 || count>n-1) is only ever re-armed by index>=1
 * queries incrementing count past n-1; a lone index=0 query after a full
 * 0..4 sequence lands on a stale count that neither branch catches, so it
 * silently reuses freq1's old result instead of recomputing for freq2. */
int main(void) {
    double SI = 0.5, GAMMAI = 2.675222e8, SPIN = 2.5, IREL = 1;
    double DELTA2 = 0.0236, TAURM = 2.88e-11, TAUVM = 2.86e-12, TAUMM = 0.0;
    double DPARAM = 0.0, EPARAM = 0.0, S4M = 0.0;
    double GXM = 2.003, GYM = 2.003, GZM = 2.003;
    double AXM = 0.0, AYM = 0.0, AZM = 0.0;
    double DM = 0.0, DDM = 0.0, CONCM = 0.001, ACQ = 1;
    double AMOLFRAM = 12, RKM = 2.767, ACONTM = 0.748, THETAM = 0, PHIM = 0;
    double freq1 = 1e6, freq2 = 5e7, FLAG = 1.0;
    int idx;
    double truth, cached;

#define CALL(FREQ, IDX) \
    FlorenceN((double)(IDX), 5.0, (FREQ), SI, GAMMAI, SPIN, IREL, DELTA2, \
              TAURM, TAUVM, TAUMM, DPARAM, EPARAM, S4M, GXM, GYM, GZM, AXM, \
              AYM, AZM, DM, DDM, CONCM, ACQ, AMOLFRAM, RKM, ACONTM, THETAM, \
              PHIM, FLAG)

    for (idx = 0; idx <= 4; ++idx) CALL(freq1, idx); /* prime the cache for freq1 */
    cached = CALL(freq2, 0);                          /* the query under test */

    /* independent, cache-free ground truth for freq2's index 0 */
    truth = Florence(freq2, SI, GAMMAI, SPIN, IREL, DELTA2, TAURM, TAUVM,
                      TAUMM, DPARAM, EPARAM, S4M, GXM, GYM, GZM, AXM, AYM,
                      AZM, DM, DDM, CONCM, ACQ, AMOLFRAM, RKM, ACONTM, THETAM,
                      PHIM, FLAG);

    printf("FlorenceN(idx=0, freq=freq2) after priming with freq1: %.15e\n", cached);
    printf("Florence(freq=freq2) ground truth (never cached):      %.15e\n", truth);
    printf("MATCH: %s\n", cached == truth ? "yes" : "NO - stale value returned");
    return 0;
}
