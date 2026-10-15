"""Exercise the production raw-motion timing with input diagnostics on and off.

The isolated C harness extracts the added raw-motion function and timing expressions
from the shipped Wine patch. It supplies a deterministic clock and a timer/event
sink; it neither builds Wine nor opens an app or touches a game environment.
"""
import ctypes
from pathlib import Path
import platform
import re
import shutil
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


def function(source, name):
    start = source.index('static ', source.index(name) - 40)
    opening = source.index('{', source.index(name))
    depth = 1
    end = opening + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end]


class RawMotionTiming(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        compiler = shutil.which('clang')
        if not compiler:
            raise unittest.SkipTest('clang is unavailable')
        source = '\n'.join(line[1:] for line in (ROOT / 'patches/wine-mouselook.patch').read_text().splitlines()
                           if line.startswith('+') and not line.startswith('+++'))
        motion = function(source, 'static void raw_motion(')
        diagnostic_clock = function(source, 'static inline unsigned long long macdrv_stat_clock(')
        flush_clock = re.search(r'unsigned long long now = (.*);', function(source, 'static void raw_flush(')).group(1)
        silence = re.search(r'if \(([^\n]+raw_silence)\)', source).group(1)
        harness = r'''
#include <stdbool.h>
#include <string.h>
#include <math.h>
typedef bool BOOL;
#define TRUE true
#define FALSE false
#define CLOCK_UPTIME_RAW 4
#define DISPATCH_TIME_NOW 0
#define DISPATCH_TIME_FOREVER (~0ULL)
static bool macdrv_input_stats_on;
static unsigned long long test_now, flushes, flush_stamp, timer_delay;
static void *raw_timer;
static int raw_on;
static unsigned long long raw_interval, raw_last_motion, raw_last_post;
static const unsigned long long raw_silence = 250000000;
static double raw_pending_x, raw_pending_y;
static BOOL raw_flush_armed;
static struct { unsigned long long moves, posted; double dx, dy; unsigned int sources; } raw_stats;
static unsigned long long clock_gettime_nsec_np(int clock) { return test_now; }
'''
        harness += diagnostic_clock + '\n'
        harness += 'static unsigned long long event_clock(void) { return ' + flush_clock + '; }\n'
        harness += r'''
static unsigned long long dispatch_time(int base, unsigned long long delay) { timer_delay = delay; return test_now + delay; }
static void dispatch_source_set_timer(void *timer, unsigned long long when, unsigned long long repeat, unsigned long long leeway) {}
static void raw_flush(void) {
    ++flushes; flush_stamp = raw_last_post = event_clock();
    raw_pending_x = raw_pending_y = 0; raw_flush_armed = FALSE;
}
'''
        harness += motion + '\n'
        harness += 'int pointer_fallback(void) { return !(' + silence + '); }\n'
        harness += r'''
void reset(int diagnostics) {
    macdrv_input_stats_on = diagnostics;
    test_now = 5000000000ULL; raw_interval = 1000000;
    raw_on = 1; raw_last_motion = raw_last_post = 0;
    raw_pending_x = raw_pending_y = 0; raw_flush_armed = FALSE;
    flushes = flush_stamp = timer_delay = 0; memset(&raw_stats, 0, sizeof(raw_stats));
}
void advance(unsigned long long ns) { test_now += ns; }
void sample(float x, float y) { raw_motion(x, y, 0); }
void deactivate(void) { raw_on = 0; }
unsigned long long deliveries(void) { return flushes; }
unsigned long long timestamp(void) { return flush_stamp; }
unsigned long long last_motion(void) { return raw_last_motion; }
unsigned long long deadline_delay(void) { return timer_delay; }
double pending_x(void) { return raw_pending_x; }
double pending_y(void) { return raw_pending_y; }
int timer_armed(void) { return raw_flush_armed; }
'''
        cls.work = tempfile.TemporaryDirectory(prefix='mouselook-clock-')
        cls.addClassCleanup(cls.work.cleanup)
        path = Path(cls.work.name)
        (path / 'probe.c').write_text(harness)
        architecture = ['-arch', platform.machine()] if sys.platform == 'darwin' else []
        subprocess.run([compiler, *architecture, '-std=c11', '-shared', '-fPIC', '-O0', str(path / 'probe.c'),
                        '-o', str(path / 'probe.dylib')], check=True, capture_output=True, timeout=30)
        cls.probe = ctypes.CDLL(str(path / 'probe.dylib'))
        cls.probe.sample.argtypes = [ctypes.c_float, ctypes.c_float]
        cls.probe.advance.argtypes = [ctypes.c_ulonglong]
        for name in ('deliveries', 'timestamp', 'last_motion', 'deadline_delay'):
            getattr(cls.probe, name).restype = ctypes.c_ulonglong
        for name in ('pending_x', 'pending_y'):
            getattr(cls.probe, name).restype = ctypes.c_double

    def test_first_report_delivers_a_current_timestamp_without_diagnostics(self):
        for diagnostics in (0, 1):
            with self.subTest(diagnostics=diagnostics):
                self.probe.reset(diagnostics)
                self.probe.sample(6, -4)
                self.assertEqual(self.probe.deliveries(), 1)
                self.assertEqual(self.probe.timestamp(), 5_000_000_000)
                self.assertEqual(self.probe.last_motion(), 5_000_000_000)

    def test_rate_limit_keeps_motion_and_schedules_only_the_remaining_delay(self):
        for diagnostics in (0, 1):
            with self.subTest(diagnostics=diagnostics):
                self.probe.reset(diagnostics)
                self.probe.sample(6, -4)
                self.probe.advance(250_000)
                self.probe.sample(3, 2)
                self.assertEqual(self.probe.deliveries(), 1)
                self.assertEqual(self.probe.timer_armed(), 1)
                self.assertEqual(self.probe.deadline_delay(), 750_000)
                self.assertEqual((self.probe.pending_x(), self.probe.pending_y()), (3, -2))

    def test_pointer_events_resume_when_raw_input_is_silent(self):
        for diagnostics in (0, 1):
            with self.subTest(diagnostics=diagnostics):
                self.probe.reset(diagnostics)
                self.assertEqual(self.probe.pointer_fallback(), 1)  # No raw source has reported.
                self.probe.sample(6, -4)
                self.assertEqual(self.probe.pointer_fallback(), 0)  # Avoid double delivery.
                self.probe.advance(249_000_000)
                self.assertEqual(self.probe.pointer_fallback(), 0)
                self.probe.advance(1_000_000)
                self.assertEqual(self.probe.pointer_fallback(), 1)

    def test_background_motion_is_discarded_without_delivery(self):
        self.probe.reset(0)
        self.probe.deactivate()
        self.probe.sample(6, -4)
        self.assertEqual(self.probe.deliveries(), 0)
        self.assertEqual((self.probe.pending_x(), self.probe.pending_y()), (0, 0))


if __name__ == '__main__':
    unittest.main()
