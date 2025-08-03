# Gen 9 Move Update for Pokémon Essentials v19.1

This repository provides an update package for Pokémon fangames built using **Pokémon Essentials v19.1**, introducing Gen 9 moves, learnsets, forms, and battle mechanics.

> This is intended for developers using the outdated v19.1 version of Essentials. If you're working on a newer version, this patch may not be compatible.

## Features

- Fixes to incorrect move IDs from older versions.
- 80+ new Gen 9 moves fully implemented.
- Updated Pokémon learnsets that:
  - Fetch all moves learned from Gen 1 to Gen 9 using data from POKEAPI (partially incomplete gen 9 learnset coverage).
  - Avoid repeated moves.
- Added Tatsugiri and its forms.
- Added Paldean Tauros and its forms.
- Added Ogerpon and its forms.
- Added Bloodmoon Ursaluna, Hisuian Braviary, Hisuian Sliggoo, Hisuian Avalugg, Hisuian Lilligant and the Hisuian starters as alternative evolutions to their previous forms (check 010_Data/001_Hardcoded data/007_Evolution.rb)
- Added Urshifu's scrolls as evolution stone
- Implemented the Commander ability with AI coverage.
- Implemented the abilities Of Ruin, Toxic Chain, Good as Gold, Toxic Debris, Thermal Exchange, Mind's Eye, Armor Tail, Guard Dog, Supreme Overlord, Well-Baked Body, Protosynthesis and Quark Drive with no AI coverage.
- Added Booster Energy.
- Hail mechanics changed to Snow, as per Gen 9.

## Installation

1. Download or clone this repository.
2. Copy all files into their respective folders in your existing Pokémon Essentials v19.1 project.
3. Overwrite any files when prompted.
4. Test in-game to ensure proper integration.

## Notes

- This update is meant to modernize older projects without forcing a complete engine upgrade.
- Some mechanics may need manual tweaking depending on your existing custom scripts.
- It is highly recommended to back up your project before applying changes.
