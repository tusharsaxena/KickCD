-- tests/test_vendor_sync.lua — the vendored-payload gate, delegated.
--
-- The ~150 lines that used to live here were a copy of the same gate in six
-- repos with a one-line delta (`local T = _G.KICKCD_TEST` versus `_G.AT_TEST`).
-- Six copies is six chances to fix one problem six different ways, and that is
-- exactly what happened: every copy carried a bare `return` on the missing-
-- sibling path, which registers as PASS, so six green gates reported "checked,
-- fine" for a comparison that never ran. The gate now lives once, in the
-- payload it checks, at `tests/_kit/vendor_sync.lua`. See its header for what
-- it compares and why it compares against the TAG rather than the working
-- tree; see `docs/api/testkit/version-13-docs.md` in LibKa0s for the contract.
--
-- ONE NORMALIZATION, AND ONLY ONE — carried in verbatim, because it is the one
-- thing a reader must not have to infer. `git show` hands back the stored blob,
-- which is LF, while the working tree is CRLF because `.gitattributes` pins
-- `* text=auto eol=crlf`. CR is stripped from the working-tree side so the file
-- is compared to the blob it round-trips to. Nothing else is normalized — a
-- real fork in content still fails. A vendored copy differing from the blob
-- ONLY in line endings PASSES; one differing by a single content byte FAILS.
-- That is the intended split: line endings are decided per checkout by
-- `.gitattributes`, so treating them as a content fork would redden this gate
-- for a fact about the checkout rather than about the bytes.
--
-- The case names below are the consumer's, not the kit's, which is why
-- `register` is a factory rather than auto-registration: swapping the
-- hand-copied gate for this one must not move docs/test-cases.md's counts.

local T = _G.KICKCD_TEST
local ROOT = T.root or "."
local VendorSync = dofile(ROOT .. "/tests/_kit/vendor_sync.lua")

VendorSync.register(T, { root = ROOT })
