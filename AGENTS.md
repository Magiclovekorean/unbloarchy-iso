# AGENTS.md — Omarchy ISO repo

## Quick commands

- **Build ISO**: `./bin/omarchy-iso-make` (output to `release/`)
- **Build with local source checkouts**: `./bin/omarchy-iso-make --local-source ../unbloarchy ../omarchy-pkgs`
- **Run unit tests**: `./test/all` (shell + Python unittest, VM-free)
- **Acceptance test (QEMU)**: `./bin/omarchy-iso-test release/omarchy.iso`
- **Integration scenarios**: `./test/integration release/omarchy.iso`
- **Boot ISO (fast, no install)**: `./bin/omarchy-iso-boot release/omarchy.iso`
- **Test Windows partition preservation**: `./bin/omarchy-iso-test-windows-disk release/omarchy.iso`
- **Sign ISO**: `./bin/omarchy-iso-sign release/omarchy.iso` (needs 1Password vault key)
- **Upload ISO**: `./bin/omarchy-iso-upload release/omarchy.iso` (needs rclone config)

## Local development with --local-source

Two directories must be mounted as `/omarchy-source` and `/omarchy-pkgs`:

- `/omarchy-source`: the Unbloarchy runtime checkout (provides install scripts, configs, themes, shell, migrations)
- `/omarchy-pkgs`: the omarchy-pkgs checkout (provides pkgbuilds for `omarchy-dev`/`omarchy-settings-dev`/`omarchy-nvim`)

The build script (`builder/build-iso.sh`) detects these at `/omarchy-source` and `/omarchy-pkgs` in the build container. With `--local-source`, it builds omarchy* packages from the local source instead of pulling from the network mirror.

Errors to watch for:
- "local source checkout must contain either install/unbloarchy-{base,other}.packages or install/omarchy-{base,other}.packages" — missing package list files in the Unbloarchy checkout
- "the --local-source checkout ships no install/provisioning/setup-form.sh" — missing shared setup form

## Package mirror & offline build

- The build creates an offline pacman mirror at `release/omarchy-mirror/` (via `builder/prune-offline-mirror.sh`)
- Package lists live in `configs/`:
  - `pacman-online-stable.conf` / `pacman-online-edge.conf` / `pacman-online-rc.conf` — online repo configs
  - `pacman-offline.conf` — used during ISO build to resolve against the offline mirror
- `builder/build-omarchy-packages.sh` builds omarchy* packages into the mirror when `--local-source` is used
- `builder/source-package-lists.sh` maps package list filenames from both `unbloarchy-` and `omarchy-` prefixed checkouts

## Test quirks

- `test/all` runs all unit tests (shell scripts + Python unittest discover). No VM needed.
- Python unit tests (`test/unit/test_*.py`) import from `configs/airootfs/usr/share/omarchy-iso/orchestrator/` and stub `orchestrator.archinstall_adapter` at module scope because the real adapter depends on the archinstall library (only available on the live ISO).
- Some tests fake `efibootmgr` and `blkid` output via a temp dir at the front of PATH. The `test/unit/*-test.sh` scripts similarly fake commands.
- Integration testing (`./test/integration`) boots a real ISO in QEMU. First run installs the ISO unattended; subsequent runs use `--reuse-base` to reuse the saved base image.
- Acceptance testing (`./bin/omarchy-iso-test`) drives the full interactive install flow via QMP screendump + OCR. It reads the acceptance suite from `$OMARCHY_PATH` when available.
- The `test/unit/test_kernel_selection.py` tests PCI hardware detection to decide between `linux-omarchy` and `linux-t2` (for T2 Macs).

## Build order matters: lint -> typecheck -> test

There is no formal lint/typecheck step in this repo, but the workflow order matters:

1. `./bin/omarchy-iso-make` — builds the ISO (this invokes pacman, package resolution, mkarchiso)
2. `./test/all` — runs unit tests against the built ISO bits
3. `./bin/omarchy-iso-test` — acceptance test (requires QEMU, enough RAM)

Do not run `./bin/omarchy-iso-test` before the ISO is built; the test harness needs the ISO artifact.

## Directory ownership

- `archiso/` — the archiso tooling and Makefile (scripts, configs, profile def)
- `builder/` — ISO build orchestration (`build-iso.sh`, `build-omarchy-packages.sh`, `prune-offline-mirror.sh`, `source-package-lists.sh`)
- `bin/` — runtime scripts (`omarchy-iso-make`, `omarchy-iso-test`, `omarchy-iso-boot`, etc.)
- `configs/` — profiledef, pacman configs, airootfs setup
- `test/` — unit tests, integration scenarios
- `release/` — ISO output directory
- `manifests/` — install manifests (JSON) used by limine-entry-tool tests