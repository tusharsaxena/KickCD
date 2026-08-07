# Capture — 2026-08-07 13:09

Copied out of the client's debug-log window after `/kcd perf finish`, `/kcd perf report` and
`/kcd perf dump`. Split into its three parts below; the machine record is in
[`dump.json`](dump.json) and the reading is in [`ANALYSIS.md`](ANALYSIS.md).

## Run log — the capture's provenance

The lifecycle lines, plus the addon's own combat / cooldown / visibility output. These are how a
later reader confirms both arms were combat-gated, that arm B really was suspended, and that no
`/reload` landed between the arms (`performance-§7`).

```
13:09:56 | [Perf] run started — 2026-08-07 13:09
13:09:56 | [Perf] who:       Lânfear-Frostmourne, level 90 Destruction Warlock
13:09:56 | [Perf] where:     Silvermoon City — Falconwing Square
13:09:56 | [Perf] group:     solo
13:09:56 | [Perf] perf run STARTED — 2026-08-07 13:09
13:09:59 | [Debug] logging enabled
13:09:59 | [Init] KickCD v1.2.1, schema v4, profile 'Default'
13:10:47 | [Cooldowns] rebuild WARLOCK(9) DESTRUCTION(267): 4 watched (19647,30283,6789,5782); 1 skipped (5484)
13:10:50 | [Cooldowns] 4/4 changed: 
13:11:08 | [Cooldowns] 3/4 changed: active=[5782,30283,6789]
13:11:09 | [Combat] entered
13:11:10 | [Cooldowns] 3/4 changed: ready=[5782,30283,6789]
13:11:11 | [Perf] experiment A armed (addon active) — waiting for combat
13:11:11 | [Perf] Experiment A RECORDING — combat started
13:11:12 | [Cooldowns] 3/4 changed: active=[5782,30283,6789]
13:11:13 | [IconGrid] [target] visibility target_casting_interruptible: shown
13:11:13 | [Cast] [target] cast gate: interruptible secret (combat-tainted)
13:11:14 | [Cooldowns] 3/4 changed: ready=[5782,30283,6789]
13:11:14 | [IconGrid] [target] visibility target_casting_interruptible: hidden
13:11:14 | [Cast] [target] cast gate: interruptible none (no hostile cast)
13:11:14 | [Cooldowns] 1/4 changed: active=[19647]
13:11:15 | [Cooldowns] 3/4 changed: active=[5782,30283,6789]
13:11:15 | [IconGrid] [focus] visibility target_casting_interruptible: shown
13:11:15 | [Cast] [focus] cast gate: interruptible secret (combat-tainted)
13:11:16 | [Cooldowns] 3/4 changed: ready=[5782,30283,6789]
13:11:17 | [Cooldowns] 3/4 changed: active=[5782,30283,6789]
13:11:17 | [Cooldowns] 3/4 changed: ready=[5782,30283,6789]
13:11:18 | [Cooldowns] 3/4 changed: active=[5782,30283,6789]
13:11:19 | [Cooldowns] 3/4 changed: ready=[5782,30283,6789]
13:11:19 | [Cooldowns] 3/4 changed: active=[5782,30283,6789]
13:11:20 | [IconGrid] [focus] visibility target_casting_interruptible: hidden
13:11:20 | [Cast] [focus] cast gate: interruptible none (no hostile cast)
13:11:20 | [IconGrid] [target] visibility target_casting_interruptible: shown
13:11:20 | [Cast] [target] cast gate: interruptible secret (combat-tainted)
13:11:20 | [Cooldowns] 3/4 changed: ready=[5782,30283,6789]
13:11:20 | [IconGrid] [target] visibility target_casting_interruptible: hidden
13:11:20 | [Cast] [target] cast gate: interruptible none (no hostile cast)
13:11:21 | [Cooldowns] 3/4 changed: active=[5782,30283,6789]
13:11:21 | [IconGrid] [focus] visibility target_casting_interruptible: shown
13:11:21 | [Cast] [focus] cast gate: interruptible secret (combat-tainted)
13:11:21 | [Cooldowns] 3/4 changed: ready=[5782,30283,6789]
13:11:22 | [Cooldowns] 3/4 changed: active=[5782,30283,6789]
13:11:24 | [IconGrid] [target] visibility target_casting_interruptible: shown
13:11:24 | [Cast] [target] cast gate: interruptible secret (combat-tainted)
13:11:25 | [Cooldowns] 3/4 changed: ready=[5782,30283,6789]
13:11:25 | [Cooldowns] 3/4 changed: active=[5782,30283,6789]
13:11:26 | [IconGrid] [target] visibility target_casting_interruptible: hidden
13:11:26 | [Cast] [target] cast gate: interruptible none (no hostile cast)
13:11:26 | [IconGrid] [focus] visibility target_casting_interruptible: hidden
13:11:26 | [Cast] [focus] cast gate: interruptible none (no hostile cast)
13:11:26 | [IconGrid] [target] visibility target_casting_interruptible: shown
13:11:26 | [Cast] [target] cast gate: interruptible secret (combat-tainted)
13:11:26 | [IconGrid] [focus] visibility target_casting_interruptible: shown
13:11:26 | [Cast] [focus] cast gate: interruptible secret (combat-tainted)
13:11:26 | [Cooldowns] 3/4 changed: ready=[5782,30283,6789]
13:11:29 | [Cooldowns] 3/4 changed: active=[5782,30283,6789]
13:11:29 | [IconGrid] [target] visibility target_casting_interruptible: hidden
13:11:29 | [Cast] [target] cast gate: interruptible none (no hostile cast)
13:11:29 | [IconGrid] [focus] visibility target_casting_interruptible: hidden
13:11:29 | [Cast] [focus] cast gate: interruptible none (no hostile cast)
13:11:30 | [Cooldowns] 2/4 changed: ready=[5782,30283]
13:11:32 | [Cooldowns] 2/4 changed: active=[5782,30283]
13:11:33 | [Cooldowns] 2/4 changed: ready=[5782,30283]
13:11:33 | [Cooldowns] 2/4 changed: active=[5782,30283]
13:11:34 | [Cooldowns] 2/4 changed: ready=[5782,30283]
13:11:34 | [Cooldowns] 2/4 changed: active=[5782,30283]
13:11:35 | [Cooldowns] 2/4 changed: ready=[5782,30283]
13:11:36 | [Cooldowns] 2/4 changed: active=[5782,30283]
13:11:37 | [Combat] left
13:11:37 | [Perf] Experiment A ENDED — 25.7s, 1772 frames, 69.1 fps
13:11:37 | [Cooldowns] 2/4 changed: ready=[5782,30283]
13:11:38 | [Cooldowns] 1/4 changed: ready=[19647]
13:11:49 | [Cooldowns] 4/4 changed: 
13:12:06 | [Cooldowns] 4/4 changed: 
13:12:15 | [Perf] addon SUSPENDED — inert
13:12:15 | [Perf] experiment B armed (addon SUSPENDED) — waiting for combat
13:12:23 | [Combat] entered
13:12:23 | [Perf] Experiment B RECORDING — combat started
13:13:02 | [Combat] left
13:13:03 | [Perf] Experiment B ENDED — 39.7s, 2711 frames, 68.3 fps
13:13:08 | [Perf] run finished — A 25.7s / 1772 frames, B 39.7s / 2711 frames
13:13:08 | [Perf] addon RESUMED — events and frames restored
13:13:08 | [Perf] perf run FINISHED — saved; `Report` or `Dump` in the panel to read it, `/reload` to flush it to SavedVariables
```

