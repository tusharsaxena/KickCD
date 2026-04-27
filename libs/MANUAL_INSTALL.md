# Library Manual Install Guide

The KickCD build sandbox cannot reach the network, so the embedded libraries
in this folder must be dropped in by hand before the addon will load. Once
this is done, KickCD's TOC will resolve every `libs\...` line and WoW will
load cleanly.

This guide is **copy-pasteable**: follow the steps in order, and the final
`find` command at the bottom should match the expected output exactly.

---

## 1. What you're downloading

| Library | Purpose | Source (CurseForge) |
| --- | --- | --- |
| **Ace3** | Bundle: `LibStub`, `CallbackHandler-1.0`, `AceAddon-3.0`, `AceEvent-3.0`, `AceDB-3.0`, `AceDBOptions-3.0`, `AceConsole-3.0`, `AceConfig-3.0` (+ `AceConfigRegistry-3.0`, `AceConfigDialog-3.0`, `AceConfigCmd-3.0`), `AceGUI-3.0` | https://www.curseforge.com/wow/addons/ace3/files |
| **LibSharedMedia-3.0** | Shared font / texture / sound registry | https://www.curseforge.com/wow/addons/libsharedmedia-3-0/files |

Mirrors (in case CurseForge is unreachable):

- Ace3 GitHub mirror: <https://github.com/WoWUIDev/Ace3>
- Ace3 SVN trunk: <https://repos.wowace.com/wow/ace3/trunk>
- LibSharedMedia GitHub: <https://github.com/funkydude/LibSharedMedia-3.0>
- LibSharedMedia SVN trunk: <https://repos.wowace.com/wow/libsharedmedia-3-0/trunk>

Pick whichever you can reach. The CurseForge zip is the most foolproof for
end users and is what most addon authors ship.

---

## 2. Step-by-step install

> All paths below are relative to **this folder**: `KickCD/libs/`.
> The `libs/` directory already contains empty placeholder subfolders that
> match the layout below — you can either delete and recreate them, or just
> drop the files into the existing folders.

### Step 1 — Download Ace3

1. Open <https://www.curseforge.com/wow/addons/ace3/files>
2. Click the latest **Release** zip (e.g. `Ace3-r1234.zip`).
3. Extract the zip somewhere temporary. You will see a top-level `Ace3/`
   folder containing many sub-folders.

### Step 2 — Copy the Ace3 sub-folders into `KickCD/libs/`

Copy the following sub-folders from the extracted `Ace3/` folder into
`KickCD/libs/` (overwriting/merging the empty placeholder folders):

```
Ace3/LibStub/                  →  KickCD/libs/LibStub/
Ace3/CallbackHandler-1.0/      →  KickCD/libs/CallbackHandler-1.0/
Ace3/AceAddon-3.0/             →  KickCD/libs/AceAddon-3.0/
Ace3/AceEvent-3.0/             →  KickCD/libs/AceEvent-3.0/
Ace3/AceDB-3.0/                →  KickCD/libs/AceDB-3.0/
Ace3/AceDBOptions-3.0/         →  KickCD/libs/AceDBOptions-3.0/
Ace3/AceConsole-3.0/           →  KickCD/libs/AceConsole-3.0/
Ace3/AceConfig-3.0/            →  KickCD/libs/AceConfig-3.0/
Ace3/AceConfigRegistry-3.0/    →  KickCD/libs/AceConfigRegistry-3.0/
Ace3/AceConfigDialog-3.0/      →  KickCD/libs/AceConfigDialog-3.0/
Ace3/AceGUI-3.0/               →  KickCD/libs/AceGUI-3.0/
```

