# ShaguDPS Details

Extension for [ShaguDPS](https://github.com/shagu/ShaguDPS) (WoW 1.12): detailed breakdown per spell and per target.

## What it shows
For every spell or ability of a player:
- number of hits
- average and maximum
- crit rate
- distribution across targets

## Usage
- Click a bar in the ShaguDPS window to open the details for that player.
- `/sdd` opens the window directly.

## How it works
ShaguDPS only stores the total per spell. This addon keeps the extra data alongside without modifying ShaguDPS itself. It hooks `parser.AddData` and checks the raw combat log message against the crit patterns beforehand. Updating ShaguDPS therefore overwrites nothing.

Font size and opacity are taken from `ShaguDPS_UI` if installed.

## Requirements
ShaguDPS

## Saved data
`ShaguDPS_Detail_Config` (per character)
