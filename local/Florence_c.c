#include <math.h>
#include <string.h>
#include "Florence_f.h"
#include "Florence_c.h"

/* A small exact-input cache shares the five outputs across all public wrappers.
 * Unlike the historical call-count cache, changing ANY input forces evaluation.
 * Eight slots retain interleaved species/components without unbounded growth.
 * No approximate matching: optimizers must see every parameter perturbation.
 * Calls must remain serialized: the Fortran backend uses shared COMMON blocks.
 * This cache does not make that backend thread-safe.
 */
#define FLORENCE_CACHE_SIZE 8
struct florence_cache_entry {
    int valid;
    double frequency;
    double parameters[28];
    double result[10];
};
static struct florence_cache_entry florence_cache[FLORENCE_CACHE_SIZE];
static unsigned int florence_next;

static double florence_component(double frequency, const double parameters[28],
                                 double index)
{
    unsigned int i;
    int component;
    double input[28], log_frequency, result[10] = {0};
    struct florence_cache_entry *entry;

    /* Check before log10 or float-to-integer conversion. Keep the historical
     * finite selector convention: truncate 1..4, otherwise select total. */
    if (!isfinite(frequency) || frequency <= 0.0 || !isfinite(index))
        return NAN;
    for (i = 0; i < 28; ++i)
        if (!isfinite(parameters[i])) return NAN;
    component = index >= 1.0 && index < 5.0 ? (int)index : 0;
    for (i = 0; i < FLORENCE_CACHE_SIZE; ++i) {
        entry = &florence_cache[i];
        if (entry->valid && entry->frequency == frequency &&
            memcmp(entry->parameters, parameters, sizeof(entry->parameters)) == 0)
            return entry->result[component];
    }
    memcpy(input, parameters, sizeof(input));
    log_frequency = log10(frequency);
    if (parameters[27] >= 2.0 && parameters[27] < 3.0)
        modflor_(input, &log_frequency, result);
    else
        florencef77_(input, &log_frequency, result);
    /* Do not retain numerical failures. Only the first five slots are outputs
     * of the legacy backend, despite its ten-element array declaration. */
    for (i = 0; i < 5; ++i)
        if (!isfinite(result[i])) return result[component];
    entry = &florence_cache[florence_next];
    entry->frequency = frequency;
    memcpy(entry->parameters, parameters, sizeof(entry->parameters));
    memcpy(entry->result, result, sizeof(result));
    entry->valid = 1;
    florence_next = (florence_next + 1) % FLORENCE_CACHE_SIZE;
    return result[component];
}

double FlorenceN(
	  double index,
	  double n,
      double FREQ,
      double SI,
      double GAMMAI,
      double SPIN,
      double IREL,
      double DELTA2,
      double TAURM,
      double TAUVM,
      double TAUMM,
      double DPARAM,
      double EPARAM,
      double S4M,
      double GXM,
      double GYM,
      double GZM,
      double AXM,
      double AYM,
      double AZM,
      double DM,
      double DDM,
      double CONCM,
      double ACQ,
      double AMOLFRAM,
      double RKM,
      double ACONTM,
      double THETAM,
      double PHIM,
      double FLAG
)
{
    const double parameters[28] = { SI, GAMMAI, SPIN, IREL, DELTA2, TAURM, TAUVM, TAUMM, 2.0, DPARAM, EPARAM, S4M, GXM, GYM, GZM, AXM, AYM, AZM, DM, DDM, CONCM, ACQ, AMOLFRAM, RKM, ACONTM, THETAM, PHIM, FLAG };
    (void)n; /* Legacy grouping hint; cache identity now uses actual inputs. */
    return florence_component(FREQ, parameters, index);
}

double FlorenceN4LS(
	  double index,
	  double n,
      double FREQ,
      double SI,
      double GAMMAI,
      double SPIN,
      double IREL,
      double DELTA2,
      double TAURM,
      double TAUVM,
      double TAUMM,
      double DPARAM,
      double EPARAM,
      double S4M,
      double GXM,
      double GYM,
      double GZM,
      double AXM,
      double AYM,
      double AZM,
      double DM,
      double DDM,
      double CONCM,
      double ACQ,
      double AMOLFRAM,
      double RKM,
      double ACONTM,
      double THETAM,
      double PHIM,
      double FLAG
)
{
    const double parameters[28] = { SI, GAMMAI, SPIN, IREL, DELTA2, TAURM, TAUVM, TAUMM, 2.0, DPARAM, EPARAM, S4M, GXM, GYM, GZM, AXM, AYM, AZM, DM, DDM, CONCM, ACQ, AMOLFRAM, RKM, ACONTM, THETAM, PHIM, FLAG };
    (void)n; /* Legacy grouping hint; cache identity now uses actual inputs. */
    return florence_component(FREQ, parameters, index);
}

double Florence(
      double FREQ,
      double SI,
      double GAMMAI,
      double SPIN,
      double IREL,
      double DELTA2,
      double TAURM,
      double TAUVM,
      double TAUMM,
      double DPARAM,
      double EPARAM,
      double S4M,
      double GXM,
      double GYM,
      double GZM,
      double AXM,
      double AYM,
      double AZM,
      double DM,
      double DDM,
      double CONCM,
      double ACQ,
      double AMOLFRAM,
      double RKM,
      double ACONTM,
      double THETAM,
      double PHIM,
      double FLAG
)
{
    const double parameters[28] = { SI, GAMMAI, SPIN, IREL, DELTA2, TAURM, TAUVM, TAUMM, 2.0, DPARAM, EPARAM, S4M, GXM, GYM, GZM, AXM, AYM, AZM, DM, DDM, CONCM, ACQ, AMOLFRAM, RKM, ACONTM, THETAM, PHIM, FLAG };
    return florence_component(FREQ, parameters, 0.0);
}

double Florence4(
	  double index,
      double FREQ,
      double SI,
      double GAMMAI,
      double SPIN,
      double IREL,
      double DELTA2,
      double TAURM,
      double TAUVM,
      double TAUMM,
      double DPARAM,
      double EPARAM,
      double S4M,
      double GXM,
      double GYM,
      double GZM,
      double AXM,
      double AYM,
      double AZM,
      double DM,
      double DDM,
      double CONCM,
      double ACQ,
      double AMOLFRAM,
      double RKM,
      double ACONTM,
      double THETAM,
      double PHIM,
      double FLAG
)
{
    const double parameters[28] = { SI, GAMMAI, SPIN, IREL, DELTA2, TAURM, TAUVM, TAUMM, 2.0, DPARAM, EPARAM, S4M, GXM, GYM, GZM, AXM, AYM, AZM, DM, DDM, CONCM, ACQ, AMOLFRAM, RKM, ACONTM, THETAM, PHIM, FLAG };
    return florence_component(FREQ, parameters, index);
}
