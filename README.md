# Tepiuz Threat

Shows your threat percentage on enemy nameplates and the target frame in World of Warcraft: Forever.

The number is how close you are to pulling the enemy. At 100% you are the target, or you are at the point of becoming it. It is scaled by distance, so it can differ from a raw "percent of the tank's threat" number shown by other addons.

## Requirements

- World of Warcraft: Forever
- Interface 16001 (game version 1.60.1)

## Installation

The CurseForge app installs the Forever file into the right client folder.

To install a release zip yourself, exit the game and extract it so the addon folder sits here:

```text
World of Warcraft/_classic_beta_/Interface/AddOns/TepiuzThreat/TepiuzThreat.toc
```

The folder name has to be `TepiuzThreat`. Start the game, enable Tepiuz Threat on the AddOns screen, and turn on enemy nameplates.

## Usage

Attackable nameplates show a whole-number percentage just past the level badge. When crowd-control effect icons appear beside the badge, the percentage moves past the whole icon group and returns when they disappear. The target frame shows a larger percentage centered above the portrait. The label hides when that enemy has no threat data for you. A real 0% stays visible.

`/tthreat` prints a short status line: client version, whether the addon is running, how many nameplates it is tracking, and whether a lookup failed. It does not print threat numbers. `/tepiuzthreat` does the same thing.

The options are under Settings → AddOns → Tepiuz Threat. All three start on: only show the percentage in combat, show it on nameplates, and show it on the target frame.

## What this version does not do

This version is intentionally small.

- No colors, bars, or icons
- No friendly units
- Default Blizzard nameplates and the default target frame only

## License

[MIT](LICENSE)
