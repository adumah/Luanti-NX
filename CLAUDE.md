# Project: Luanti port to Nintendo Switch (Horizon OS homebrew)

Cross-compiles the Luanti client (5.18.0-dev) into a Switch `.nro` for consoles running
custom firmware (Atmosphère), launched from hbmenu. `build.sh`, `stubs/` and `patches/`
are the source of truth; everything else is fetched or generated.
(Minecraft LCE / Java ports were ruled out: leaked-source or closed-source. Don't revisit.)

## Status (2026-10-15)
Playable on hardware: main menu, singleplayer worlds (Development Test,
Minetest Game, Mineclonia, VoxeLibre), controller + touch, menu pointer, system keyboard,
sound, ContentDB browse/install/delete, texture packs, minimap, screenshots.
Performance: LuaJIT interpreter (VoxeLibre mod load 34.1 s -> 25.3 s), PortMaster/Android
performance defaults. Remaining: publish on GitHub (README, licence notices, release zip),
then optionally LuaJIT's JIT compiler (step 2, see below).

## Environment
- Repository: https://github.com/adumah/Luanti-NX
- Host: Linux x86_64. If the interactive shell isn't bash, run bash syntax via
  `bash -c '...'` (or write scripts to files).
- devkitPro via its pacman repo in /etc/pacman.conf; use normal `pacman` (not dkp-pacman).
  Sysroot: `/opt/devkitpro/portlibs/switch`. devkitA64 GCC 16.1; `aarch64-none-elf-cmake`
  applies the Switch toolchain and defines `__SWITCH__`.
- Run `./build.sh` as a normal user (it calls sudo only for pacman / sysroot installs;
  `sudo` drops `$DEVKITPRO`, so never compile under sudo).

## Layout
- `README.md` (project name **Luanti-NX**, author **Adumah**; AI disclosure + "not a
  Luanti PR" section citing Luanti's AI policy and rubenwardy's homebrew-ports comment in
  luanti-org/luanti#12624; performance notice; controls), `LICENSE` (LGPL-2.1, = Luanti's
  COPYING.LESSER), `THIRD-PARTY-NOTICES.md`. build.sh step 8 copies LICENSE,
  THIRD-PARTY-NOTICES.md, Luanti's LICENSE.txt (as LICENSE-luanti.txt) and a generated
  SOURCE.txt (pinned commits) into dist/; NACP title "Luanti-NX", author "Adumah".
- `BUILDING.md`: user-facing build guide (host tools, devkitPro via pacman repos on Arch or
  dkp-pacman elsewhere, running build.sh, installing, troubleshooting). Keep it in sync
  with build.sh. build.sh picks `dkp-pacman` if present, else `pacman` with devkitPro's
  repos, skips sudo when run as root, and checks host tools first.
- `build.sh`: whole build; idempotent. Steps: packages, zstd/SQLite/libzip into the sysroot
  (sudo), LuaJIT into `deps/luajit` (no sudo), fetch Luanti at `LUANTI_COMMIT`, apply
  `patches/*.patch` (name order, skipped when `git apply -R --check` passes), configure,
  build, package `dist/switch/luanti/` (NRO + builtin, client, fonts, textures, devtest,
  Minetest Game at `MTG_COMMIT`).
- `stubs/`: `endian.h`, `switch_compat.h` (C++), `sys/utsname.h` are force-included /
  on the include path via CFLAGS/CXXFLAGS env vars (CMake appends them to the toolchain
  flags). `switch_shim.c` + `switch_terminate.cpp` are compiled by build.sh and added to
  the luanti target by `switch.cmake` (via `-DCMAKE_PROJECT_luanti_INCLUDE`, deferred
  `target_sources`). `switch_getentropy.c` goes into libluajit.a.
- Generated / fetched (gitignored): `luanti/`, `luanti/build-switch/`, `minetest_game/`,
  `deps/`, `dist/`, `stubs/*.o`, `.work/` (scratch: pristine clones for making patches).

## Incremental rebuild (don't re-run build.sh while iterating; it wipes build-switch)
`cd luanti && DEVKITPRO=/opt/devkitpro PATH=/opt/devkitpro/devkitA64/bin:/opt/devkitpro/portlibs/switch/bin:/opt/devkitpro/tools/bin:$PATH cmake --build build-switch -j$(nproc) > build.log 2>&1`
then `elf2nro build-switch/bin/luanti.elf build-switch/luanti.nro --nacp=build-switch/luanti.nacp --icon=/opt/devkitpro/libnx/default_icon.jpg`.
After editing a stub, rebuild its .o with `$NX_CFLAGS` (see build.sh); switch.cmake makes
the .o a dependency, so luanti relinks. Changing switch_compat.h rebuilds everything.

## Making / changing a patch
Work in a pristine clone (`.work/clean`: `git clone luanti .work/clean`), apply the earlier
patches the file depends on if needed, edit, `git diff -- <files> > patches/<name>.patch`.
Then verify the whole sequence on a fresh clone (apply all, then `git apply -R --check`
all) and `git apply` the new patch to `luanti/`. Patches apply in name order and several
touch src/filesys.cpp in different places.

## Horizon rules learned (each caused a real bug)
- **No second handle on a file open for writing**; libnx `stat()` opens the file, so stat
  of an open-for-write file fails. Open files can't be deleted. (Hit by: /dev/null temp
  file, SQLite journal creation, debug.txt from other code, menu music blocking game delete.)