## The report — `/kcd perf report`

```
13:13:10 | [Perf] capture: 2026-08-07 13:09  (KickCD, schema 2, v1.2.1)
13:13:10 | [Perf] who:       Lânfear-Frostmourne, level 90 Destruction Warlock
13:13:10 | [Perf] where:     Silvermoon City — Falconwing Square
13:13:10 | [Perf] group:     solo
13:13:10 | [Perf] active:       25.7s    1772 frames    69.1 fps   14.48 ms/frame
13:13:10 | [Perf] suspended:    39.7s    2711 frames    68.3 fps   14.65 ms/frame
13:13:10 | [Perf] delta:                                                   -0.17 ms/frame
13:13:10 | [Perf] 
13:13:10 | [Perf] bucket            calls   total ms       ms/s    max ms
13:13:10 | [Perf] spellPoll           399     135.26      5.273     1.750
13:13:10 | [Perf]   pollSpell        1596      67.13      2.617     0.715
13:13:10 | [Perf]   spellState       1171      54.39      2.120     1.419
13:13:10 | [Perf]     iconApply      2342      50.03      1.950     1.396
13:13:10 | [Perf] cdText              225      11.47      0.447     0.174
13:13:10 | [Perf] castEvent            11       1.64      0.064     0.310
13:13:10 | [Perf] visibility           21       1.65      0.064     0.263
13:13:10 | [Perf] castTick           1262      11.61      0.453     0.056
13:13:10 | [Perf] (buckets nest: pollSpell declares itself within spellPoll — not observed, spellState declares itself within spellPoll — not observed, iconApply declares itself within spellState — not observed — do not sum)
```

## The dump — `/kcd perf dump`

Committed verbatim as [`dump.json`](dump.json). Reproduced here as it came out of the log window:

```
13:13:11 | [Perf] {"addon":"KickCD","buckets":{"castEvent":{"calls":11,"maxMs":0.3104,"totalMs":1.6358},"castTick":{"calls":1262,"maxMs":0.0560,"totalMs":11.6115},"cdText":{"calls":225,"maxMs":0.1739,"totalMs":11.4686},"iconApply":{"calls":2342,"maxMs":1.3961,"totalMs":50.0322,"within":"spellState"},"pollSpell":{"calls":1596,"maxMs":0.7148,"totalMs":67.1303,"within":"spellPoll"},"spellPoll":{"calls":399,"maxMs":1.7497,"totalMs":135.2610},"spellState":{"calls":1171,"maxMs":1.4186,"totalMs":54.3927,"within":"spellPoll"},"visibility":{"calls":21,"maxMs":0.2628,"totalMs":1.6512}},"context":{"character":"Lânfear","class":"Warlock","group":"solo","level":90,"realm":"Frostmourne","spec":"Destruction","subZone":"Falconwing Square","zone":"Silvermoon City"},"fps":{"active":{"avgFps":69.0784,"frames":1772,"msPerFrame":14.4763,"seconds":25.6520},"deltaMsPerFrame":-0.1740,"suspended":{"avgFps":68.2579,"frames":2711,"msPerFrame":14.6503,"seconds":39.7170}},"interface":120007,"label":"2026-08-07 13:09","schema":2,"source":"ingame","timestamp":1786088591,"version":"1.2.1"}
```
