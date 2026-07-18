# Citronics Kernel Packaging

Kernel packaging for Citronics boards. This repository builds `.deb` packages from various kernel sources for supported devices.

## Supported Devices

- **FP2**: armhf architecture, using `msm8974` or `msm8x74` kernel configurations.
- **FP3**: arm64 architecture, using `msm8953-staging`.

## Repository Structure

- `kernels.conf`: Main configuration file mapping phones to kernel sources, branches, and architectures.
- `configs/`: Contains kernel `.config` templates named after the kernel entries in `kernels.conf`.
- `build-all-kernels.sh`: Main build script.
- `sources/`: Working directory where kernel sources are cloned.
- `output/`: Where the final `.deb` packages are placed.

## Building Kernels

Use `build-all-kernels.sh` to build for a specific phone:

```bash
./build-all-kernels.sh <phone> [kernel-name-filter]
```

Example:
```bash
./build-all-kernels.sh fp2 msm8974-6.12.y
```

The script clones the source, applies the configuration, and produces Debian packages in the `output/` directory.

## Releasing

1. Tag the current commit with a version:
   ```bash
   git tag v2.0
   ```
2. Run the release script:
   ```bash
   ./release.sh
   ```
   This triggers a GitHub Release with the `.deb` assets.

3. After the release is complete, trigger the [deb-packages](https://github.com/Citronics/deb-packages) CI workflow to update the APT repository.

### Release candidates

Kernels marked with the `rc` component in `kernels.conf` are release candidates.
They are **excluded from normal releases**, so adding an `rc` entry never changes
what an ordinary tag ships. To publish the rc kernels, tag with an `-rcN` suffix:

```bash
git tag v3.2-rc1
./release.sh
```

An `-rc` tag makes `release.sh` build **only** the `rc` kernels and publish the
GitHub release as a **prerelease**. The `.deb` version uses `~rc` (e.g. `3.2~rc1`)
so dpkg sorts it before the final release. Once validated, promote the kernel by
moving its entry to `main` (or `experimental`) and tagging a final version.

## Adding a New Kernel Config

1. Add an entry to `kernels.conf` following this format:
   `<phone> <name> <repo_url> <branch> <arch>`
2. Create a corresponding kernel config file in `configs/<name>.config`.

## Links

- [deb-packages](https://github.com/Citronics/deb-packages): APT repository management — live at `https://citronics.github.io/deb-packages/`.
- [debos-citronics](https://github.com/Citronics/debos-citronics): OS image builder.

## FP2 Kernel Note

The FP2 kernel is not published to the APT repository — it is delivered via `local-debs` in the debos recipe.
This is intentional: FP2 kernel images are large and board-specific, and are embedded directly in the OS image build process.
The `release.sh` script is structured to loop all boards, so when a future FP2 kernel APT release is desired, it will be built and published automatically.
