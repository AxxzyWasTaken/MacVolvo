"""Exercise the Wine resize query inside a display-lock-held OnMainThread wait.

Requires the pinned Wine source used for runtime builds. The harness compiles
the patched production resize method and OnMainThread pump. A deterministic
queue delivers the resize at the problematic interleaving; trylock detects the
old self-deadlock without hanging the test.
"""
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / "runtime/source/cx26/sources/wine/dlls/winemac.drv"


def block(source, signature):
    start = source.index(signature)
    opening = source.index("{", start)
    depth = 1
    end = opening + 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start:end]


@unittest.skipUnless(BASE.exists(), "requires pinned Wine source")
class DisplayQuery(unittest.TestCase):
    def test_resize_is_deferred_until_display_lock_is_released(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder = Path(tmp)
            driver = folder / "dlls/winemac.drv"
            shutil.copytree(BASE, driver)
            for patch in ("wine-v1-canvas.patch", "wine-mouselook.patch", "wine-winemac-activation.patch"):
                subprocess.run(["patch", "-N", "-F0", "-p1", "-i", str(ROOT / "patches" / patch)],
                               cwd=folder, check=True, capture_output=True)
            source = (driver / "cocoa_event.m").read_text()
            pump = block(source, "void OnMainThread(dispatch_block_t block)")
            method = block((driver / "cocoa_window.m").read_text(), "- (void) sendResizeStartQuery")
            selection = re.search(r"type = \(flags & WineQueryNoPreemptWait\)[^;]+;", source).group()
            harness = r"""
#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
#include <pthread.h>
#include <sys/event.h>
#include <assert.h>
enum { QUERY_EVENT=1, QUERY_EVENT_NO_PREEMPT_WAIT=2, QUERY_RESIZE_START=3,
       WineQueryNoPreemptWait=2 };
typedef void *macdrv_window;
typedef struct { int type; macdrv_window window; } macdrv_query;
typedef struct { int type; } macdrv_event;
static macdrv_query *macdrv_create_query(void) { return calloc(1,sizeof(macdrv_query)); }
static void macdrv_release_query(macdrv_query *q) { [(id)q->window release]; free(q); }
static unsigned event_mask_for_type(int type) { return 1u << type; }
static pthread_mutex_t display_lock=PTHREAD_MUTEX_INITIALIZER;
static int blocked, handled;
static void handle(macdrv_event *event) {
    if (pthread_mutex_trylock(&display_lock)) blocked++;
    else { handled++; pthread_mutex_unlock(&display_lock); }
}
@interface MacDrvEvent : NSObject { @public macdrv_event *event; }
@end
@implementation MacDrvEvent
@end
@interface WineEventQueue : NSObject {
@public int kq; void (*event_handler)(macdrv_event *);
    MacDrvEvent *pending;
}
- (BOOL)query:(macdrv_query*)q timeout:(NSTimeInterval)t flags:(NSUInteger)flags;
- (BOOL)query:(macdrv_query*)q timeout:(NSTimeInterval)t;
- (MacDrvEvent*)getEventMatchingMask:(unsigned)mask;
- (void)signalEventAvailable;
@end
@implementation WineEventQueue
- (BOOL)query:(macdrv_query*)q timeout:(NSTimeInterval)t flags:(NSUInteger)flags {
    int type;
    SELECTION
    pending=[MacDrvEvent new]; pending->event=calloc(1,sizeof(macdrv_event));
    pending->event->type=type;
    return NO;
}
- (BOOL)query:(macdrv_query*)q timeout:(NSTimeInterval)t {
    return [self query:q timeout:t flags:0];
}
- (MacDrvEvent*)getEventMatchingMask:(unsigned)mask {
    if (pending && (event_mask_for_type(pending->event->type) & mask)) {
        MacDrvEvent *result=pending; pending=nil; return result;
    }
    return nil;
}
- (void)signalEventAvailable {}
@end
@interface WineWindow : NSObject { WineEventQueue *_queue; }
@property(retain) WineEventQueue *queue;
- (void)sendResizeStartQuery;
@end
@implementation WineWindow
@synthesize queue=_queue;
METHOD
@end
static NSString *WineEventQueueThreadDictionaryKey=@"testWineQueue";
static dispatch_block_t queuedBlock;
static void OnMainThreadAsync(dispatch_block_t block) { queuedBlock=[block copy]; }
static int fake_kevent(int kq, const struct kevent *c, int n, struct kevent *e,
                       int count, const struct timespec *timeout) {
    queuedBlock(); [queuedBlock release]; queuedBlock=nil; return 1;
}
#define kevent(...) fake_kevent(__VA_ARGS__)
PUMP
int main(void) { @autoreleasepool {
    WineEventQueue *q=[WineEventQueue new]; q->event_handler=handle;
    [[NSThread currentThread] threadDictionary][WineEventQueueThreadDictionaryKey]=q;
    WineWindow *w=[WineWindow new]; w.queue=q;
    [w sendResizeStartQuery];
    pthread_mutex_lock(&display_lock);
    OnMainThread(^{});
    pthread_mutex_unlock(&display_lock);
    MacDrvEvent *event=[q getEventMatchingMask:~0u];
    if(event) handle(event->event);
    printf("%d %d\n",blocked,handled);
    return 0;
}}
"""
            harness = harness.replace("SELECTION", selection).replace("METHOD", method).replace("PUMP", pump)
            for control in (False, True):
                # Negative control reproduces the old preempting query policy.
                text = harness.replace("timeout:0.3 flags:WineQueryNoPreemptWait", "timeout:0.3") if control else harness
                path = folder / "probe.m"
                path.write_text(text)
                binary = folder / "probe"
                built = subprocess.run(["clang", "-fblocks", "-framework", "Foundation", str(path), "-o", str(binary)],
                                       text=True, capture_output=True)
                self.assertEqual(built.returncode, 0, built.stderr)
                result = subprocess.check_output([str(binary)], text=True, timeout=5).strip()
                self.assertEqual(result, "1 0" if control else "0 1")


if __name__ == "__main__":
    unittest.main()
