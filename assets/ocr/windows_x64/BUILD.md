# Rebuilding the bundled Windows `tesseract.exe`

This executable is cross-compiled on Linux with MinGW-w64 (GCC 13, POSIX threads)
and linked statically. It imports only `KERNEL32.dll` and `msvcrt.dll`, both of
which ship with every Windows install, so it needs no Visual C++ redistributable
and no other DLLs. It is Tesseract 5.4.1 with Leptonica 1.84.1, the same versions
as the Linux bundle, and like the Linux build Leptonica reads PNG and JPEG only
(TIFF, GIF, WebP and JPEG 2000 are left out).

The English language data is not duplicated here. `windows/CMakeLists.txt`
installs `assets/ocr/linux_x64/tessdata/eng.traineddata`, which is platform
independent, next to this executable.

## Rebuild

On Debian/Ubuntu-family Linux, install the toolchain, then run the script below
(it downloads and checksum-verifies each pinned source archive):

```bash
sudo apt-get install -y build-essential cmake curl mingw-w64
bash build-windows-tesseract.sh "$PWD/tesseract-build"
cp tesseract-build/tesseract.exe assets/ocr/windows_x64/tesseract.exe
```

`build-windows-tesseract.sh`:

```bash
#!/usr/bin/env bash
# Cross-builds a static Windows x64 tesseract.exe on Linux with mingw-w64.
# Usage: build-windows-tesseract.sh WORKDIR   (result: WORKDIR/tesseract.exe)
set -euo pipefail

work=$(mkdir -p "${1:?usage: $0 WORKDIR}" && cd "$1" && pwd)
out="$work/out"
export OUT="$out"
mkdir -p "$work/src" "$out/lib" "$out/include"
cd "$work"

fetch() { # name url sha256
  [[ -f "src/$1" ]] || curl -fsSL -o "src/$1" "$2"
  echo "$3  src/$1" | sha256sum -c -
  tar -xf "src/$1" -C "$work"
}
fetch zlib-1.3.1.tar.gz https://github.com/madler/zlib/releases/download/v1.3.1/zlib-1.3.1.tar.gz \
  9a93b2b7dfdac77ceba5a558a580e74667dd6fede4585b91eefb60f03b72df23
fetch libpng-1.6.43.tar.gz https://github.com/pnggroup/libpng/archive/refs/tags/v1.6.43.tar.gz \
  fecc95b46cf05e8e3fc8a414750e0ba5aad00d89e9fdf175e94ff041caf1a03a
fetch libjpeg-turbo-3.0.3.tar.gz https://github.com/libjpeg-turbo/libjpeg-turbo/releases/download/3.0.3/libjpeg-turbo-3.0.3.tar.gz \
  343e789069fc7afbcdfe44dbba7dbbf45afa98a15150e079a38e60e44578865d
fetch leptonica-1.84.1.tar.gz https://github.com/DanBloomberg/leptonica/releases/download/1.84.1/leptonica-1.84.1.tar.gz \
  2b3e1254b1cca381e77c819b59ca99774ff43530209b9aeb511e1d46588a64f6
fetch tesseract-5.4.1.tar.gz https://github.com/tesseract-ocr/tesseract/archive/refs/tags/5.4.1.tar.gz \
  c4bc2a81c12a472f445b7c2fb4705a08bd643ef467f51ec84f0e148bd368051b

# The "-posix" compilers provide std::thread, which Tesseract needs.
cat > toolchain.cmake <<'TOOLCHAIN'
set(CMAKE_SYSTEM_NAME Windows)
set(CMAKE_SYSTEM_PROCESSOR x86_64)
set(CMAKE_C_COMPILER x86_64-w64-mingw32-gcc-posix)
set(CMAKE_CXX_COMPILER x86_64-w64-mingw32-g++-posix)
set(CMAKE_RC_COMPILER x86_64-w64-mingw32-windres)
set(CMAKE_FIND_ROOT_PATH "$ENV{OUT}")
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
TOOLCHAIN
# Keep the build directory out of the assert/log strings compiled into the exe.
pathmap="-ffile-prefix-map=$work=/build"
common=(-G "Unix Makefiles" -DCMAKE_TOOLCHAIN_FILE="$work/toolchain.cmake"
        -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$out"
        -DCMAKE_C_FLAGS="$pathmap" -DCMAKE_CXX_FLAGS="$pathmap")

# zlib
(cd zlib-1.3.1 &&
  make -f win32/Makefile.gcc PREFIX=x86_64-w64-mingw32- CC=x86_64-w64-mingw32-gcc-posix \
    SHARED_MODE=0 LOC="$pathmap" libz.a -j"$(nproc)" &&
  cp zlib.h zconf.h "$out/include/" && cp libz.a "$out/lib/")

# libpng
cmake -S libpng-1.6.43 -B build-png "${common[@]}" -DPNG_SHARED=OFF -DPNG_STATIC=ON \
  -DPNG_TESTS=OFF -DPNG_TOOLS=OFF -DZLIB_INCLUDE_DIR="$out/include" -DZLIB_LIBRARY="$out/lib/libz.a"
cmake --build build-png -j"$(nproc)" && cmake --install build-png

# libjpeg-turbo (no NASM needed: SIMD is off, which only slows JPEG decoding slightly)
cmake -S libjpeg-turbo-3.0.3 -B build-jpeg "${common[@]}" -DENABLE_SHARED=OFF -DENABLE_STATIC=ON \
  -DWITH_TURBOJPEG=OFF -DWITH_SIMD=OFF -DWITH_JAVA=OFF
cmake --build build-jpeg -j"$(nproc)" && cmake --install build-jpeg

# Leptonica: PNG/JPEG/zlib only, matching the Linux build.
cmake -S leptonica-1.84.1 -B build-lept "${common[@]}" -DBUILD_SHARED_LIBS=OFF -DSW_BUILD=OFF \
  -DBUILD_PROG=OFF -DCMAKE_PREFIX_PATH="$out" \
  -DZLIB_INCLUDE_DIR="$out/include" -DZLIB_LIBRARY="$out/lib/libz.a" \
  -DPNG_PNG_INCLUDE_DIR="$out/include" -DPNG_LIBRARY="$out/lib/libpng16.a" \
  -DJPEG_INCLUDE_DIR="$out/include" -DJPEG_LIBRARY="$out/lib/libjpeg.a"
cmake --build build-lept -j"$(nproc)" && cmake --install build-lept

# Tesseract links "Ws2_32"; mingw ships libws2_32.a, and Linux filesystems are
# case sensitive, so provide the spelling Tesseract asks for.
ln -sf /usr/x86_64-w64-mingw32/lib/libws2_32.a "$out/lib/libWs2_32.a"

# LEPT_TIFF_RESULT answers a try_run() check that cannot execute while
# cross-compiling. Leptonica was built without TIFF, so the answer is 1.
cmake -S tesseract-5.4.1 -B build-tess "${common[@]}" -DCMAKE_INSTALL_PREFIX="$out/tess" \
  -DBUILD_SHARED_LIBS=OFF -DBUILD_TRAINING_TOOLS=OFF -DSW_BUILD=OFF -DOPENMP_BUILD=OFF \
  -DDISABLE_CURL=ON -DDISABLE_ARCHIVE=ON -DDISABLE_TIFF=ON -DLEPT_TIFF_RESULT=1 \
  -DGRAPHICS_DISABLED=ON -DINSTALL_CONFIGS=OFF -DCMAKE_PREFIX_PATH="$out" \
  -DLeptonica_DIR="$out/lib/cmake/leptonica" \
  -DCMAKE_EXE_LINKER_FLAGS="-static -static-libgcc -static-libstdc++ -Wl,--no-insert-timestamp -L$out/lib"
cmake --build build-tess -j"$(nproc)"

# strip rewrites the PE timestamp unless SOURCE_DATE_EPOCH pins it; with it, two
# builds in different directories are byte-for-byte identical.
SOURCE_DATE_EPOCH=1704067200 x86_64-w64-mingw32-strip --strip-all \
  build-tess/bin/tesseract.exe -o "$work/tesseract.exe"
echo "Built $work/tesseract.exe"
```

