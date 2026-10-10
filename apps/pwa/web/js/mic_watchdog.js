// CPU watchdog for the call microphone's audio graph (see mic_processor.js).
//
// RNNoise runs on the audio thread. On a phone that can't keep up, the audio thread misses its
// deadlines and the call turns choppy — worse than the background noise it was removing. This
// watches the AudioContext and calls back when overload is sustained, so mic_processor.js can
// bypass RNNoise and fall back to the browser's own noise suppression.
//
// Two signals, same policy (N consecutive bad one-second windows after a warm-up):
//   - AudioContext.renderCapacity (Chrome/Edge): reports real underruns and load directly.
//   - Clock lag (everywhere else, e.g. Safari/Firefox): an overloaded audio thread falls behind,
//     so ctx.currentTime advances slower than wall-clock time.
// A window is skipped while the context isn't running or during warm-up (WASM compile and the
// first blocks are always slower), and a good window resets the count, so a brief spike — a
// notification, a screen rotation — never trips it.

window.lynkMicWatchdog = (function () {
  const DEFAULTS = {
    warmupMs: 3000,        // ignore the start: compiling the model and the first blocks are slow
    intervalMs: 1000,      // window length
    strikes: 4,            // consecutive bad windows before giving up on the neural filter
    maxUnderrunRatio: 0.05, // renderCapacity: >5% of render blocks missed in a window = audibly choppy
    maxAverageLoad: 0.95,  // renderCapacity: audio thread essentially saturated
    minClockRatio: 0.85,   // clock fallback: audio time advanced < 85% of real time
  };

  // Counts consecutive bad windows. record(bad) returns true once the limit is reached.
  function createStrikeCounter(limit) {
    let count = 0;
    return {
      record(isBad) {
        count = isBad ? count + 1 : 0;
        return count >= limit;
      },
      reset() { count = 0; },
    };
  }

  function isRenderCapacityBad(event, o) {
    return event.underrunRatio > o.maxUnderrunRatio || event.averageLoad > o.maxAverageLoad;
  }

  function isClockStarved(audioDeltaSec, wallDeltaSec, o) {
    return wallDeltaSec > 0 && audioDeltaSec / wallDeltaSec < o.minClockRatio;
  }

  // Watches [ctx]; calls onOverload(detail) once when overload is sustained, then stops itself.
  // Returns stop(). options.signal: 'auto' (default) | 'clock' forces the clock-lag fallback.
  function watch(ctx, onOverload, options) {
    const o = Object.assign({}, DEFAULTS, options || {});
    const counter = createStrikeCounter(o.strikes);
    const startedAt = performance.now();
    let stopped = false;
    let cleanup = function () {};

    const inWarmup = () => performance.now() - startedAt < o.warmupMs;
    const trip = (detail) => {
      if (stopped) return;
      stopped = true;
      cleanup();
      onOverload(detail);
    };

    const rc = ctx.renderCapacity;
    if (o.signal !== 'clock' && rc && typeof rc.start === 'function') {
      const onUpdate = (event) => {
        if (stopped) return;
        if (inWarmup() || ctx.state !== 'running') { counter.reset(); return; }
        if (counter.record(isRenderCapacityBad(event, o))) {
          trip({
            signal: 'renderCapacity',
            underrunRatio: Number(event.underrunRatio.toFixed(3)),
            averageLoad: Number(event.averageLoad.toFixed(3)),
          });
        }
      };
      rc.addEventListener('update', onUpdate);
      rc.start({ updateInterval: o.intervalMs / 1000 });
      cleanup = () => {
        try { rc.removeEventListener('update', onUpdate); rc.stop(); } catch (_) {}
      };
    } else {
      let lastAudio = ctx.currentTime;
      let lastWall = performance.now();
      const timer = setInterval(() => {
        const audioNow = ctx.currentTime;
        const wallNow = performance.now();
        const audioDelta = audioNow - lastAudio;
        const wallDelta = (wallNow - lastWall) / 1000; // real elapsed, so a late timer tick isn't a false alarm
        lastAudio = audioNow;
        lastWall = wallNow;
        if (stopped) return;
        if (inWarmup() || ctx.state !== 'running') { counter.reset(); return; }
        if (counter.record(isClockStarved(audioDelta, wallDelta, o))) {
          trip({ signal: 'clock', ratio: Number((audioDelta / wallDelta).toFixed(3)) });
        }
      }, o.intervalMs);
      cleanup = () => clearInterval(timer);
    }

    return function stop() {
      if (stopped) return;
      stopped = true;
      cleanup();
    };
  }

  return { DEFAULTS, createStrikeCounter, isRenderCapacityBad, isClockStarved, watch };
})();
