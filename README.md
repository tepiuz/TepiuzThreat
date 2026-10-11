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

## Features

- Show threat beside enemy nameplates and above the target portrait.
- Choose a percentage, a number, or **Low threat**, **High threat**, and **AGGRO**.
- Use matching threat colors on both displays, or keep the text white.
- Enable an optional pulse at High threat and a brief pop when you gain aggro.
- Keep crowd-control icons readable, with threat text positioned beside them.

## Options

Open with `/tthreat` or `/tepiuzthreat`, or Settings → AddOns → Tepiuz Threat.

| Option | Default | Effect |
| --- | --- | --- |
| Only show in combat | On | Hide threat outside combat. |
| Show on nameplates / target frame | Both on | Choose where threat appears. |
| Threat display | Number with % | Show a percentage, a number only, or threat text. |
| Color by threat | On | Neutral for Low threat, yellow for High threat, red for AGGRO. Turn off for white text. |
| Pop when gaining aggro | Off | Briefly enlarge the text when you gain aggro. |
| Pulse near aggro | Off | Pulse at High threat until it drops or you gain aggro. |

## License

[MIT](LICENSE)