The libpng and Tesseract archives are GitHub-generated tag archives. If GitHub
ever changes their compression, the checksum check fails; confirm the tag is
unchanged and update the hash rather than dropping the check.

The build is deterministic. Two builds in different directories produce a
byte-identical file. The committed `tesseract.exe` has SHA-256
`084bb4f68b898cb4de965cd587849941f33b8181acd840d9f13cf6b399078eed`.

## Verify before committing

```bash
x86_64-w64-mingw32-objdump -p assets/ocr/windows_x64/tesseract.exe | grep 'DLL Name'
# expect only KERNEL32.dll and msvcrt.dll

# Optional smoke test under Wine, using the same fixtures as CI:
export WINEDEBUG=-all
export TESSDATA_PREFIX='Z:\path\to\repo\assets\ocr\linux_x64\tessdata'
wine assets/ocr/windows_x64/tesseract.exe test/fixtures/ocr/label.png stdout -l eng --psm 6
```

The Windows CI job runs `tool/verify_windows_ocr.ps1` against the built app
bundle. It checks that the engine and language data were installed, that the
engine starts with only system directories on `PATH`, and that it reads
`test/fixtures/ocr/label.png` and `label.jpg`.

Messages such as `Error in pixReadMemTiff: function not present` on stderr are
expected because Leptonica has no TIFF support. Recognition is unaffected and the
app reads only stdout, as with the Linux build.

## Licenses

`LICENSE-*.txt` cover Tesseract, Leptonica, zlib, libpng and libjpeg-turbo.
`NOTICE-mingw-runtime.txt` covers the GCC and MinGW-w64 runtime code that static
linking copies into the executable. The language data license is
`../linux_x64/LICENSE-tessdata.txt`; the Windows build installs a copy beside
the language data.
