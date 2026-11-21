/// Stride length assumed until Daniel has corrected a treadmill distance once, in meters.
const defaultStrideM = 1.0;

/// Strides outside this (meters) are a miscount or a typo, not a calibration.
const minStrideM = 0.3, maxStrideM = 2.5;

/// Distance of [steps] steps at [strideM] meters a step, in km. The default stride when it is null.
double stepDistanceKm(int steps, double? strideM) => steps * (strideM ?? defaultStrideM) / 1000;

/// The calibrated stride and how many corrections it is the average of.
typedef Stride = ({double strideM, int samples});

/// Folds one correction into the stride: Daniel typed [typedKm] for [steps] steps. The stride is the running average of every correction.
/// A correction that makes no sense (no steps, no distance, a stride outside [minStrideM]..[maxStrideM]) leaves it as it was.
Stride calibrateStride(double? currentM, int samples, int steps, double typedKm) {
  final kept = (strideM: currentM ?? defaultStrideM, samples: currentM == null ? 0 : samples);
  if (steps <= 0 || typedKm <= 0) return kept;
  final observed = typedKm * 1000 / steps;
  if (observed < minStrideM || observed > maxStrideM) return kept;
  final n = kept.samples;
  return (strideM: n == 0 ? observed : (kept.strideM * n + observed) / (n + 1), samples: n + 1);
}
