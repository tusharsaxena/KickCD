# Capture — 2026-09-09 01:36

Copied out of the client's debug-log window after `/kcd perf finish`, `/kcd perf report` and
`/kcd perf dump`. Split into its three parts below; the machine record is in
[`dump.json`](dump.json) and the reading is in [`ANALYSIS.md`](ANALYSIS.md).

## Run log — the capture's provenance

The lifecycle lines, kept with their `HH:MM:SS | [Tag]` prefixes. These are how a later reader
confirms both arms were combat-gated, that arm B really was suspended, and that no `/reload` landed
between the arms (`performance-§7`). Note the **first run was CANCELED** and discarded; the capture
below is the second run, started 21 minutes later in a different zone.

```
01:15:04 | [Perf] run started — 2026-09-09 01:15
01:15:04 | [Perf] who:       Sacrìlege-Frostmourne, level 90 Protection Paladin
01:15:04 | [Perf] where:     Silvermoon City — The Bazaar
01:15:04 | [Perf] group:     solo
01:15:04 | [Perf] perf run STARTED — 2026-09-09 01:15
01:15:33 | [Perf] run CANCELED — measurements discarded, nothing saved
01:36:18 | [Perf] run started — 2026-09-09 01:36
01:36:18 | [Perf] who:       Sacrìlege-Frostmourne, level 90 Protection Paladin
01:36:18 | [Perf] where:     Nexus-Point Xenas
01:36:18 | [Perf] group:     party (5) / party
01:36:18 | [Perf] perf run STARTED — 2026-09-09 01:36
01:36:33 | [Perf] experiment A armed (addon active) — waiting for combat
01:36:37 | [Perf] Experiment A RECORDING — combat started
01:37:44 | [Perf] Experiment A ENDED — 67.2s, 4859 frames, 72.3 fps
01:39:19 | [Perf] addon SUSPENDED — inert
01:39:19 | [Perf] experiment B armed (addon SUSPENDED) — waiting for combat
01:39:28 | [Perf] Experiment B RECORDING — combat started
01:40:30 | [Perf] Experiment B ENDED — 62.0s, 4499 frames, 72.5 fps
01:40:33 | [Perf] run finished — A 67.2s / 4859 frames, B 62.0s / 4499 frames
01:40:33 | [Perf] addon RESUMED — events and frames restored
01:40:33 | [Perf] perf run FINISHED — saved; `Report` or `Dump` in the panel to read it, `/reload` to flush it to SavedVariables
```

Unlike [`../20260807-131311/report.md`](../20260807-131311/report.md), this paste carries **no
`[Debug]`, `[Cooldowns]`, `[IconGrid]` or `[Cast]` lines at all** — the addon's debug console was not
enabled for this run. That is provenance, not an omission in the copy: it means the debug-only
branches inside the instrumented functions did not execute. `ANALYSIS.md` reads the consequence.

## The report — `/kcd perf report`

```
01:40:34 | [Perf] capture: 2026-09-09 01:36  (KickCD, schema 2, v1.2.1)
01:40:34 | [Perf] who:       Sacrìlege-Frostmourne, level 90 Protection Paladin
01:40:34 | [Perf] where:     Nexus-Point Xenas
01:40:34 | [Perf] group:     party (5) / party
01:40:34 | [Perf] active:       67.2s    4859 frames    72.3 fps   13.83 ms/frame
01:40:34 | [Perf] suspended:    62.0s    4499 frames    72.5 fps   13.79 ms/frame
01:40:34 | [Perf] delta:                                                   +0.04 ms/frame
01:40:34 | [Perf] 
01:40:34 | [Perf] bucket            calls   total ms       ms/s    max ms
01:40:34 | [Perf] spellPoll           810     210.55      3.134     9.640
01:40:34 | [Perf]   pollSpell        2450      99.46      1.480     0.296
01:40:34 | [Perf]   spellState       1590      80.83      1.203     0.213
01:40:34 | [Perf]     iconApply      3228      73.46      1.093     0.195
01:40:34 | [Perf] cdText              573      25.25      0.376     0.145
01:40:34 | [Perf] castEvent            13       0.69      0.010     0.077
01:40:34 | [Perf] visibility           45       1.19      0.018     0.183
01:40:34 | [Perf] castTick            778       9.18      0.137     0.134
01:40:34 | [Perf] (buckets nest: pollSpell declares itself within spellPoll — not observed, spellState declares itself within spellPoll — not observed, iconApply declares itself within spellState — not observed — do not sum)
```

## The dump — `/kcd perf dump`

Committed verbatim as [`dump.json`](dump.json). Reproduced here as it came out of the log window:

```
01:40:35 | [Perf] {"addon":"KickCD","buckets":{"castEvent":{"calls":13,"maxMs":0.0773,"totalMs":0.6886},"castTick":{"calls":778,"maxMs":0.1345,"totalMs":9.1848},"cdText":{"calls":573,"maxMs":0.1455,"totalMs":25.2480},"iconApply":{"calls":3228,"maxMs":0.1948,"totalMs":73.4586,"within":"spellState"},"pollSpell":{"calls":2450,"maxMs":0.2961,"totalMs":99.4554,"within":"spellPoll"},"spellPoll":{"calls":810,"maxMs":9.6400,"totalMs":210.5512},"spellState":{"calls":1590,"maxMs":0.2135,"totalMs":80.8323,"within":"spellPoll"},"visibility":{"calls":45,"maxMs":0.1826,"totalMs":1.1934}},"context":{"character":"Sacrìlege","class":"Paladin","group":"party (5) / party","level":90,"realm":"Frostmourne","spec":"Protection","subZone":"","zone":"Nexus-Point Xenas"},"fps":{"active":{"avgFps":72.3173,"frames":4859,"msPerFrame":13.8279,"seconds":67.1900},"deltaMsPerFrame":0.0407,"suspended":{"avgFps":72.5306,"frames":4499,"msPerFrame":13.7873,"seconds":62.0290}},"interface":120100,"label":"2026-09-09 01:36","schema":2,"source":"ingame","timestamp":1788898235,"version":"1.2.1"}
```
