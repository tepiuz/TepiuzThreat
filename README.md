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

- Show threat to the left, top, right, or bottom of enemy nameplates and independently around the target frame.
- Choose a percentage, a number, or **Low threat**, **High threat**, and **AGGRO**.
- Use matching threat colors on both displays, or keep the text white.
- Enable an optional pulse at High threat and a brief pop when you gain aggro.
- In the right-side position, threat text moves past visible crowd-control icons.

## Options

Open with `/tthreat` or `/tepiuzthreat`, or Settings → AddOns → Tepiuz Threat.

Threat labels automatically hide when threat data is unavailable.

| Option | Default | Effect |
| --- | --- | --- |
| Show threat | While in a party or raid | Any location while grouped; In dungeons or raids (even solo); or Always, whether solo or grouped. |
| Show on nameplates / target frame | Both on | Choose where threat appears. |
| Nameplate text position | Right | Left, top, right, or bottom. Top clears the unit name; bottom clears a visible cast bar. |
| Target frame text position | Right | Left, top, right, or bottom of the target frame, independently of nameplates. Top and bottom exclude invisible frame padding. |
| Threat display | Percentage | Percentage (65%), Number (65), or Text (Low threat, High threat, AGGRO). |
| Larger text | Off | Double the threat text size on nameplates and the target frame. |
| Color by threat | On | Neutral for Low threat, yellow for High threat, red for AGGRO. Turn off for white text. |
| Pop when gaining aggro | Off | Briefly enlarge the text when you gain aggro. |
| Pulse near aggro | Off | Pulse at High threat until it drops or you gain aggro. |

## License

[MIT](LICENSE)