- **Reads starting past EOF fail** (libnx -> EIO; SQLite reports "malformed").
- **rename() won't overwrite** an existing file.
- **Paths are `device:/...`**: anything assuming absolute == leading '/' or ':' as a list
  separator breaks (SQLite full pathnames, IsPathAbsolute, PATH_DELIM/texture_path).
- newlib gaps: no endian.h, utsname, libdl, /dev/urandom, iconv impl, `_getentropy_r`;
  `mkdtemp()` is an ENOSYS stub; `BUFSIZ` is 1 KiB; no fcntl locks.
- Every FS call is an IPC round trip and FAT dir lookups are linear: avoid per-file
  stat storms and huge flat directories.
- SDL2's Switch port opens the inline keyboard inside `SDL_StartTextInput()`, draws no
  mouse cursor, and plays audio for OpenAL Soft (SDL2 backend).
- Anything compiled by hand must use `$NX_CFLAGS` (incl. `-fPIE`), else the link fails with
  "read-only segment has dynamic relocations" (`-z text`).
- Never put objects/libs in LDFLAGS / CMAKE_EXE_LINKER_FLAGS: they reach CMake's configure
  test programs, which then fail and silently cache wrong results (FindZstd unsets
  ZSTD_LIBRARY). The toolchain FORCE-sets CMAKE_CXX_STANDARD_LIBRARIES.

## What each piece does
**build.sh configure flags**: GLES2 (sysroot has libGLESv2.a only), RUN_IN_PLACE,
LuaJIT/cURL/sound on, gettext/leveldb/redis/postgres/server/tests off,
`-DENABLE_OPENSSL=OFF` (libzip's config reads ENABLE_OPENSSL and collided with Luanti's
option on CMake re-runs), explicit library paths, and
`-DFREETYPE_LIBRARY=freetype;harfbuzz;freetype;bz2;png;z` (FreeType's CMake config sets no
FREETYPE_LIBRARY). cURL 7.69 uses libnx's ssl service (system CAs, no mbedtls).

**LuaJIT (build.sh 3c)**: 2.1 at `LUAJIT_COMMIT`, `TARGET_SYS=Other`, `-D__NX__` (LuaJIT's
own console target), `-DLUAJIT_DISABLE_JIT` (no W+X memory), `-DLUAJIT_DISABLE_FFI`,
`-DLUAJIT_USE_SYSMALLOC`. `switch_getentropy.c` (randomGet) inside the archive so CMake's
`luaopen_string_buffer` link check passes too.

**stubs/switch_shim.c**: fchown/geteuid (SQLite), failing posix_spawnp, UTF-8<->UTF-32LE
iconv, `null:` devoptab device (replaces /dev/null), `switch_keyboard_show` (libnx swkbd),
and `userAppInit`: sockets + nxlinkStdio, `TMPDIR=/switch/luanti/tmp` (wiped at start),
default SQLite VFS "switch" = "unix-none" (no locks) with device-path-aware
xFullPathname, EOF-clamped xRead and a stat() that treats "busy" as existing; SQLite
error log -> `sdmc:/switch/luanti/sqlite_log.txt`.
**stubs/switch_terminate.cpp**: uncaught exceptions -> `sdmc:/switch/luanti/crash.txt`.

