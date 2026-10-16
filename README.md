# Luanti-NX

**An unofficial port of [Luanti](https://www.luanti.org/) (formerly Minetest) to the
Nintendo Switch**, as a homebrew app for consoles running custom firmware.

Luanti is a free, open-source voxel game engine. This port runs the full Luanti client on
the Switch, with singleplayer worlds, controller and touch controls, sound, and online
content downloads from ContentDB. It comes with **Development Test** and
**Minetest Game**, and more games (for example Mineclonia or VoxeLibre), mods and
texture packs can be installed from inside the app.

## About this project

**This is an unofficial, independent port. It is not affiliated with the Luanti project,
and it is not a pull request or a proposed contribution to Luanti.** Nothing here is meant
to be merged into the official engine.

**AI disclosure:** I don't have much programming experience, so this port was made with
the help of Claude (or entirely by it). I tested every build on real hardware (Nintendo Switch Lite),
but most of the code changes in `patches/` and `stubs/` were written by the AI.

The Luanti project has a [Generative AI policy](https://github.com/luanti-org/luanti/blob/master/doc/developing/ai_policy.md)
for contributions to the engine, which does not accept "vibe-coded" or largely
AI-generated pull requests. I respect that, which is why this port stays a separate,
self-contained project and will not be submitted to Luanti.

Console ports are something the Luanti team has said they don't have the resources to
work on themselves. As a Luanti team member
[wrote](https://github.com/luanti-org/luanti/issues/12624#issuecomment-1214442746) in the issue about homebrew console ports:
*"Minetest has limited resources. Contributors are welcome to try to port Minetest to
their consoles via homebrew, but this isn't something we should track as an issue."*
This project is one such attempt.

**Please:**
- **Don't report problems with this port to the official Luanti project.** Bugs that only
  happen on the Switch are caused by this port; report them here instead.
- **Use it only if you're comfortable with how it was made.** Nobody has to use this
  project, and I'm not asking anyone to. If you'd rather not use AI/vibe-coded software, that's
  completely your decision.

**If you want to make your own port without AI:** Go ahead! Due to the Switch's hardware
limitations, I'd suggest aiming for a build with full LuaJIT (including its JIT compiler)
if the Switch can support it, since that's where most of the performance is (see below).
You're welcome to use anything from this repository, or nothing at all, whichever you
prefer.

## ⚠️ Performance notice

Performance **may not** be stable: expect smooth moments mixed with stutters, slow chunk
loading at the edge of your view, and occasional lag spikes, especially in big games like
Mineclonia or VoxeLibre. Light games such as Minetest Game and Development Test run
noticeably better. Some games are not updated to the latest Luanti changes, so they may
not run (ask their creators to update them).

The main reason is **LuaJIT**. Almost all game logic in Luanti (mobs, crafting, world
generation, machines) is Lua code. On PC and Android, Luanti runs that code with LuaJIT's
**JIT compiler**, which turns it into fast machine code at runtime. The Switch's system (Horizon OS)
doesn't let programs create executable code that way, so this port uses **LuaJIT
in interpreter-only mode**. That is still faster than standard Lua (mod loading in
VoxeLibre went from 34 s to 25 s), but for heavy games the JIT can be **5–10× faster or
more**, and that is the gap you feel.

Several Switch-specific default settings (shorter view range, smaller map chunks, fewer
active mobs) are already applied to keep the game playable.

### Overclocking

Overclocking the CPU, e.g. with [sys-clk](https://github.com/retronx-team/sys-clk),
**does help a bit**: the Lua interpreter runs on the CPU, so a faster CPU (stock is
1020 MHz; overclocks go up to about 1785 MHz) makes it proportionally faster, at most
around 1.75×. It **won't remove the lag**, though. It can't make up for the missing JIT
compiler, and parts of the slowdown (SD card access, generating new terrain) don't scale
with the clock.

> **⚠️ Overclocking is entirely at your own risk.** It increases heat, power draw and
> battery drain, and can cause instability or damage to your console. **Luanti-NX and its
> author are not responsible for any damage to your console, SD card or data** caused by
> overclocking or by using overclocking tools. Luanti-NX doesn't overclock anything
> itself, and it works without overclocking.

### Want to help? Bring the JIT to the Switch

Getting LuaJIT's JIT compiler working on Horizon would be the single biggest performance
improvement for this port. The technical starting point: libnx provides a JIT API that
gives two views of the same memory (one writable, one executable), while LuaJIT's machine
code allocator (`src/lj_mcode.c`) expects to write and run code at the same address, and
patches code in place later. Bridging that is the work.

**Anyone is welcome to use this repository as a base for that.** The build already
compiles LuaJIT for the Switch (see `build.sh`, step 3c, and `BUILDING.md`); switching
from `-DLUAJIT_DISABLE_JIT` to a working JIT is the missing piece. Pull requests and forks
are welcome.

## Features

- Luanti 5.18.0-dev client with singleplayer worlds
- **Controller support** with a crosshair for digging and placing, plus touch controls
- **Controller pointer in menus** (move with the left stick, click with A)
- **Switch system keyboard** for text fields
- **Sound and music**
- **ContentDB**: browse, install, update and delete games, mods and texture packs online
- Texture packs, minimap, screenshots
- **LuaJIT** (interpreter mode) and performance settings tuned for the Switch
- **Shaders / Optional visual effects** (post-processing, e.g. bloom): off by default,
  enable them in **Settings → Graphics and Audio → Effects**. They work, but expect lower
  and less stable performance with them turned on.
- Bundled games: Development Test and Minetest Game

## Requirements

- A Nintendo Switch (any model, including Lite) running custom firmware
  ([Atmosphère](https://github.com/Atmosphere-NX/Atmosphere)) with the Homebrew Menu
- An internet connection only if you want to use ContentDB

## Installation

1. Download the latest release zip from the [Releases page](https://github.com/adumah/Luanti-NX/releases)
   (or [build it yourself](BUILDING.md)).
2. Extract it to the **root of your SD card**, so you get `sdmc:/switch/luanti/`.
3. Launch the Homebrew Menu in **application mode**: hold **R** while starting any game.
   Album/applet mode has too little memory for Luanti.
4. Start **Luanti-NX**.

**Updating:** replace `switch/luanti/luanti.nro`. If a release says so, also replace the
`builtin` folder. Your worlds, settings and installed content are kept.

## Controls

**In game**

| Button | Action |
|---|---|
| Left stick | Move |
| Right stick | Look around |
| ZR | Dig / punch |
| ZL | Place / use |
| B | Jump |
| A | Sneak |
| Y | Run (Aux1) |
| X | Inventory |
| L / R | Previous / next hotbar item |
| + | Pause menu |
| − | Minimap |
| D-pad Up | Zoom |
| D-pad Down | Drop item |
| D-pad Right | Screenshot |
| R3 (press right stick) | Change camera view |

**In menus**

| Button | Action |
|---|---|
| Left stick | Move the pointer |
| A | Click |
| Y | Right click (take half a stack, place one item) |
| Right stick | Scroll |
| Touch screen | Works everywhere, and hides the pointer |

Tapping or clicking a text field opens the Switch keyboard. Controls can be changed in
**Settings → Controls**.

## Tips

- **Big games** like Mineclonia and VoxeLibre load slowly the first time (a few minutes),
  because their files are copied into the cache once. Later starts are faster.
- **Map chunk size** for new worlds is reduced for smoother loading. It only applies to
  worlds created with this version.
- **Settings in `minetest.conf` override the Switch defaults.** If something behaves
  oddly after an update, remove the matching line from `sdmc:/switch/luanti/minetest.conf`.
- **Overclocking** helps a bit; see the performance notice above. **At your own risk:
  we are not responsible for any damage to your console.**

## Known issues

- Performance varies, especially in heavy games (see the performance notice).
- In VoxeLibre, mobs can fly further than normal when punched while the game lags. That
  comes from how VoxeLibre slows mobs down, and is not a bug in this port.
- Online multiplayer is untested.

## Reporting problems

Please report problems in this repository's
[Issues](https://github.com/adumah/Luanti-NX/issues), **not to the Luanti project**.
Include:

- What you did and what happened
- The end of `sdmc:/switch/luanti/debug.txt` (for more detail, add
  `debug_log_level = info` to `sdmc:/switch/luanti/minetest.conf` and try again)
- `crash.txt` and `sqlite_log.txt` from the same folder, if they exist

## Building from source

See **[BUILDING.md](BUILDING.md)**. In short: install devkitPro, then run `./build.sh`.
All Switch-specific changes to Luanti are in [`patches/`](patches/) and
[`stubs/`](stubs/).

## Credits and licence

- **Luanti** by the Luanti contributors: <https://github.com/luanti-org/luanti>
- **Minetest Game** by the Luanti contributors
- **devkitPro** and **libnx** for the Switch homebrew toolchain
- Performance defaults inspired by the [PortMaster](https://portmaster.games/) Luanti port
  and Luanti's own Android settings
- Made with the help of Claude (Anthropic); see
  *About this project* above

Luanti-NX is licensed under the **GNU Lesser General Public License v2.1 or later**, like
Luanti itself (see [`LICENSE`](LICENSE)). The release includes many third-party
components with their own licences; see [`THIRD-PARTY-NOTICES.md`](THIRD-PARTY-NOTICES.md).

Luanti-NX is not affiliated with or endorsed by the Luanti project or Nintendo.
"Nintendo Switch" is a trademark of Nintendo.