> Note: `AceConfig-3.0/` ships its own `AceConfig-3.0.xml` that pulls in
> `AceConfigRegistry-3.0`, `AceConfigCmd-3.0`, and `AceConfigDialog-3.0`
> via relative `..\` paths. The TOC also lists the registry and dialog
> directly — both routes resolve to the same files, which is fine because
> LibStub de-duplicates by version.

### Step 3 — Download LibSharedMedia-3.0

1. Open <https://www.curseforge.com/wow/addons/libsharedmedia-3-0/files>
2. Click the latest **Release** zip.
3. Extract it. You will see a `LibSharedMedia-3.0/` folder.

### Step 4 — Copy LibSharedMedia into `KickCD/libs/`

```
LibSharedMedia-3.0/  →  KickCD/libs/LibSharedMedia-3.0/
```

The folder must contain **`lib.xml`** at minimum (this is what the TOC
references). If the release ships a `LibSharedMedia-3.0.xml` instead, rename
it to `lib.xml` — that is the standalone-embed convention this TOC follows.

---

## 3. Expected target tree

After both libs are dropped in, this is the **exact** layout the TOC
expects to see. Files marked `(*)` are the ones the TOC references directly;
everything else is loaded transitively via the `.xml` manifests.

```
KickCD/libs/
├── LibStub/
│   └── LibStub.lua                              (*)
├── CallbackHandler-1.0/
│   ├── CallbackHandler-1.0.lua                  (*)
│   └── CallbackHandler-1.0.xml
├── AceAddon-3.0/
│   ├── AceAddon-3.0.lua                         (*)
│   └── AceAddon-3.0.xml
├── AceEvent-3.0/
│   ├── AceEvent-3.0.lua                         (*)
│   └── AceEvent-3.0.xml
├── AceDB-3.0/
│   ├── AceDB-3.0.lua                            (*)
│   └── AceDB-3.0.xml
├── AceDBOptions-3.0/
│   ├── AceDBOptions-3.0.lua                     (*)
│   └── AceDBOptions-3.0.xml
├── AceConsole-3.0/
│   ├── AceConsole-3.0.lua                       (*)
│   └── AceConsole-3.0.xml
├── AceConfigRegistry-3.0/
│   ├── AceConfigRegistry-3.0.lua
│   └── AceConfigRegistry-3.0.xml                (*)
├── AceConfig-3.0/
│   ├── AceConfig-3.0.lua
│   └── AceConfig-3.0.xml                        (*)
├── AceConfigCmd-3.0/                            (transitively pulled by AceConfig-3.0.xml)
│   ├── AceConfigCmd-3.0.lua
│   └── AceConfigCmd-3.0.xml
├── AceConfigDialog-3.0/
│   ├── AceConfigDialog-3.0.lua
│   └── AceConfigDialog-3.0.xml                  (*)
├── AceGUI-3.0/
│   ├── AceGUI-3.0.lua
│   ├── AceGUI-3.0.xml                           (*)
│   └── widgets/
│       ├── AceGUIContainer-BlizOptionsGroup.lua
│       ├── AceGUIContainer-DropDownGroup.lua
│       ├── AceGUIContainer-Frame.lua
│       ├── AceGUIContainer-InlineGroup.lua
│       ├── AceGUIContainer-ScrollFrame.lua
│       ├── AceGUIContainer-SimpleGroup.lua
│       ├── AceGUIContainer-TabGroup.lua
│       ├── AceGUIContainer-TreeGroup.lua
│       ├── AceGUIContainer-Window.lua
│       ├── AceGUIWidget-Button.lua
│       ├── AceGUIWidget-CheckBox.lua
│       ├── AceGUIWidget-ColorPicker.lua
│       ├── AceGUIWidget-DropDown.lua
│       ├── AceGUIWidget-DropDown-Items.lua
│       ├── AceGUIWidget-EditBox.lua
│       ├── AceGUIWidget-Heading.lua
│       ├── AceGUIWidget-Icon.lua
│       ├── AceGUIWidget-InteractiveLabel.lua
│       ├── AceGUIWidget-Keybinding.lua
│       ├── AceGUIWidget-Label.lua
│       ├── AceGUIWidget-MultiLineEditBox.lua
│       ├── AceGUIWidget-Slider.lua
│       └── AceGUIWidget-TreeGroup.lua
└── LibSharedMedia-3.0/
    ├── lib.xml                                  (*)
    └── LibSharedMedia-3.0.lua
