# Development notes

This file and `tests/` are excluded from release packages.

## Threat display

Query each enemy independently using its own unit token. Nameplates must work without a selected target; never copy the target's threat onto other enemies.

`UnitDetailedThreatSituation("player", unit)` supplies the scaled percentage in its third return. Pass restricted percentages directly to `SetFormattedText`; do not compare, calculate with, or evaluate curves on them. Addon curve evaluation rejected these inputs on Forever 1.60.1 (build 70338), although numeric display worked.

`UnitThreatSituation("player", unit)` supplies the separate state. Validate it with `issecretvalue` before interpreting it. Use the same mapping everywhere: 0 → Low/neutral, 1 → High/yellow/pulse, 2–3 → AGGRO/red. This is the normal presentation, not a fallback for percentage bands. Derive aggro transitions from this same state.

Preserve the selected mode and color preference. Missing percentages hide the label; missing states hide text or enabled colors. White numeric displays can work without a state. Do not substitute numbers for text or invent zero for missing data. Unavailable animations leave the main display steady.

Keep the saved `colorGradient` key for compatibility, although colors now change by state. Reset aggro baselines on target changes and reused nameplates. Do not read restricted widget text, opacity, or animation progress back into Lua.

## Verification and releases

Run `lua tests/threat_display.lua` from the repository root with Lua 5.1; the suite also supports newer Lua versions. Mocks cover display modes, restricted inputs, multiple enemies, alerts, saved options, and frame lifecycle. They do not replace in-game testing of client restrictions.

Before releasing, check text and numeric modes, target switching with multiple enemies, both alerts, and missing threat data in game. Run `git diff --check` and review the player-facing README and changelog.

The release workflow extracts the changelog section matching the tag without its `v` prefix. The packager replaces `@project-version@` in the TOC. Pushing a release tag publishes to GitHub, CurseForge, and Wago; preparing files locally does not publish them.
