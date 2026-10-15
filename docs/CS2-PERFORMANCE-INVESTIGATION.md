# CS2 sustained FPS collapse: investigation and optimization plan

Research date: October 13, 2026. Symptom: CS2 fell to approximately 4 FPS in
a casual match and stayed slow, as confirmed in the follow-up answer. That is
approximately 250 ms per frame. No frame trace of the affected interval was
available, so the cause remains unconfirmed.
First-use shader compilation is one hypothesis; it does not establish why the
slowdown persisted.

The initial review covered the launcher, installed profile and selected local logs,
Recall's DXMT/Wine patches, and primary upstream sources. It was read-only.
The subsequent v0.9 implementation and validation are recorded below; the table
in this section describes the original code, before those fixes.

The inspected machine is an M2 Max with 12 CPU cores, a 30-core GPU, 32 GB RAM
and macOS 26.5. About 6.2 GB of swap was allocated during inspection; a later
memory-pressure query reported 66–67% system memory free, and `pmset` reported
no thermal warning. These are snapshots outside the slow CS2 interval. Swap
occupancy alone does not prove active paging or memory pressure during play.

The runtime inspected initially was `phase2-20261007.3`. The source manifest pins DXMT to
`NerRobDog/dxmt` commit `c5dc3a0dfe9108e667da43de871324bd298c9c02`, plus Recall's
patches. Recall's published performance results are Overwatch measurements,
not CS2 benchmarks; their gains cannot be assumed for Source 2.

## What the code and local evidence establish

| Finding | Evidence | Implication |
| --- | --- | --- |
| CS2 inherits Overwatch's renderer settings. | `gamesProfile()` in [portable_steam.h](../scripts/portable_steam.h), lines 126–135, copies the section from [dxmt-source60-1200.conf](../config/dxmt-source60-1200.conf). | Eight normal-priority compiler workers, one-frame latency and pacing mode 3 have no CS2-specific validation here. |
| Speculative translation also runs, without a bound on predicted tasks. | [dxmt-v1-performance.patch](../patches/dxmt-v1-performance.patch), lines 368–460 and 528–572: two low-priority workers prepare compatible vertex/input-layout combinations and retain tasks. | Large shader/layout sets could create CPU, memory and cache contention. Foreground requests do not join an in-flight speculative task. Actual prediction volume and duplication in CS2 need measurement. |
| Offline preparation and Game Mode app cache warming are disconnected. | [build_native_app.py](../scripts/build_native_app.py), lines 44–54, does not package the pipeline helpers; `launchClient()` in [portable_setup.m](../scripts/portable_setup.m), lines 447–504, does not call them. | Launches miss Recall's explicit offline preparation. In-game shader caching and the inherited 128-entry/10-second prewarm remain enabled. |
| Dormant helpers still use the Overwatch cache identity. | [portable_pipeline.swift](../scripts/portable_pipeline.swift), line 103, uses `ow2-source-v1`; `wineEnv()` in `portable_setup.m`, line 163, uses `macvolvo-v1`. | Reconnecting the old helper unchanged would prepare the wrong identity. Its GPU registry-ID consolidation and per-app warming also need adapting. |
| An Overwatch texture optimization applies to CS2 by default. | `DXMT_DEFER_SHADER_WRITE` in `dxmt-v1-performance.patch`, lines 4270–4281; rationale at 5053–5057; first UAV use at 85–124. | First unordered-access use allocates a replacement texture and copies every mip/slice. Repeated resource creation/use could erase the compression benefit. This is a hypothesis, not a demonstrated CS2 regression. |
| The launcher sends SIGTERM to Steam after a game has run for 25 seconds. | `watchClient()` in [portable_session.h](../scripts/portable_session.h), lines 66–71; monitors start at `portable_setup.m`, lines 480 and 504. | Inherited Battle.net lifecycle policy needs removing for Steam. Two monitor logs record completion while a game runs, but actual Steam exit and FPS consequences were not established. |
| Current diagnostics cannot attribute shader or allocation stalls. | [portable_diagnostics.h](../scripts/portable_diagnostics.h), lines 31–35, enables frame/geometry/window/display/canvas traces only. [measure_resources.py](../scripts/measure_resources.py), lines 256–262 and 389–412, still targets Overwatch and old experiment paths. | Existing resource tools cannot simply be pointed at the installed CS2 session. Adapt process attribution and add the available shader/pipeline/resource streams. |

