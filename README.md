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

## Adding a New Kernel Config

1. Add an entry to `kernels.conf` following this format:
   `<phone> <name> <repo_url> <branch> <arch>`
2. Create a corresponding kernel config file in `configs/<name>.config`.

## Links

- [deb-packages](https://github.com/Citronics/deb-packages): APT repository management.
- [debos-citronics](https://github.com/Citronics/debos-citronics): OS image builder.
