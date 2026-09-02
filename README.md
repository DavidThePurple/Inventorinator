<p align="center">
  <img src="assets/images/inventorinator-raygun-v2.png" width="180" alt="Inventorinator raygun logo">
</p>

<h1 align="center">Inventorinator</h1>

<p align="center">
  Take over <s>the world</s> the shop!
</p>

<p align="center">
  A Linux-first workshop inventory, consumables, machine, kit, and build
  manager for makers.
</p>

> [!WARNING]
> **NOT PRODUCTION READY**
>
> Inventorinator is experimental. Features may be incomplete, unstable, or
> change without notice. Back up important data. **Use at your own risk.**

## Download

**[Download Inventorinator](https://github.com/DavidThePurple/Inventorinator/releases)**

Release downloads are provided for:

- Linux x64
- Windows x64
- Android (`arm64-v8a` for most current phones and tablets)

On Linux, extract the `.tar.gz` archive and run `./install.sh`. This registers the
raygun icon and adds Inventorinator to the application menu for your user.

Windows packages are currently unsigned and may trigger a Microsoft Defender
SmartScreen warning. Verify the published SHA-256 checksum before running one.

Inventorinator is under active development. Back up important inventory with
the built-in database export before upgrading.

## What it does

- Tracks supplies, parts, tools, machines, storage, cost, quantity, and
  compatibility.
- Handles filament drying, moisture lifespan, deployment, low-stock alerts,
  and material-specific instructions.
- Creates kits and editable bills of materials, then turns them into persistent
  shared build queues.
- Imports validated `.inventorinator-kit.json` BOM packages on desktop
  (v0.1.0-alpha+). Files can be written manually, exported or scripted by another
  tool, or optionally created with ChatGPT, Codex, Claude, or another research
  tool; Inventorinator has no built-in AI account, API key, or usage fee.
- Scans QR codes and product barcodes with ordinary phone and webcam cameras.
- Captures and OCRs labels, imports product pages, and generates downloadable
  item QR labels.
- Works locally with SQLite and supports optional multi-device synchronization
  through hosted or self-hosted Supabase.
- Supports owner, admin, manager, editor, and builder access boundaries.
- Allows custom item types and contextual fields, so it is not limited to 3D
  printing.

## Getting started

Download the package for your platform from
[Releases](https://github.com/DavidThePurple/Inventorinator/releases).
Inventorinator works locally immediately; remote synchronization is optional
and can be connected from inside the app.

Installation, self-hosting, development, and build documentation belong in the
**[Inventorinator Wiki](https://github.com/DavidThePurple/Inventorinator/wiki)**.

## Help and project information

- Report bugs or request features in
  [GitHub Issues](https://github.com/DavidThePurple/Inventorinator/issues).
- Read the [privacy notes](PRIVACY.md) before enabling OCR, web imports, or
  remote synchronization.
- Report vulnerabilities according to the [security policy](SECURITY.md).
- Contributions are welcome; see [CONTRIBUTING.md](CONTRIBUTING.md).
- Changes are recorded in [CHANGELOG.md](CHANGELOG.md).

## AI assistance

ChatGPT and OpenAI Codex were used as development tools during Inventorinator's
design, implementation, testing, and documentation. Project direction and
final decisions remain with the human maintainer.

## Data attribution

Optional filament swatch search uses data from
[FilamentColors.xyz](https://filamentcolors.xyz/), licensed under
[CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). Inventorinator
caches API responses locally, throttles searches, honors server cooldowns, and
remains fully usable without that service.

The searchable Type icon picker includes the open-source
[Lucide](https://lucide.dev/) icon set. Lucide is licensed under the
[ISC License](https://github.com/lucide-icons/lucide/blob/main/LICENSE).

## License

Inventorinator is released under the [MIT License](LICENSE). You may use,
modify, redistribute, sell, fork, and rebrand it, provided the MIT copyright
and permission notice remains included with copies of the software.
