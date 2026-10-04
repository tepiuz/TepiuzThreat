# Tepiuz Threat

Tepiuz Threat shows your threat on enemy nameplates and the target frame in World of Warcraft: Forever. It is designed to seamlessly match Blizzard's default UI.

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

## How it works

Threat appears beside an attackable enemy's level badge, moving past crowd-control icons while they are visible. The target frame has a larger label above the portrait. Labels hide when threat data is unavailable; a real 0% stays visible. Both use Blizzard's default frames.

The percentage measures how close you are to pulling aggro. Blizzard's threat mechanic accounts for your distance from the enemy; the addon displays that game-provided value. It can differ from raw threat relative to the tank. A rounded 100% does not guarantee aggro; **AGGRO** means the game reports the enemy is targeting you.

## Options

Open with `/tthreat` or `/tepiuzthreat`, or Settings → AddOns → Tepiuz Threat. Display and styling settings apply to both views; existing visibility settings are preserved.

| Option | Default | Effect |
| --- | --- | --- |
| Only show in combat | On | Hide labels outside combat. |
| Show on nameplates / target frame | Both on | Toggle each location independently. |
| Threat display | Number with % | Whole numbers with `%`, without `%`, or text bands. |
| Color by threat | On | Smooth neutral → yellow (75%) → orange (90%) → red (100%) gradient; white when off. |
| Pop when gaining aggro | Off | Grow by up to 60%, then return to normal over 0.45 seconds when aggro switches to you. |
| Pulse near aggro | Off | Pulse between 30–100% opacity every 0.8 seconds at ≥90% threat; stop below 90% or on aggro. |

Text bands: **No threat** <0.5%, **Low threat** 0.5–<50%, **Medium threat** 50–<80%, **High threat** ≥80%. **AGGRO** overrides all bands. First observations, target changes, and newly attached nameplates establish a baseline without popping.

Forever's restrictions can differ between targets and nameplates. If percentage styling is unavailable, public threat states provide coarser **Low threat / High threat / AGGRO** bands, neutral/Blizzard colors, and a high-threat pulse instead of an exact 90% threshold. Without either styling source, labels fall back to white percentages. The pop is skipped when aggro transitions are restricted.

For troubleshooting, `/tthreat debug` (or `/tepiuzthreat debug`) reports client/addon status, options, nameplate counts, restriction fallbacks, and styling failures without printing threat values.

## License

[MIT](LICENSE)
