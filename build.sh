#!/usr/bin/env bash
# Cross-compile the Luanti client for Nintendo Switch (Horizon OS) with devkitPro.
# Needs devkitPro's pacman: the system pacman with devkitPro's repos (Arch-based
# distros) or dkp-pacman (other distros). See BUILDING.md.
# Run as a normal user; it calls sudo itself only for package/library installs.
set -euo pipefail

export DEVKITPRO=/opt/devkitpro
export PATH="$DEVKITPRO/portlibs/switch/bin:$DEVKITPRO/devkitA64/bin:$PATH"
SYSROOT="$DEVKITPRO/portlibs/switch"
JOBS="$(nproc)"
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
# Flags the devkitPro CMake toolchain uses, for things compiled by hand below.
# -fPIE is required: the NRO is linked as PIE with -z text.
NX_CFLAGS="-O2 -fPIE -march=armv8-a+crc+crypto -mtune=cortex-a57 -mtp=soft -ftls-model=local-exec -ffunction-sections -fdata-sections -D__SWITCH__"

# Tested upstream versions. The patches in patches/ are made against LUANTI_COMMIT;
# updating it may require refreshing them. Delete ./luanti or ./minetest_game to
# re-fetch after changing a commit.
LUANTI_COMMIT=0e1414682e4be3ffb84d067d0621e98d6bf5cd76
MTG_COMMIT=c42e4d0c0ff9d27ff7b9b308c3cfc14098dd3a0f

# Adjust if the SQLite URL is out of date (see https://www.sqlite.org/download.html)
SQLITE_URL="https://www.sqlite.org/2025/sqlite-amalgamation-3490100.zip"

# --- Host checks --------------------------------------------------------------
# devkitPro packages come only through pacman: dkp-pacman on most distros, or the
# system pacman with devkitPro's repos added to /etc/pacman.conf on Arch-based ones.
if command -v dkp-pacman >/dev/null 2>&1; then
  PACMAN=dkp-pacman
elif command -v pacman >/dev/null 2>&1 && grep -qi devkitpro /etc/pacman.conf 2>/dev/null; then
  PACMAN=pacman
else
  echo "devkitPro's pacman not found: install dkp-pacman, or add devkitPro's repos" \
       "to /etc/pacman.conf on Arch-based distros. See BUILDING.md." >&2
  exit 1
fi
# Root (e.g. in a container) doesn't need sudo.
if [ "$(id -u)" -eq 0 ]; then SUDO=""; else SUDO="sudo"; fi
missing=""
for tool in git curl unzip make gcc cmake; do
  command -v "$tool" >/dev/null 2>&1 || missing="$missing $tool"
done
if [ -n "$missing" ]; then
  echo "Missing host tools:$missing (install them with your distro's package manager)" >&2
  exit 1
fi

# 1) devkitPro packages (pacman aborts if any name is missing: only list real ones;
#    switch-zstd / switch-sqlite / switch-luajit don't exist, so those are built below)
$SUDO $PACMAN -S --needed \
  switch-dev switch-sdl2 switch-mesa switch-zlib \
  switch-libpng switch-libjpeg-turbo switch-freetype switch-harfbuzz \
  switch-curl switch-openal-soft switch-libogg switch-libvorbis

# 2) zstd: build into the Switch sysroot if no package exists
if [ ! -f "$SYSROOT/lib/libzstd.a" ]; then
  echo ">> Building zstd for Switch"
  rm -rf /tmp/zstd-nx
  git clone --depth 1 https://github.com/facebook/zstd.git /tmp/zstd-nx
  aarch64-none-elf-cmake -S /tmp/zstd-nx/build/cmake -B /tmp/zstd-nx/build \
    -DZSTD_BUILD_PROGRAMS=OFF -DZSTD_BUILD_SHARED=OFF -DZSTD_BUILD_TESTS=OFF \
    -DCMAKE_INSTALL_PREFIX="$SYSROOT"
  cmake --build /tmp/zstd-nx/build -j"$JOBS"
  $SUDO cmake --install /tmp/zstd-nx/build
