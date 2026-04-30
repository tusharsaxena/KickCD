# Frame mixin pattern

**Never `setmetatable(frame, t)` on a Blizzard widget** — Frame methods (`ClearAllPoints`, `Show`, `SetAlpha`, ...) live on the C-side metatable, and replacing it nils them. Use `Mixin(frame, t)` (Blizzard's global) to copy fields onto the frame without touching the metatable. See `modules/IconGrid.lua` `CreateIconWidget` → `return Mixin(btn, Icon)`.
