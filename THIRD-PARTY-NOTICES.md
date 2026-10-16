# Third-party notices

Luanti-NX's own files (`build.sh`, `stubs/`, `patches/`, documentation) are licensed under
the **GNU Lesser General Public License v2.1 or later** (see `LICENSE`), the same as Luanti.

The `luanti.nro` built by this project is a single static program that contains the
components below. Each keeps its own licence; full texts are in the respective projects.

## Luanti and its bundled code

| Component | Licence |
|---|---|
| [Luanti](https://github.com/luanti-org/luanti) engine source | LGPL-2.1-or-later |
| Luanti media (textures, sounds), fonts, Irrlicht, JThread, Lua | See Luanti's `LICENSE.txt`, shipped as `LICENSE-luanti.txt` (CC BY-SA 3.0/4.0, CC BY 4.0, Apache 2.0, SIL OFL 1.1, zlib, MIT) |
| mini-gmp (bundled in Luanti) | LGPL-3.0-or-later or GPL-2.0-or-later (dual) |
| JsonCpp (bundled in Luanti) | Public domain / MIT |
| tiniergltf (bundled in Luanti) | MIT |
| SHA-256 code (bundled in Luanti) | OpenSSL licence |

## Libraries linked into the NRO

| Library | Licence | Source |
|---|---|---|
| [LuaJIT](https://luajit.org/) | MIT | built by `build.sh` |
| [libnx](https://github.com/switchbrew/libnx) | ISC | devkitPro |
| [SDL2](https://www.libsdl.org/) | zlib | devkitPro (`switch-sdl2`) |
| [Mesa](https://www.mesa3d.org/) | MIT | devkitPro (`switch-mesa`) |
| [OpenAL Soft](https://openal-soft.org/) | LGPL-2.0-or-later | devkitPro (`switch-openal-soft`) |
| [libogg](https://xiph.org/ogg/), [libvorbis](https://xiph.org/vorbis/) | BSD-3-Clause | devkitPro |
| [cURL](https://curl.se/) | curl licence (MIT-style) | devkitPro (`switch-curl`) |
| [FreeType](https://freetype.org/) | FreeType Licence (FTL) | devkitPro (`switch-freetype`) |
| [HarfBuzz](https://harfbuzz.github.io/) | MIT ("Old MIT") | devkitPro (`switch-harfbuzz`) |
| [libpng](http://www.libpng.org/) | libpng licence | devkitPro |
| [libjpeg-turbo](https://libjpeg-turbo.org/) | IJG + BSD-3-Clause + zlib | devkitPro |
| [zlib](https://zlib.net/) | zlib | devkitPro |
| [bzip2](https://sourceware.org/bzip2/) | bzip2 licence (BSD-style) | devkitPro |
| [zstd](https://github.com/facebook/zstd) | BSD-3-Clause (or GPL-2.0, dual) | built by `build.sh` |
| [SQLite](https://sqlite.org/) | Public domain | built by `build.sh` |
| [libzip](https://libzip.org/) | BSD-3-Clause | built by `build.sh` |

This software is based in part on the work of the Independent JPEG Group.
The FreeType Project is copyright © The FreeType Project (www.freetype.org). All rights reserved.

## LGPL components

Luanti and OpenAL Soft are LGPL-licensed and statically linked. Everything needed to
rebuild the NRO, including with modified versions of those components, is in this
repository: `build.sh` fetches the exact source versions listed in `SOURCE.txt` (included
in each release) and the Switch changes are in `patches/` and `stubs/`.

## Bundled games

| Game | Licence |
|---|---|
| Development Test (part of Luanti) | See its folder and Luanti's `LICENSE.txt` |
| [Minetest Game](https://github.com/luanti-org/minetest_game) | Code LGPL-2.1-or-later, media CC BY-SA 3.0; see `games/minetest_game/LICENSE.txt` |