fi

# 3) SQLite: build the amalgamation as a static lib if no package exists
if [ ! -f "$SYSROOT/lib/libsqlite3.a" ]; then
  echo ">> Building SQLite for Switch"
  rm -rf /tmp/sqlite-nx && mkdir /tmp/sqlite-nx && cd /tmp/sqlite-nx
  curl -L -o sqlite.zip "$SQLITE_URL"
  unzip -q sqlite.zip
  cd sqlite-amalgamation-*
  # devkitA64's newlib has no <sys/ioctl.h>, which SQLite's unix VFS includes.
  # Provide an empty stub header, and turn off features that need mmap/shared memory.
  mkdir -p stubs/sys && : > stubs/sys/ioctl.h
  # shellcheck disable=SC2086
  aarch64-none-elf-gcc $NX_CFLAGS -Istubs \
    -DSQLITE_OMIT_LOAD_EXTENSION -DSQLITE_THREADSAFE=1 \
    -DSQLITE_OMIT_WAL -DSQLITE_MAX_MMAP_SIZE=0 -DSQLITE_OMIT_SHARED_CACHE \
    -c sqlite3.c -o sqlite3.o
  aarch64-none-elf-ar rcs libsqlite3.a sqlite3.o
  $SUDO cp libsqlite3.a "$SYSROOT/lib/"
  $SUDO cp sqlite3.h "$SYSROOT/include/"
  cd - >/dev/null
fi

# 3b) libzip (Luanti needs >= 1.7.2): use a devkitPro package if one exists,
#     otherwise build it from source into the Switch sysroot
if [ ! -f "$SYSROOT/lib/libzip.a" ]; then
  if $PACMAN -Si switch-libzip >/dev/null 2>&1; then
    $SUDO $PACMAN -S --needed switch-libzip
  else
    echo ">> Building libzip for Switch"
    rm -rf /tmp/libzip-nx
    git clone --depth 1 --branch v1.11.3 https://github.com/nih-at/libzip.git /tmp/libzip-nx
    aarch64-none-elf-cmake -S /tmp/libzip-nx -B /tmp/libzip-nx/build \
      -DBUILD_SHARED_LIBS=OFF -DBUILD_TOOLS=OFF -DBUILD_REGRESS=OFF \
      -DBUILD_EXAMPLES=OFF -DBUILD_DOC=OFF -DBUILD_OSSFUZZ=OFF \
      -DENABLE_BZIP2=OFF -DENABLE_LZMA=OFF -DENABLE_ZSTD=OFF \
      -DENABLE_OPENSSL=OFF -DENABLE_GNUTLS=OFF -DENABLE_MBEDTLS=OFF \
      -DENABLE_COMMONCRYPTO=OFF -DENABLE_WINDOWS_CRYPTO=OFF \
      -DCMAKE_INSTALL_PREFIX="$SYSROOT"
    # Compile as your normal user (sudo drops $DEVKITPRO, which the compiler needs),
    # then only use sudo for the file copy.
    cmake --build /tmp/libzip-nx/build --target zip -j"$JOBS"
    $SUDO cmake --install /tmp/libzip-nx/build
  fi
fi

