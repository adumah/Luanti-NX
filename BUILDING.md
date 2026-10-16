# Building Luanti for Nintendo Switch

This builds `luanti.nro` and a ready-to-copy SD card folder from source. Everything is
done by one script, `build.sh`; this page covers what you need before running it.

Tested on an Arch-based distribution (x86_64). Other Linux distributions should work through
devkitPro's `dkp-pacman` (see below), but haven't been tested yet.

## What you need

- A Linux PC (x86_64) with an internet connection
- About **1.5 GB** of free disk space (devkitPro ≈ 0.6 GB, this project ≈ 0.5 GB while building)
- **devkitPro** (the Switch homebrew toolchain); see step 2
- Host build tools: `git`, `curl`, `unzip`, `make`, `gcc`, `cmake` (3.19 or newer)

`build.sh` checks for all of these and tells you what's missing.

## 1. Install the host build tools

| Distribution | Command |
|---|---|
| Arch, CachyOS, EndeavourOS, Manjaro | `sudo pacman -S --needed base-devel git cmake curl unzip` |
| Debian, Ubuntu, Linux Mint | `sudo apt install build-essential git cmake curl unzip` |
| Fedora | `sudo dnf install gcc make git cmake curl unzip` |

## 2. Install devkitPro

devkitPro is distributed **only** through its own pacman packages. How you get them
depends on your distribution. The official instructions are here:
<https://devkitpro.org/wiki/devkitPro_pacman>. Follow them; the summary below is
only to show what to expect.

### Arch-based distributions

You use your **normal `pacman`**, with devkitPro's repositories added:

1. Import devkitPro's signing key and install the `devkitpro-keyring` package, exactly as
   described on the official page above.
2. Add devkitPro's repositories at the end of `/etc/pacman.conf`:
   ```ini
   [dkp-libs]
   Server = https://pkg.devkitpro.org/packages

   [dkp-linux]
   Server = https://pkg.devkitpro.org/packages/linux/$arch/
   ```
3. Refresh the package lists: `sudo pacman -Syu`

Note that `pacman -Syu` will now update devkitPro's packages together with your system.

### Other distributions (Debian, Ubuntu, Fedora…)

devkitPro provides **`dkp-pacman`**, a separate copy of pacman that installs next to your
system's package manager without replacing it. On Debian and Ubuntu, devkitPro's wiki
gives this installer:

```sh
wget https://apt.devkitpro.org/install-devkitpro-pacman
chmod +x ./install-devkitpro-pacman
sudo ./install-devkitpro-pacman
```

For other distributions, use the instructions on the official page.

### After installing

Log out and back in (or reboot), so the `DEVKITPRO` environment variable from devkitPro's
`/etc/profile.d/devkit-env.sh` is set. You **don't** need to install any Switch packages
yourself: `build.sh` installs exactly what it needs.

## 3. Build

```sh
git clone https://github.com/adumah/Luanti-NX.git
cd Luanti-NX
./build.sh
```

Run it as your **normal user, not with `sudo`**. It asks for your password itself when it
installs packages or libraries into devkitPro's folder. (Running the whole script with
`sudo` breaks the build, because sudo drops the `DEVKITPRO` variable.)

What `build.sh` does:

1. Installs the needed devkitPro packages (SDL2, Mesa, cURL, OpenAL, FreeType, …)
2. Builds the libraries devkitPro doesn't package (zstd, SQLite, libzip) and installs them
   into devkitPro's Switch folder (only the first time)
3. Builds LuaJIT into `deps/` (only the first time)
4. Downloads Luanti at the tested version and applies the Switch patches from `patches/`
5. Compiles Luanti and packs it into `luanti.nro`
6. Assembles the SD card folder in `dist/`, including Development Test and Minetest Game

The first build takes roughly **10–15 minutes**; later full builds about 5. The result:

```
dist/
└── switch/
    └── luanti/
        ├── luanti.nro
        ├── builtin/  client/  fonts/  textures/
        ├── games/    (devtest, minetest_game)
        ├── mods/
        ├── worlds/
        └── LICENSE, LICENSE-luanti.txt, THIRD-PARTY-NOTICES.md, SOURCE.txt
```

## 4. Install on the Switch

1. Copy the **contents** of `dist/` to the root of the SD card, so you get
   `sdmc:/switch/luanti/`.
2. Start the Homebrew Menu in **application mode**: hold **R** while launching any game.
   (Album/applet mode has too little memory for Luanti.)
3. Launch **Luanti**.

When updating, usually only `luanti.nro` changes. Copy `builtin/` again too if the
release notes say so.

## Rebuilding and updating

- **Rebuild:** run `./build.sh` again. It keeps the downloaded sources and libraries and
  only redoes the Luanti build.
- **Start completely fresh:** delete `luanti/`, `deps/`, `minetest_game/` and `dist/`,
  then run `./build.sh`.
- **Newer Luanti or Minetest Game:** the versions are pinned at the top of `build.sh`
  (`LUANTI_COMMIT`, `MTG_COMMIT`, `LUAJIT_COMMIT`). After changing one, delete the
  matching folder so it's fetched again. A newer Luanti may need the patches in
  `patches/` refreshed; `build.sh` stops with an error if a patch no longer applies.

## Troubleshooting

| Problem | Fix |
|---|---|
| `devkitPro's pacman not found` | devkitPro isn't installed or its repos aren't in `/etc/pacman.conf`; see step 2 |
| `Missing host tools: …` | Install the listed tools (step 1) |
| `DEVKITPRO` not set / compiler not found | Log out and back in after installing devkitPro |
| Files owned by root after running with `sudo` by mistake | `sudo chown -R "$USER":"$USER" Luanti-NX`, then run without sudo |
| `error: patch failed` / `does not apply` | You changed `LUANTI_COMMIT`; the patches need updating for that version |
| Luanti crashes or misbehaves on the Switch | Check `sdmc:/switch/luanti/debug.txt` (add `debug_log_level = info` to `minetest.conf` for more detail), plus `sqlite_log.txt` and `crash.txt` in the same folder if they exist |