Saved CS2 settings currently contain a 1512 × 982 fullscreen resolution, VSync
off, 2× MSAA and `fps_max = 400`. The generated DXMT canvas is 1920 × 1200.
The port's `settingsFiles()` returns an empty list
([portable_preferences.h](../scripts/portable_preferences.h), lines 4–7), so it
does not read CS2's video configuration or synchronize this size. Extra scaling
is worth measuring, but this mismatch does not prove a 4 FPS cause. Numeric
FSR/HDR/low-latency settings were not interpreted as named UI modes.

Two retained CS2 launches show only `cs2.exe -steam`, without MacVolvo's game
launch arguments. Thus app-supplied `-w`, `-h` and `-nojoy` were
not present in those launches. Some recent shared logs contained MoltenVK
shader errors amid Deadlock launches; they cannot reliably be attributed to
CS2. The normal worker truncates/reuses `steam.log` at every launch
(`portable_setup.m`, lines 169–176), which further limits historical evidence.

## Most promising renderer change to evaluate

Upstream [DXMT issue #204](https://github.com/3Shain/dxmt/issues/204) reports a
synthetic workload where repeated `UpdateSubresource` calls on a DEFAULT
constant buffer become disproportionately expensive when bound to the pixel
shader. Its proposed allocator change reduced frame time from about 87 ms to
4.8 ms at 24,000 draws on the author's M3 Max. The author explicitly has not
shown that CS2 issues enough updates to trigger this behavior.

The implicated allocation pattern exists in our
[pinned d3d11_buffer.cpp](https://github.com/NerRobDog/dxmt/blob/c5dc3a0dfe9108e667da43de871324bd298c9c02/src/d3d11/d3d11_buffer.cpp):
only DYNAMIC buffers get `SuballocateFromOnePage`, while non-output DEFAULT
buffers also receive a `DynamicBuffer` using the unchanged flags. Recall's
checked-in patches do not change this constructor. Small DEFAULT-buffer
renames can consequently create separate Metal buffer objects rather than
sharing page allocations. This is a concrete optimization candidate whose
relevance to the reported match still needs profiling.

Evaluate suballocation on the rename allocator for small DEFAULT constant
buffers, separately from their initial allocations. Verify buffer contents,
offsets, synchronization and lifetime through immediate updates, deferred
command-list execution/re-execution, and mixed draw/dispatch use. Compare the
synthetic workload first, then the same CS2 scene. Treat this as an experimental
patch until those correctness checks and game measurements pass.

Upstream [issue #200](https://github.com/3Shain/dxmt/issues/200) discusses a
geometry/tessellation marshal hang. Its fatal missing loop increment is
already fixed in the pinned
[dxmt_command.metal](https://github.com/NerRobDog/dxmt/blob/c5dc3a0dfe9108e667da43de871324bd298c9c02/src/dxmt/dxmt_command.metal).
The pin also already contains v0.80's fence-based resource synchronization.
Neither is a missing fix that justifies replacing the runtime wholesale.

## Prioritized work

1. **Capture the sustained slowdown and fix Steam lifecycle.** Keep Steam
   running throughout gameplay. Use per-launch logs. Extend opt-in diagnostics
   with the existing bounded `DXMT_SHADER_LOG`, `DXMT_PIPELINE_CACHE_LOG` and
   `DXMT_RESOURCE_LOG` streams; include CS2 process footprint, GPU allocation,
   compiler activity and VM counter deltas. Keep ordinary launches quiet.
2. **Evaluate the DEFAULT constant-buffer rename allocator.** This is the
   strongest source-backed renderer optimization candidate found. Profile
   driver CPU cost and update/allocation counts before claiming a CS2 gain.
3. **Measure speculative shader work and compiler competition.** Compare
   `DXMT_PREPARE_SHADERS=0` with the current setting, then 4/6/8 compiler workers
   separately. Record prediction hits, duplicate in-flight work, queue delay
   and memory. Bound predictions and coalesce matching tasks if that work
   proves wasteful. More workers can increase contention.
4. **Restore offline cache preparation deliberately.** Parameterize cache
   identity, use the exact runtime cache codec, build/package the helpers, and
   warm the generated CS2 Game Mode app. Preserve learned recipes across GPU
   registry-ID changes while rebuilding incompatible GPU binaries. Consider
   per-game attribution: CS2 and Deadlock currently share the namespace and
   compete for the cost-ranked 128-entry startup selection.
5. **A/B deferred shader-write textures.** Compare
   `DXMT_DEFER_SHADER_WRITE=0` with the current default while measuring texture
   allocation/copy activity and GPU time. Keep it enabled if CS2 actually
   benefits. Apple's [texture guidance](https://developer.apple.com/documentation/metal/optimizing-texture-data)
   explains the compression/bandwidth tradeoff; compression is not proof of a
   smaller resident-memory footprint.

Pacing is a lower-priority candidate: its explicit sleep defaults to a maximum
of 8 ms, and mode 3 resets its estimate after waits above 25 ms
(`dxmt-v1-performance.patch`, lines 4467 and 4668–4682). That sleep alone cannot
account for persistent 250 ms frames; GPU waits or OS scheduling still can.

## Reproduction and acceptance

Start with the same map and settings; record player count and whether the game
was launched through MacVolvo or Steam. Capture normal play and at least ten
seconds of the collapse. Keep the game in focus during measurement and mark
menus, loading screens and focus changes. Record:

- Displayed frame intervals and GPU time, including median, p99 and time spent
  above 100/250 ms. In-game FPS and Present calls alone do not establish what
  reaches the screen.
- CS2 physical footprint and CPU load; shader compiler and Steam helper load;
  GPU allocated memory. Apple explains that [physical footprint includes CPU
  and GPU memory, compressed and swapped pages](https://developer.apple.com/videos/play/wwdc2022/10106/),
  so RSS alone is incomplete.
- VM swap-in/out and compression/decompression **deltas**, memory pressure and
  thermal state during the same interval.
- Shader queue/translation/Metal creation times, pipeline misses and first-UAV
  texture migrations. Migrations currently emit a warning suppressed by normal
  launch logging; add a bounded counter/span or targeted warning capture for
  this experiment. The shader trace already separates `queue_us`, `translate_us`
  and `metal_us` (`dxmt-v1-private.patch`, line 1376).

Low GPU time with long frames points investigation toward CPU/driver work,
compiler queues or waits. Long GPU time points toward expensive rendering,
resource hazards or copying. Footprint growth accompanied by paging during
the collapse supports a memory-pressure explanation. These are diagnostic
signatures, not conclusions from the current snapshots.

After a repeat of the same scene, change one factor per run. A 60/120 FPS cap
and disabling 2× MSAA are useful first settings experiments, not proven fixes.
For cache-sensitive comparisons, preserve equivalent starting caches: a second
run is naturally warmer and can falsely credit an unrelated change. Keep
driver/runtime versions and image quality recorded, and repeat a promising
result in a comparable casual match before setting a default.

For a diagnostic launch, first close Steam and both games through the normal
UI. The currently built developer app's worker can then open Steam with the
existing frame/display traces:

```sh
runtime/build/release/MacVolvo.app/Contents/Helpers/ow2-setup \
  diagnostic-launch --game cs2 \
  --root "$HOME/Library/Application Support/MacVolvo" \
  --metal-hud 1
```

In v0.9 this opens CS2 through Steam and emits the `logs/parity-<UUID>` output
folder. It includes frame, display, shader, pipeline, resource and mouse-state
traces. An already-open Steam retains its original environment, so diagnostic
capture requires closing Steam first. Normal launches keep these traces off.
For bounded process/VM/GPU counters alongside the game:

```sh
python3 scripts/process_probe.py --build
arch -arm64 /usr/bin/python3 scripts/measure_macvolvo.py \
  --worker runtime/build/release/MacVolvo.app/Contents/Helpers/ow2-setup \
  --seconds 600 --output runtime/build/cs2-capture
```

Choose a new output folder for each run. The sampler admits only the worker-owned
Steam/game processes and brackets admission with kernel start identities. CPU
counters must run in native ARM Python: Rosetta virtualizes the Mach timebase.
The native counter tests compare CPU time to an independent measurement.

Saved AIR and learned render pipelines also do not guarantee every effect is
warm. Apple's [compilation workflow](https://developer.apple.com/videos/play/wwdc2021/10229/)
distinguishes cached intermediate code from GPU binaries. Recall's speculative
preparation stores translation results; final pipeline creation may still
block first use, and the native persisted render-pipeline path does not cover
every compute/geometry/tessellation path.

Success means the same workload no longer enters a sustained slow state,
frame-time tails improve, memory remains stable, and rendering stays correct.
No FPS improvement is claimed from this research alone.

## v0.9 implementation and remaining verification

The owner later reported repeated combat spikes when being shot or when enemies
appear, persisting across rounds. That is distinct from the original sustained
4 FPS collapse. Repeated rounds do not rule out new shader/pipeline combinations,
but first-use compilation is not an adequate diagnosis without a matching trace.

Implemented: per-game resolution/canvas options, common display ratios plus
custom sizes, Steam Properties synchronization preserving unrelated arguments,
CS2's initial `+fps_max 120` (preserving an existing launch-option cap), and four
CS2 shader compiler workers instead of the inherited eight. Deadlock retains
eight. The worker no longer terminates Steam after 25 seconds. Unique launch
logs replace the shared truncated log. These changes are mitigation candidates;
no measured improvement in combat or the 4 FPS episode is claimed.

Fixed two concrete input/launch bugs: functional raw-input timing depended on
a statistics clock that returned zero with logging off, and session discovery
recognized only Windows-style executable paths although Wine can expose Unix
paths. Game handoff now waits for the game window instead of activating Steam
during fullscreen initialization. Native driver ABI and dependencies were checked;
all other runtime files were verified byte-identical to the base archive.

A Deadlock startup on `phase2-20261013.1` produced 52,238 frame intervals over
approximately 472 seconds, a visible fullscreen window, and loaded the patched
winemac driver plus DX11/DXMT. This verifies that the candidate can start and
present; it does not prove absence of intermittent black screens or post-match
mouse failure. No competitive match was automated. A later old-app launch
reselected `phase2-20261007.3`, so delivery must replace the owner's existing
`runtime/build/release/MacVolvo.app` rather than leave the candidate elsewhere.

DEFAULT constant-buffer suballocation, speculative compilation changes and
deferred shader-write changes remain experiments requiring a renderer build
and correctness/performance comparisons. They are not silently enabled in v0.9.

## Deadlock black-screen follow-up — October 14

The owner reports intermittent black video with music from both MacVolvo and
Steam Library launches. The v0.9 handoff change therefore did not establish a
complete fix. The active runtime remains phase2-20261013.1 and the saved backend
is DX11. The canvas overlay is already disabled in the shipped contract;
disabling it again would not change this installation. Do not attribute Steam
MoltenVK browser messages to Deadlock's DXMT renderer.

Reproduction was initially blocked before game startup: Steam's connection log
contained repeated timeout/error entries, no new Deadlock process appeared, and
normal Steam shutdown timed out. After checking that no game was running, the
owned idle session was stopped and Steam reopened with game/frame/canvas/input
diagnostics. Latest capture: logs/parity-23A89179-10EA-46D5-9E3B-71551EE3C835.
No renderer or fullscreen default was changed on this evidence.

The latest five Deadlock assert dumps contain no exception stream, so they do
not identify the cause of the black screen. Next: inspect the live failed game
before restarting. Compare native presentation callbacks, swapchain geometry,
fullscreen transition/focus records and input activity. If it reproduces, test
windowed mode separately to isolate the fullscreen path rather than changing
several renderer settings at once.

### Captured fullscreen deadlock and candidate repair

At 14:30 local time on October 14 the owner confirmed that native PID 59180
(Windows PID 2908) was black with music. Its canvas entered fullscreen and gained
focus, but its frame recorder had zero boundary intervals and no drawable geometry
or native presentation trace. The same capture directory contains the earlier
successful session (PID 51981), so lack of presentation is specific to this launch.
The failed-state sample is retained locally as
`deadlock-59180-black-screen.sample.txt` in that capture directory.

All 2,082 samples of the game main thread were in this chain (stripped winemac
addresses resolved against the matching unstripped local build's symbol table):

    NtUserChangeDisplaySettings
      macdrv_ChangeDisplaySettings
        macdrv_set_display_mode
          OnMainThread
            macdrv_handle_event
              query_resize_start
                sync_window_min_max_info
                  NtUserGetWinMonitorDpi
                    pthread_mutex_lock

The pinned win32u source holds its non-recursive `display_lock` across
`pChangeDisplaySettings`. While waiting for Cocoa, `OnMainThread` pumps
`QUERY_EVENT`. A pending resize-start query then reads monitor DPI, attempting
to acquire that same lock on the same thread. This explains the captured
startup stall, including why audio can continue. It does not establish the
cause of post-match mouse loss or CS2 combat spikes.

The activation patch now submits resize-start with `WineQueryNoPreemptWait`.
Wine already supports this event class: it remains queued through the synchronous
Cocoa wait and is handled by the normal event pump after the display call returns.
The query retains its bounded 0.3-second Cocoa timeout; interactive resize still
uses the normal query handler. No global lock semantics or rendering settings
change.

`tests/test_winemac_display_query.py` applies all three production patches to
the pinned Wine driver, compiles its resize method and synchronous query pump,
and injects a resize while a non-recursive display lock is held. The new policy
delivers the query after unlocking; the old policy's negative control detects
the self-lock. Native driver build passed with identical exports and dependencies.
Candidate runtime: `phase2-20261014.1`; app remains 0.9, build 3. Real-game startup
verification and post-match input verification remain separate from this test.