**patches/**
- `switch-portability.patch`: serialize.h uses the endian stub; s_security.cpp uses
  `null:/`; filesys.cpp removes the target before rename() and treats `device:/` as
  absolute (VoxeLibre/Mineclonia schematics were blocked as "./sdmc:/..."); socket.cpp
  logs+ignores poll() errors on sockets closed during shutdown; porting.cpp
  secure_rand_fill_buf uses randomGet (else "Couldn't create salted SRP verifier");
  game.cpp logs "Server start failed: <what>"; CMakeLists: no -ldl, accept CMake 4's
  `OpenAL_FOUND`.
- `switch-defaults.patch` (end of set_default_settings, so it overrides): touch_controls
  off (else no crosshair), D-pad Left no longer fly, R3 (SDL 8) = camera. Performance
  from the PortMaster port (chunksize=1 for new worlds, viewing_range=60,
  active_block_range=2, emergequeue_limit_total=64, no fog/3D clouds/raytraced culling,
  performance_tradeoffs, mcl_mob_cap_total=250) and Luanti's Android block
  (sqlite_synchronous=1, server_map_save_interval=15, max_block_generate_distance=5,
  emergequeue diskonly/generate=32, block sends=20, simple leaves, no post-processing,
  client_mapblock_limit=2200; PortMaster's 100 made the client re-request visible chunks).
  Tried and reverted on hardware: run on L3 (awkward), emergequeue_limit_total=128 +
  block sends 60 + mesh_generation_threads=2 (worse: competes with the game for CPU).
  GAMEPAD_BUTTON_n = SDL controller IDs: 2 west, 4 Back/minus, 7 L3, 8 R3, 13 D-pad Left.
- `switch-gamepad-pointer.patch` (irr/src): in menus the left stick moves a drawn arrow,
  A = left click, Y = right click, right stick = wheel; withheld from the game, whose
  stick axes are zeroed when a menu opens. B is not Escape (Esc on the main menu quits).
- `switch-keyboard.patch`: never start SDL text input (reopen loop); edit-box clicks open
  swkbd via GUIModalMenu::preprocessEvent (like Android); Enter for enter-after-edit fields.
- `switch-tempdir-extract.patch`: CreateTempDir() makes MT_<random hex> with mkdir
  (mkdtemp is ENOSYS -> every ContentDB install failed); logs silent extract failures.
- `switch-path-delim.patch`: PATH_DELIM ";" (filesys.h + builtin pkgmgr.lua) and
  PLATFORM "Switch". Changes builtin/, so SD cards need the new builtin folder.
- `switch-sound-delete.patch`: sounds decoded from memory (open .ogg blocked deleting
  games); RecursiveDelete lists before deleting and names the failing entry.
- `switch-texture-lookup.patch`: texture-pack lookups from cached folder listings.
- `switch-media-cache.patch`: 256 KiB copies (first VoxeLibre start took >9 min copying
  5358 media files) and cache/media/<2 hex>/ subfolders.
- `switch-jit-opt.patch`: no-op `jit.opt.start` (VoxeLibre/Mineclonia call it whenever
  `jit` exists; interpreter-only LuaJIT has no jit.opt).

## Testing on hardware
Copy `dist/` to the SD root (or only what changed: usually just the .nro; builtin/ when a
patch touches it). Launch from hbmenu in application mode (hold R on a game). Logs on the
SD card: `switch/luanti/debug.txt` (set `debug_log_level = info` in minetest.conf for
detail), `sqlite_log.txt`, `crash.txt`. Settings in minetest.conf override the defaults.

## Possible next work
- GitHub: README (build, install, controls, licences), THIRD-PARTY notices, release zip.
- LuaJIT JIT (step 2): needs libnx's JIT API (separate RW and RX views) in lj_mcode.c;
  LuaJIT writes and patches code at the address it runs from. Uncertain.
- VoxeLibre's mob knockback slows by a fixed 0.7 per server step (not dtime-scaled), so
  knocked mobs fly further when the server lags: upstream VoxeLibre issue, not ours.

## Reference (read-only)
`github.com/emmauss/minetest` and `github.com/emmauss/irrlicht`: an old (~2021) Switch
fork. Mine ideas with `grep -rn "__SWITCH__" .`, don't copy files.
PortMaster's Luanti port (PortsMaster/PortMaster-New, ports/minetest): source of the
performance defaults.

## Working style
Keep Switch changes as `stubs/` shims or `patches/` files (never hand-edit `luanti/`
without a matching patch), so a fresh clone builds with one command. The user tests on
hardware and pastes debug.txt; find the first real error and give the exact fix.
