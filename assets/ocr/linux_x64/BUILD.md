# Rebuilding the bundled Linux `tesseract` binary

This binary is statically linked (no `libtesseract`/`liblept`/libstdc++
dependency) and built inside `ubuntu:22.04` so it matches the glibc baseline
the `linux` CI job and release packaging target. Rebuild it whenever bumping
the tesseract/leptonica version:

```bash
docker run --rm -v "$PWD/build.sh:/build.sh:ro" -v "$PWD/output:/output" \
  ubuntu:22.04 bash /build.sh
```

Where `build.sh` does, in an otherwise clean container:

```bash
apt-get update
apt-get install -y --no-install-recommends \
  build-essential autoconf automake libtool pkg-config cmake git ca-certificates wget \
  zlib1g-dev libpng-dev libjpeg-dev

mkdir -p /build && cd /build

# Leptonica: static, minimal format set (PNG/JPEG/zlib only — enough for
# camera-captured labels; TIFF/WebP/JPEG2000/GIF are intentionally left out
# to avoid needing their static libs too).
wget -q https://github.com/DanBloomberg/leptonica/releases/download/1.84.1/leptonica-1.84.1.tar.gz
tar xf leptonica-1.84.1.tar.gz && cd leptonica-1.84.1
./configure --disable-shared --enable-static \
  --without-libwebp --without-giflib --without-libopenjpeg --without-libtiff \
  --prefix=/build/out
make -j"$(nproc)" && make install
cd /build

# Tesseract: static, linked against the static Leptonica above.
wget -q https://github.com/tesseract-ocr/tesseract/archive/refs/tags/5.4.1.tar.gz -O tesseract-5.4.1.tar.gz
tar xf tesseract-5.4.1.tar.gz && cd tesseract-5.4.1
./autogen.sh
PKG_CONFIG_PATH=/build/out/lib/pkgconfig \
  LDFLAGS="-static-libstdc++ -static-libgcc" \
  ./configure --disable-shared --enable-static --disable-openmp --prefix=/build/out
make -j"$(nproc)" && make install
```

Then strip it (binutils isn't in the base image) and copy it out:

```bash
docker run --rm -v "$PWD/output:/output" ubuntu:22.04 bash -c '
  apt-get update -qq && apt-get install -y -qq binutils
  strip --strip-all /output/tesseract -o /output/tesseract-stripped'
cp output/tesseract-stripped assets/ocr/linux_x64/tesseract
chmod 755 assets/ocr/linux_x64/tesseract
```

Verify before committing:

```bash
ldd assets/ocr/linux_x64/tesseract   # only libpng/libjpeg/libz/libm/libc — no "not found"
assets/ocr/linux_x64/tesseract --version
```

## Why this exists

The binary originally checked into this repo (as of the initial commit,
`cfc9a40`) linked against `libtesseract.so.5`, which doesn't exist in Ubuntu
22.04's own `tesseract-ocr` package (that ships `libtesseract.so.4`, i.e.
tesseract 4.x) — a major-version mismatch, not just a glibc one. There was
no build recipe recorded anywhere for how that binary was produced. Building
statically here sidesteps the whole "which `.so` versions are present on the
end user's system" problem entirely — the tradeoff is a ~6MB binary instead
of a ~40KB one that depended on an OS-provided library.
