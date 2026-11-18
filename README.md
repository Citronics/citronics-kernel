# Citronics Kernel Packaging

Kernel packaging for Citronics boards. This repository builds `.deb` packages from various kernel sources for supported devices.

## Supported Devices

- **FP2**: armhf architecture, using `msm8974` or `msm8x74` kernel configurations.
- **FP3**: arm64 architecture, using `msm8953-6.18` (`6.18/staging` of mlainez/linux-msm8953).

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

### Release channels

Each kernel's component in `kernels.conf` decides where its packages go:

| Component | Kernel release | APT component | Devices get it |
|---|---|---|---|
| `main` | `6.12.117-citronics-lime-fp2` | `main` | yes, through the `linux-image-citronics-lime-<phone>` meta-package (`meta` flag) |
| `rc` | `6.12.117-citronics-lime-fp2-rc` | `experimental` | only if they add the `experimental` component |
| `experimental` | as built | `experimental` | only if they add the `experimental` component |

Every release builds whichever kernels moved, whatever their component, and
lists each package's APT component in its `components.tsv` asset, which
deb-packages reads. A release without a `main` kernel is published as a
GitHub prerelease.

Promoting a validated rc to release (FP2 6.12):

1. Validate the rc kernel on a device (install it from `experimental`).
2. Fast-forward the release branch in the kernel fork:
   `git push origin 6.12/rc:6.12/release` (no force).
3. Tag the next version here, e.g. `git tag v3.3 && git push origin v3.3`.
   Automatic builds then number their tags `v3.3.1`, `v3.3.2`, … and the
   package versions follow (`3.3.1`).
4. Run the `build-release` workflow (or let the fork's push trigger it).

Versions must keep increasing: `3.2~rc3.23 < 3.2 < 3.2.1 < 3.3`.

## Adding a New Kernel Config

1. Add an entry to `kernels.conf` following this format:
   `<phone> <name> <repo_url> <branch> <arch> <component> [meta]`
2. Create a corresponding kernel config file in `configs/<name>.config`.

## Links

- [deb-packages](https://github.com/Citronics/deb-packages): APT repository management — live at `https://citronics.github.io/deb-packages/`.
- [debos-citronics](https://github.com/Citronics/debos-citronics): OS image builder.

## FP2 Kernel Note

The FP2 kernel is not published to the APT repository — it is delivered via `local-debs` in the debos recipe.
This is intentional: FP2 kernel images are large and board-specific, and are embedded directly in the OS image build process.
The `release.sh` script is structured to loop all boards, so when a future FP2 kernel APT release is desired, it will be built and published automatically.