```

The `(*)` entries are the lines the TOC references at
`KickCD.toc`:

```
libs\LibStub\LibStub.lua
libs\CallbackHandler-1.0\CallbackHandler-1.0.lua
libs\AceAddon-3.0\AceAddon-3.0.lua
libs\AceEvent-3.0\AceEvent-3.0.lua
libs\AceDB-3.0\AceDB-3.0.lua
libs\AceDBOptions-3.0\AceDBOptions-3.0.lua
libs\AceConsole-3.0\AceConsole-3.0.lua
libs\AceConfigRegistry-3.0\AceConfigRegistry-3.0.xml
libs\AceConfig-3.0\AceConfig-3.0.xml
libs\AceConfigDialog-3.0\AceConfigDialog-3.0.xml
libs\AceGUI-3.0\AceGUI-3.0.xml
libs\LibSharedMedia-3.0\lib.xml
```

---

## 4. Verification

From the **repo root** (the folder containing `KickCD.toc`), run:

```bash
find libs -type f \( -name '*.lua' -o -name '*.xml' \) | sort
```

Expected output (paths, not necessarily in this exact line count if the
upstream Ace3 release adds new widgets, but these specific lines must all
be present):

```
libs/AceAddon-3.0/AceAddon-3.0.lua
libs/AceAddon-3.0/AceAddon-3.0.xml
libs/AceConfig-3.0/AceConfig-3.0.lua
libs/AceConfig-3.0/AceConfig-3.0.xml
libs/AceConfigCmd-3.0/AceConfigCmd-3.0.lua
libs/AceConfigCmd-3.0/AceConfigCmd-3.0.xml
libs/AceConfigDialog-3.0/AceConfigDialog-3.0.lua
libs/AceConfigDialog-3.0/AceConfigDialog-3.0.xml
libs/AceConfigRegistry-3.0/AceConfigRegistry-3.0.lua
libs/AceConfigRegistry-3.0/AceConfigRegistry-3.0.xml
libs/AceConsole-3.0/AceConsole-3.0.lua
libs/AceConsole-3.0/AceConsole-3.0.xml
libs/AceDB-3.0/AceDB-3.0.lua
libs/AceDB-3.0/AceDB-3.0.xml
libs/AceDBOptions-3.0/AceDBOptions-3.0.lua
libs/AceDBOptions-3.0/AceDBOptions-3.0.xml
libs/AceEvent-3.0/AceEvent-3.0.lua
libs/AceEvent-3.0/AceEvent-3.0.xml
libs/AceGUI-3.0/AceGUI-3.0.lua
libs/AceGUI-3.0/AceGUI-3.0.xml
libs/AceGUI-3.0/widgets/AceGUIContainer-BlizOptionsGroup.lua
libs/AceGUI-3.0/widgets/AceGUIContainer-DropDownGroup.lua
libs/AceGUI-3.0/widgets/AceGUIContainer-Frame.lua
libs/AceGUI-3.0/widgets/AceGUIContainer-InlineGroup.lua
libs/AceGUI-3.0/widgets/AceGUIContainer-ScrollFrame.lua
libs/AceGUI-3.0/widgets/AceGUIContainer-SimpleGroup.lua
libs/AceGUI-3.0/widgets/AceGUIContainer-TabGroup.lua
libs/AceGUI-3.0/widgets/AceGUIContainer-TreeGroup.lua
libs/AceGUI-3.0/widgets/AceGUIContainer-Window.lua
libs/AceGUI-3.0/widgets/AceGUIWidget-Button.lua
libs/AceGUI-3.0/widgets/AceGUIWidget-CheckBox.lua
libs/AceGUI-3.0/widgets/AceGUIWidget-ColorPicker.lua
libs/AceGUI-3.0/widgets/AceGUIWidget-DropDown-Items.lua
libs/AceGUI-3.0/widgets/AceGUIWidget-DropDown.lua
libs/AceGUI-3.0/widgets/AceGUIWidget-EditBox.lua
libs/AceGUI-3.0/widgets/AceGUIWidget-Heading.lua
libs/AceGUI-3.0/widgets/AceGUIWidget-Icon.lua
libs/AceGUI-3.0/widgets/AceGUIWidget-InteractiveLabel.lua
libs/AceGUI-3.0/widgets/AceGUIWidget-Keybinding.lua
libs/AceGUI-3.0/widgets/AceGUIWidget-Label.lua
libs/AceGUI-3.0/widgets/AceGUIWidget-MultiLineEditBox.lua
libs/AceGUI-3.0/widgets/AceGUIWidget-Slider.lua
libs/AceGUI-3.0/widgets/AceGUIWidget-TreeGroup.lua
libs/CallbackHandler-1.0/CallbackHandler-1.0.lua
libs/CallbackHandler-1.0/CallbackHandler-1.0.xml
libs/LibSharedMedia-3.0/LibSharedMedia-3.0.lua
libs/LibSharedMedia-3.0/lib.xml
libs/LibStub/LibStub.lua
```

Quick sanity check (must each return 1):

```bash
test -f libs/LibStub/LibStub.lua                                && echo 1
test -f libs/CallbackHandler-1.0/CallbackHandler-1.0.lua        && echo 1
test -f libs/AceAddon-3.0/AceAddon-3.0.lua                      && echo 1
test -f libs/AceEvent-3.0/AceEvent-3.0.lua                      && echo 1
test -f libs/AceDB-3.0/AceDB-3.0.lua                            && echo 1
test -f libs/AceDBOptions-3.0/AceDBOptions-3.0.lua              && echo 1
test -f libs/AceConsole-3.0/AceConsole-3.0.lua                  && echo 1
test -f libs/AceConfigRegistry-3.0/AceConfigRegistry-3.0.xml    && echo 1
test -f libs/AceConfig-3.0/AceConfig-3.0.xml                    && echo 1
test -f libs/AceConfigDialog-3.0/AceConfigDialog-3.0.xml        && echo 1
test -f libs/AceGUI-3.0/AceGUI-3.0.xml                          && echo 1
test -f libs/LibSharedMedia-3.0/lib.xml                         && echo 1
```

If you get twelve `1`s, every TOC reference resolves and the addon will
load.

---

## 5. After install

1. Delete this `MANUAL_INSTALL.md` and `STATUS.md` (optional, they don't
   ship in the addon).
2. Update `libs/STATUS.md` from `manual-install required` to `vendored` if
   you want the orchestrator to skip the warning on the next build.
3. Drop the entire `KickCD/` folder into `World of Warcraft/_retail_/Interface/AddOns/`.
4. `/reload` in WoW. The addon should load without "missing file" Lua
   errors.

---

## 6. Why these specific paths?

The TOC was generated in Phase 0 of the build plan
(`docs/EXECUTION_PLAN.md` §3) and is **not modified by Agent A1**. Every
path above is dictated by the TOC; do not rename folders. If you need to
upgrade Ace3 in the future, just overwrite each subfolder with the new
release — the TOC paths will keep working as long as upstream keeps the
folder names (which they have for ~15 years).