# 3c) LuaJIT 2.1, interpreter only (no JIT: Horizon doesn't allow writable +
#     executable memory the normal way) and no FFI (unused by Luanti; its callbacks
#     generate machine code). Uses LuaJIT's console target __NX__ (no tmpfile etc.)
#     and the system allocator. Built into the project-local deps/ (no sudo).
#     Pinned to a tested commit; bump LUAJIT_COMMIT and delete deps/luajit to update.
LUAJIT_COMMIT=2a8e017ef1ece6a95b983ffca073d30609dce7c4
LUAJIT_DIR="$PROJECT_DIR/deps/luajit"
if [ ! -f "$LUAJIT_DIR/lib/libluajit-5.1.a" ]; then
  echo ">> Building LuaJIT for Switch"
  rm -rf /tmp/luajit-nx && mkdir /tmp/luajit-nx
  git -C /tmp/luajit-nx init -q
  git -C /tmp/luajit-nx fetch -q --depth 1 https://github.com/LuaJIT/LuaJIT.git "$LUAJIT_COMMIT"
  git -C /tmp/luajit-nx checkout -q FETCH_HEAD
  make -C /tmp/luajit-nx/src -j"$JOBS" HOST_CC=gcc CROSS=aarch64-none-elf- \
    TARGET_SYS=Other BUILDMODE=static TARGET_CFLAGS="$NX_CFLAGS" \
    XCFLAGS="-D__NX__ -DLUAJIT_DISABLE_JIT -DLUAJIT_DISABLE_FFI -DLUAJIT_USE_SYSMALLOC" \
    libluajit.a
  # LuaJIT seeds its PRNG with getentropy(); provide newlib's missing backend
  # inside the archive so every link of LuaJIT (incl. CMake's checks) works.
  # shellcheck disable=SC2086
  aarch64-none-elf-gcc $NX_CFLAGS -c "$PROJECT_DIR/stubs/switch_getentropy.c" \
    -o /tmp/luajit-nx/src/switch_getentropy.o
  aarch64-none-elf-ar rs /tmp/luajit-nx/src/libluajit.a /tmp/luajit-nx/src/switch_getentropy.o
  rm -rf "$LUAJIT_DIR" && mkdir -p "$LUAJIT_DIR/lib" "$LUAJIT_DIR/include/luajit-2.1"
  cp /tmp/luajit-nx/src/libluajit.a "$LUAJIT_DIR/lib/libluajit-5.1.a"
  (cd /tmp/luajit-nx/src && cp lua.h lualib.h lauxlib.h luaconf.h lua.hpp luajit.h \
    "$LUAJIT_DIR/include/luajit-2.1/")
fi

# 4) Pick the graphics backend based on what switch-mesa actually installed
GL_FLAGS=""
if ls "$SYSROOT"/lib/libGL.a >/dev/null 2>&1; then
  GL_FLAGS="-DENABLE_OPENGL=OFF -DENABLE_OPENGL3=ON -DENABLE_GLES2=OFF"
elif ls "$SYSROOT"/lib/libGLESv2.a >/dev/null 2>&1; then
  GL_FLAGS="-DENABLE_OPENGL=OFF -DENABLE_OPENGL3=OFF -DENABLE_GLES2=ON"
else
  echo "No GL/GLES library found in $SYSROOT/lib - check: pacman -Ql switch-mesa" >&2
  exit 1
fi
echo ">> Graphics flags: $GL_FLAGS"

# 5) Get the source (run from the directory containing this script)
cd "$(dirname "$0")"

# Compat headers in stubs/ (force-included via CFLAGS/CXXFLAGS below):
#   endian.h       byte-order macros + be32toh etc. (newlib has no <endian.h>)
#   switch_compat.h no-op thread-priority calls, randomGet/switch_keyboard_show decls
#   sys/utsname.h  minimal uname() (Luanti only prints OS info with it)
STUBS="$PWD/stubs"
SHIM="$STUBS/endian.h"
COMPAT="$STUBS/switch_compat.h"

# CMake appends these env vars to the toolchain's own flags (it doesn't replace them)
export CFLAGS="-I$STUBS -I$SYSROOT/include/freetype2 -include $SHIM"
export CXXFLAGS="-I$STUBS -I$SYSROOT/include/freetype2 -include $SHIM -include $COMPAT"
# Link-time shims (iconv, fchown/geteuid, posix_spawnp, null: device, SQLite VFS,
# libnx init hooks, terminate handler). Linked via stubs/switch.cmake.
# shellcheck disable=SC2086
aarch64-none-elf-gcc $NX_CFLAGS -I"$DEVKITPRO/libnx/include" -I"$SYSROOT/include" \
  -c "$STUBS/switch_shim.c" -o "$STUBS/switch_shim.o"
# shellcheck disable=SC2086
aarch64-none-elf-g++ $NX_CFLAGS -c "$STUBS/switch_terminate.cpp" -o "$STUBS/switch_terminate.o"

