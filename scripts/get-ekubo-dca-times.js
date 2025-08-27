#!/usr/bin/env node

// -------------------------------
// Utility Functions
// -------------------------------

const DENOMINATOR_LOG_16 = Math.log(16);
const MIN_DURATION_SECONDS = 30 * 60;
const MIN_DURATION_INTERVAL_SECONDS = 16
const MAX_DURATION_SECONDS = MIN_DURATION_INTERVAL_SECONDS ** 6;
const DEFAULT_DURATION_SECONDS = 180 * 60;

/**
 * Compute the step size for a given time difference.
 * - If the difference is small (< 256), the step size is fixed at 16.
 * - Otherwise, it returns the largest power of 16 that is <= difference.
 */
function timeDifferenceToStepSize(diff) {
  if (diff < 256) return 16;
  const exponent = Math.floor(Math.log(diff) / DENOMINATOR_LOG_16);
  return 16 ** exponent;
}

/**
 * Snap a time to the nearest valid multiple of step size.
 */
function toNearestValidTime({ blockTime, time, roundUp }) {
  if (roundUp === undefined) {
    const down = toNearestValidTime({ blockTime, time, roundUp: false });
    const up = toNearestValidTime({ blockTime, time, roundUp: true });
    return Math.abs(down - time) <= Math.abs(up - time) ? down : up;
  }

  const diff = time - blockTime;

  if (diff < 256) {
    return roundUp ? Math.ceil(time / 16) * 16 : Math.floor(time / 16) * 16;
  }

  const stepSize = timeDifferenceToStepSize(diff);
  const remainder = time % stepSize;

  if (remainder === 0) return time;

  if (roundUp) {
    const nextAligned = time + (stepSize - remainder);
    return toNearestValidTime({ blockTime, time: nextAligned, roundUp: true });
  } else {
    const prevAligned = time - remainder;
    const prevStepSize = timeDifferenceToStepSize(prevAligned - blockTime);
    return prevStepSize === stepSize
      ? prevAligned
      : Math.floor(((blockTime + stepSize - 1) / prevStepSize)) * prevStepSize;
  }
}

/**
 * Generate all valid times between start and end.
 */
function getValidTimes(blockTime, startTime, endTime) {
  const validTimes = [];

  let current = toNearestValidTime({
    time: startTime,
    blockTime,
    roundUp: true,
  });

  while (current < endTime) {
    validTimes.push(current);
    current = toNearestValidTime({ time: current + 1, blockTime, roundUp: true });
  }

  return validTimes;
}

/**
 * Generate valid durations (relative to blockTime).
 */
function getDurationOptions(blockTime) {
  return getValidTimes(
    blockTime,
    blockTime + MIN_DURATION_SECONDS,
    blockTime + MAX_DURATION_SECONDS
  ).map(time => time - blockTime);
}

// -------------------------------
// CLI Runner
// -------------------------------

function main() {
  const [blockArg] = process.argv.slice(2);

  if (!blockArg) {
    console.log("Usage: node durationOptions.js <blockTime>");
    console.log("Example: node durationOptions.js 1000");
    process.exit(1);
  }

  const blockTime = Number(blockArg);

  const durationOptions = getDurationOptions(blockTime);
  console.log("Duration Options (seconds):", durationOptions);
}

// Run only if called directly
if (require.main === module) {
  main();
}
