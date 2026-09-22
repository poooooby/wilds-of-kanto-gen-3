# 🌿 Wilds of Kanto Revival
![Total Downloads](https://img.shields.io/github/downloads/poooooby/wilds-of-kanto-gen-3/total)
[![License](https://img.shields.io/badge/license-Modified%20MIT-blue)](https://github.com/poooooby/wilds-of-kanto-gen-3/blob/main/LICENSE)
![Latest release](https://img.shields.io/github/v/release/poooooby/wilds-of-kanto-gen-3)
![Release date](https://img.shields.io/github/release-date/poooooby/wilds-of-kanto-gen-3)

**Wilds of Kanto Revival continues to make Kanto feel alive in
[Gen1Recomp](https://github.com/bryanthaboi/gen1recomp).**

> [!NOTE]
> **Fork notice:** this is [poooooby](https://github.com/poooooby)'s fork of
> [YoDrehDenSwagAuf/overworld-spawn-mod](https://github.com/YoDrehDenSwagAuf/overworld-spawn-mod)
> ("Wilds of Kanto"), forked after upstream v2.2.0. Full credit for the
> original mod goes to YoDrehDenSwagAuf and the collaborators listed below.
> See [CHANGELOG.md](CHANGELOG.md) for exactly what changed and when.
> WoK Revival uses new mod id `wilds_of_kanto_gen3`.
> If another mod referenced `overworld_wilds_spawns`, it will need
> to add this mod's id for compatibility.


## 🪄 Features of WoK Revival:

- **Massive performance upgrade**
  - Drops file count from 10k+ to <300. Reduces size by over 50% from 45MB+ to ~20MB 
    while also adding over 1000 new sprites.
- Overworld and follower sprites for all 1025 species with dex expansion mods.
- Updated overworld Pokémon with idle, roam, chase, and hidden behaviours
- Optional hand authored spawn tables for national dex
- Random spawn mode + Legendary / Mythic spawn option
- Included shiny system that carries over to other shiny mods.
- Optional overworld Poké Ball catching
- Updated party follow system
- Updated Water Pokémon (swimming sprites, silhouettes, or classic encounters)
- Town / ambient Pokémon
- New Cave spawn logic so overworld mon stay only where you can reach them.
- Sprite art styles: Poké Followers / GSC or HGSS / PokeMMO
  - **Full** species support with HGSS style (1025 + regional forms)
  - 416 **new** GSC sprites (667 total) spanning multiple dex generation.
    (GSC falls back to HGSS when a sprite is not available)
  - *PMDCollab overworld sprites temporarily removed due to voxel sizing bug*
- PMDCollab dialogue portraits for Wilds Pokémon talk (followers, town Pokémon,
  generic cries) — independent of the selected overworld Sprite Style
- Red / Blue / Yellow, plus experimental Pokémon G/S/C (beta)
- Safari compatibility
- Stable species-based sprite identity (reordered Pokédex / Fakemon mods keep
  the correct Wilds art, or the missing-sprite fallback)

> [!TIP]
> Extended Dex recommendations:
> - [Kanto Reforged](https://github.com/1Jamie/Kanto-Reforged) - Up to Gen 3 species
>   OR
> - [G1R National Dex](https://github.com/sanjinpepic/gen1recomp-national-dex) - National Dex framework
>   + [Gen9 Dex](https://github.com/tectorifter/Gen9Dex) - National dex **combat**
>   + [G9 Battle Sprites](https://github.com/tectorifter/g9-battle-sprites/) - National dex combat **sprites**
>   + (Optional) [G9 Battle Forms](https://github.com/sanjinpepic/gen1recomp-battle-forms) - Mega, Dynamax, etc in **battle**


## 🟨 Pokémon Gold / Gen 2 Support (Beta)

WoK Revival includes experimental support for Pokémon Gold through Gen1Recomp's
Gen 2 compatibility layer.

- **Gen 1:** Red / Blue / Yellow
- **Gen 2:** Pokémon Gold (**beta**)

> [!IMPORTANT]
> Pokémon Gold support is currently in beta. The core systems are working.
> Please report anything that behaves differently from Gen1.
> If reporting a Gen2 issue, include Pokémon Gold, map / location, sprite style,
> follower count / control mode if relevant, Voxel mod if enabled, and
> reproduction steps.


## 📥 Installation

1. Install the latest release of this fork from
   [GitHub Releases](https://github.com/poooooby/wilds-of-kanto-gen-3/releases)
   (or the original, unforked mod from
   [YoDrehDenSwagAuf/overworld-spawn-mod](https://github.com/YoDrehDenSwagAuf/overworld-spawn-mod/releases) —
   NOT BOTH.)
   Use the packed `wilds-of-kanto-v*.zip` (manifest.json at the archive root).
   Do not import the GitHub "Source code" / `overworld-spawn-mod-main` ZIP.
2. Import via the Mod Manager in launcher, or place the mod in your Gen1Recomp mods directory.
3. Enable **Wilds of Kanto Revival**.

## 🔧 Settings

Open from the pause menu:

```text
START → OPTIONS → Wilds of Kanto Revival
```
### 🎨 Sprite Styles

| Setting | Values | Default | Description |
|---------|--------|---------|-------------|
| Sprite Style | Poke Followers / GSC · HGSS / PokeMMO | Poke Followers / GSC | Overworld sprite style for wilds and followers. GSC uses Classic (16×16); HGSS uses True Size. Dialogue portraits are separate (always PMDCollab for supported Wilds Pokémon talk). |
| Pika Follower | Multiple | Default | For Yellow only. 12 optional Pikachu Follower sprites to choose from, including caps and cosplay. |
| Sprite Scale | On / Off | On | Optional display-size tuning for HGSS / PokeMMO under Voxel renderers. Off renders every species at native True Size instead. |
| Sprite Fade | Solid / Faded | Solid | Opacity of normal wild sprites (Solid = fully opaque). Does not affect followers, Town Pokémon, silhouettes, or UI. |

### 🐕‍🦺 Followers

| Setting | Values | Default | Description |
|---------|--------|---------|-------------|
| Control Mode | Trainer / Pokémon | Trainer | Who you control in the overworld. |
| Trainer Trail | On / Off | Off | When controlling a Pokémon, the trainer follows behind. |
| Followers | 0–6 | 1 | Extra party Pokémon trailing the leader. |
| Leader | Party menu | — | Choose the lead follower from the party menu. |

### 🐅 Wild Pokémon

| Setting | Values | Default | Description |
|---------|--------|---------|-------------|
| Show Wild Mons | On / Off | On | Spawn visible wild Pokémon in eligible areas. |
| Spawn Amount | Low / Normal / High / Very High | Normal | How many visible overworld Pokémon can appear (including water). |
| Random Enc | On / Off | On | Classic step-based random encounters. Visible overworld Pokémon stay active. |
| Water Mons | Swim Sprites / Hid Silhouette / Silhouettes / Classic Enc / Disabled | Swim Sprites | How water Pokémon appear. |
| Cave Spawns | Reachable Only / Mixed | Reachable Only | Cave spawn reachability filter. Mixed allows ~20% atmospheric scenery in inaccessible pockets. |
| Modern Spawns | Off / Spawn Table / Random | Off | Use the default spawns, a hand authored spawn table with national dex entries, or randomize spawns. |
| Legend / Mythic | Off / On | Off | Include Legendaries / Mythics into the spawn pool when Modern Spawns is set to Random. |
| Shiny Rate | Off, %s, Always | Off | Adds shiny rolls into the spawn pool |
| Shiny Sparkle | Off / On | Off | Shiny Pokemon play a short jingle and one-time sparkle effect in battle. |
| Max Gen | All - Gen 1-9 | Gen 1 | Cap the max generation of pokemon that will spawn |
| Town Pokémon | On / Off | On | Peaceful ambient Pokémon in safe towns and interiors. |
| Grass View | Above / Immersed | Immersed | Draw wilds fully above tall grass, or partially hidden inside it. |
| Silhouette | Off / Undiscovered / All | Off | Off keeps normal colours. Undiscovered silhouettes species not yet caught / registered in the Pokédex. All silhouettes every encounter-zone wild. |
| Idle Mons | On / Off | On | Allow idle look behaviour. |
| Roam Mons | On / Off | On | Allow wander behaviour. |
| Chase Mons | On / Off | On | Allow aggressive chase behaviour. |
| Hidden Mons | On / Off | On | Allow hidden grass / cave markers. |

### 🤾 Overworld Catching

| Setting | Values | Default | Description |
|---------|--------|---------|-------------|
| OW Catch | On / Off | On | Direct Poké Ball throws at visible wild Pokémon. |
| Catch Key | C / V / F / G / R / T | C | Desktop key that charges and throws. |
| Ball Switch | Q / E / R / F / G / T | Q | Desktop key that cycles Balls. |
| Catch Combo | B + A / Select + A / Disabled | B + A | Controller/touch charge-and-throw combo. |
| Switch Combo | B + Left/Right / Select + Left/Right / Disabled | B + Left/Right | Controller/touch Ball-switch combo. |
| Catch HUD Size | 0–10 | 5 | Size of the Ball HUD. 0 hides the HUD only; catching stays on. |

Hold Catch Key (or Catch Combo) to charge 1–6 tiles, release to throw.
Throws only hit battleable wilds directly ahead. A miss still consumes a Ball.
Failed catches make the Pokémon aggressive through the normal `!` → chase →
battle flow. Safari sessions disable overworld throws.

### 🧑‍💻 Developer

| Setting | Values | Default | Description |
|---------|--------|---------|-------------|
| Dev Overlay | On / Off | Off | Show behaviour and facing labels above wild Pokémon. |

## 🧬 Encounter Behaviors

| Behavior | Description |
|----------|-------------|
| **Idle** | Pokémon stands around and looks about. |
| **Wander** | Pokémon moves within its area. |
| **Aggressive** | Pokémon notices the trainer, reacts, and chases. |
| **Hidden** | Pokémon stays hidden or is shown only via its marker. |
| **Safari Flee** | Safari Zone only — Pokémon flees after being noticed. |


## 🔗 Compatibility

- Pokémon Red
- Pokémon Blue
- Pokémon Yellow
- Pokémon Gold (beta)
- **Kanto Reforged** (Gen 3 species extension) — this fork's Gen 3 species
  support (species IDs 252–386, spawning, and sprites) is tested against
  [Kanto Reforged](https://github.com/1Jamie/Kanto-Reforged).
- **Full National Dex** (Pokédex expansion through Gen 9) — this fork's national dex
  support (251-1025) is tested against [Gen1Recomp National Dex](https://github.com/sanjinpepic/gen1recomp-national-dex)
- **Shiny Pokemon** (`SHINY_POKEMON`) — The original [Shiny Pokemon](https://github.com/masterwebx/gen1recomp-shiny-pokemon)
  mod conflicted with updated spawns, now declared a **conflict**, use the built-in.
- Voxel Mods: Battle Art (Gen 1+2), Potato (Gen 1), Dramaless Shape (Gen 1), and Terrarium (Gen 1) via public
  `SpriteBillboards`.

## 🤝 Collaborators

This fork:

- [poooooby](https://github.com/poooooby) — fork maintainer
- [PokeWilds](https://github.com/sheerst/pokewilds#overworld-sprites) - Additional GSC overworld sprites
  Major thanks to the sprite artists for their work (Full credits linked)
- [Gen 9 Resource Pack](https://eeveeexpo.com/resources/1101/)
  Huge thanks to these sprite artists for their work!
  - **Gen 1-5 Pokemon Overworlds:** MissingLukey, help-14, Kymoyonian, cSc-A7X,
  2and2makes5, Pokegirl4ever, Fernandojl, Silver-Skies, TyranitarDark, Getsuei-H,
  Kid1513, Milomilotic11, Kyt666, kdiamo11, Chocosrawlooid, Syledude, Gallanty,
  Gizamimi-Pichu, 2and2makes5, Zyon17,LarryTurbo, spritesstealer, LarryTurbo
  - **Gen 6 Pokemon Overworlds:** princess-pheonix, LunarDusk, Wolfang62, TintjeMadelintje101, piphybuilder88
  - **Gen 7 Pokemon Overworlds:** Larry Turbo, princess-pheonix
  - **Gen 8 Pokemon Overworlds:** SageDeoxys, Wolfang62, LarryTurbo, tammyclaydon
  - **PLA Pokemon Overworlds:** Boonzeet, DarkusShadow, princess-phoenix, Ezeart, WolfPP
  - **Gen 9 Pokemon Overworlds:** Azria, DarkusShadow, EduarPokeN, Carmanekko, StarWolff, Caruban
  - **PLZA Pokemon Overworlds:** DarkusShadow
- **Pokemon Tower Ghost:** Nuclear-Blizzard (DeviantArt)
- [masterwebx](https://github.com/masterwebx) (WEX): author of the
  [**Shiny Pokemon**](https://github.com/masterwebx/gen1recomp-shiny-pokemon)
  mod (MIT). This fork's **SHINY RATE** and **SHINY SPARKLE** options
  incorporate that mod's ideas: rolling real shiny DVs on wild Pokémon at a
  configurable rate and the one-time battle sparkle and chime that waits for
  the intro to finish. They were reimplemented here (`lib/shiny.lua`, `lib/shiny_sparkle.lua`)
  rather than copied; thank you, masterwebx, for the design and the original mod!

Original project ([YoDrehDenSwagAuf/overworld-spawn-mod](https://github.com/YoDrehDenSwagAuf/overworld-spawn-mod)) collaborators — full credit for
everything through v2.2.0:

- [YoDrehDenSwagAuf](https://github.com/YoDrehDenSwagAuf) — Wilds of Kanto /
  overworld systems / integration
- [masterwebx](https://github.com/masterwebx) (WEX) — Followers EX / follower
  systems
- [TheRhysWyrill](https://github.com/TheRhysWyrill) (TRW) — PokéPC / follower
  selection / integration / Poke Followers / GSC - Sprites
- **ShockSlayer / Crystal Clear team** — for the GSC-style Pokémon sprite work that the Poké Followers / GSC presentation is based on
- [gamecorner-033](https://github.com/gamecorner-033) — Original PokéPC / Overworld Catching inspiration / overworld follower concepts and related work
- [PMDCollab / SpriteCollab](https://github.com/PMDCollab/SpriteCollab) (CC BY-NC 4.0) —
  Mystery Dungeon–style dialogue portraits (talk portraits). Shoutout to
  that repo and its contributors.

Full license and attribution:
[THIRD_PARTY_ASSETS.md](THIRD_PARTY_ASSETS.md) and
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).


### Release history

[CHANGELOG.md](CHANGELOG.md).

### Developer documentation (outdated)

- [docs/DEVELOPER_GUIDE.md](docs/DEVELOPER_GUIDE.md)
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