PATCHES="$PWD/patches"
fetch_commit() { # <url> <commit> <dir>
  mkdir -p "$3"
  git -C "$3" init -q
  git -C "$3" fetch -q --depth 1 "$1" "$2"
  git -C "$3" checkout -q FETCH_HEAD
}
[ -d luanti ] || fetch_commit https://github.com/luanti-org/luanti.git "$LUANTI_COMMIT" luanti
cd luanti

# Larger Switch changes live as patch files in patches/ (applied once; skipped
# if already applied):
#   switch-portability.patch: small Horizon fixes (endian.h, null: device instead
#     of /dev/null, rename() over existing files, device-prefixed absolute paths,
#     poll() on closed sockets, libnx randomGet, server start error logging,
#     no -ldl, CMake 4 FindOpenAL).
#   switch-jit-opt.patch: no-op jit.opt for the interpreter-only LuaJIT (VoxeLibre).
#   switch-gamepad-pointer.patch: controller-driven mouse pointer in menus.
#   switch-keyboard.patch: system keyboard for text fields (no reopen loop).
#   switch-tempdir-extract.patch: mkdtemp() fix + logging for ContentDB installs.
#   switch-path-delim.patch: ';' separates path lists (texture_path...) since
#     Switch paths contain "sdmc:"; PLATFORM = "Switch".
#   switch-defaults.patch: Switch defaults (controller-first, PortMaster-style
#     performance settings).
#   switch-sound-delete.patch: sounds decoded from memory (no open .ogg handles)
#     and a Switch RecursiveDelete that names the failing entry.
#   switch-texture-lookup.patch: texture/texture-pack lookups answered from cached
#     folder listings instead of thousands of slow file-exists checks.
#   switch-media-cache.patch: 256 KiB file copies (newlib BUFSIZ is 1 KiB) and
#     the media cache split into 256 subfolders (FAT lookups are linear).
for p in "$PATCHES"/*.patch; do
  [ -e "$p" ] || continue
  if git apply -R --check "$p" 2>/dev/null; then
    echo ">> Patch already applied: $(basename "$p")"
  else
    git apply "$p"
  fi
done

# 6) Configure. aarch64-none-elf-cmake is devkitPro's wrapper that applies the
#    Switch toolchain file. libzip is found through its own CMake config.
rm -rf build-switch
# shellcheck disable=SC2086
aarch64-none-elf-cmake -S . -B build-switch \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_CLIENT=ON \
  -DBUILD_SERVER=OFF \
  -DBUILD_UNITTESTS=OFF \
  -DBUILD_BENCHMARKS=OFF \
  -DBUILD_DOCUMENTATION=OFF \
  -DRUN_IN_PLACE=ON \
  -DCUSTOM_SHAREDIR=share \
  -DCUSTOM_BINDIR=bin \
  -DCUSTOM_DOCDIR=doc \
  -DEXAMPLE_CONF_DIR=doc \
  -DHAVE_ENDIAN_H=1 \
  -DENABLE_LUAJIT=ON \
  -DLUA_LIBRARY="$LUAJIT_DIR/lib/libluajit-5.1.a" \
  -DLUA_INCLUDE_DIR="$LUAJIT_DIR/include/luajit-2.1" \
  -DENABLE_CURL=ON \
  -DENABLE_SOUND=ON \
  -DENABLE_GETTEXT=OFF \
  -DENABLE_LEVELDB=OFF \
  -DENABLE_REDIS=OFF \
  -DENABLE_POSTGRESQL=OFF \
  -DENABLE_OPENSSL=OFF \
  -DZLIB_LIBRARY="$SYSROOT/lib/libz.a" \
  -DZLIB_INCLUDE_DIR="$SYSROOT/include" \
  -DZSTD_LIBRARY="$SYSROOT/lib/libzstd.a" \
  -DZSTD_INCLUDE_DIR="$SYSROOT/include" \
  -DSQLITE3_LIBRARY="$SYSROOT/lib/libsqlite3.a" \
  -DSQLITE3_INCLUDE_DIR="$SYSROOT/include" \
  -DCURL_LIBRARY="$SYSROOT/lib/libcurl.a" \
  -DCURL_INCLUDE_DIR="$SYSROOT/include" \
  -DOPENAL_LIBRARY="$SYSROOT/lib/libopenal.a" \
  -DOPENAL_INCLUDE_DIR="$SYSROOT/include/AL" \
  -DOGG_LIBRARY="$SYSROOT/lib/libogg.a" \
  -DOGG_INCLUDE_DIR="$SYSROOT/include" \
  -DVORBIS_LIBRARY="$SYSROOT/lib/libvorbis.a" \
  -DVORBISFILE_LIBRARY="$SYSROOT/lib/libvorbisfile.a" \
  -DVORBIS_INCLUDE_DIR="$SYSROOT/include" \
  -DCMAKE_PROJECT_luanti_INCLUDE="$STUBS/switch.cmake" \
  -DFREETYPE_LIBRARY="$SYSROOT/lib/libfreetype.a;$SYSROOT/lib/libharfbuzz.a;$SYSROOT/lib/libfreetype.a;$SYSROOT/lib/libbz2.a;$SYSROOT/lib/libpng.a;$SYSROOT/lib/libz.a" \
  $GL_FLAGS

# 7) Build
cmake --build build-switch -j"$JOBS" 2>&1 | tee build.log

# 8) Package: ELF -> NRO, plus an SD-card tree. With RUN_IN_PLACE, Luanti can't
#    find its executable on Horizon and falls back to the cwd, which libnx sets
#    to the NRO's folder, so the data dirs sit next to the NRO.
export PATH="$DEVKITPRO/tools/bin:$PATH"
nacptool --create "Luanti-NX" "Adumah" "5.18.0-dev" build-switch/luanti.nacp
elf2nro build-switch/bin/luanti.elf build-switch/luanti.nro \
  --nacp=build-switch/luanti.nacp --icon="$DEVKITPRO/libnx/default_icon.jpg"
DIST="$PWD/../dist/switch/luanti"
rm -rf "$PWD/../dist"
mkdir -p "$DIST/games" "$DIST/mods" "$DIST/worlds"
cp build-switch/luanti.nro "$DIST/"
cp -r builtin client fonts textures "$DIST/"
cp -r games/devtest "$DIST/games/"
# Bundle Minetest Game (LGPL-2.1 code, CC BY-SA 3.0 media) next to devtest,
# fetched once at MTG_COMMIT into the project folder.
MTG="$PWD/../minetest_game"
[ -d "$MTG" ] || fetch_commit https://github.com/luanti-org/minetest_game.git "$MTG_COMMIT" "$MTG"
cp -r "$MTG" "$DIST/games/minetest_game"
rm -rf "$DIST/games/minetest_game/.git" "$DIST/games/minetest_game/.github"
# Licence notices and the exact source versions (LGPL: source must be obtainable)
cp "$PROJECT_DIR/LICENSE" "$PROJECT_DIR/THIRD-PARTY-NOTICES.md" "$DIST/"
cp LICENSE.txt "$DIST/LICENSE-luanti.txt"
cat > "$DIST/SOURCE.txt" <<SOURCE
Luanti-NX: Luanti for Nintendo Switch (unofficial port by Adumah).
Source and build script: https://github.com/adumah/Luanti-NX
The Switch changes are in patches/ and stubs/ of that repository.

Luanti:        https://github.com/luanti-org/luanti        commit $LUANTI_COMMIT
Minetest Game: https://github.com/luanti-org/minetest_game commit $MTG_COMMIT
LuaJIT:        https://github.com/LuaJIT/LuaJIT            commit $LUAJIT_COMMIT
SOURCE
echo ">> Copy the contents of $(realpath "$PWD/../dist") to the SD card root"
echo ">> Or test over Wi-Fi: nxlink -s -a <switch-ip> $DIST/luanti.nro  (data dirs must already be on SD)"
