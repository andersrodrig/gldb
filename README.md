# GLDB - Generic Linux Distro Builder

GLDB is a Bash-based project that automates the creation of a custom Linux distribution from source code. It builds a minimal root filesystem, compiles the Linux kernel, and generates a bootable ISO image with GRUB.

## What is GLDB?

GLDB is a Linux-from-scratch style builder for creating custom distributions with a lightweight base and a predictable build flow. It is useful for building minimal systems, learning how Linux is assembled, and generating bootable test images.

## Why use it?

GLDB is designed for:

- building lightweight custom Linux distributions;
- creating minimal system images for labs and tests;
- prototyping operating systems from source;
- learning how base Linux components are assembled;
- generating bootable ISO images for development and experimentation.

## Features

- Linux kernel compilation
- BusyBox-based minimal userspace
- root filesystem generation
- GRUB BIOS + UEFI support
- keyboard, locale, network and audio setup scripts
- bootable ISO creation
- user and hostname customization

## Requirements

Before running the build, make sure your host system has:

- a Linux-based host OS
- root privileges
- internet access to download the source tarballs
- enough disk space for compilation and ISO output
- x86_64 architecture support

## Host dependencies

The script already attempts to install the required packages automatically on Debian/Ubuntu systems. If you want to install them manually, you can use this one-liner:

```bash
sudo apt-get update && sudo apt-get install -y build-essential bison flex libssl-dev libelf-dev bc gawk wget tar xz-utils bzip2 xorriso grub-pc-bin grub-efi-amd64-bin mtools cpio pkg-config python3 texinfo rsync unzip patch zlib1g-dev openssl cmake autoconf automake libtool
```

## Repository structure

```text
.
├── gldb.sh
├── README.md
├── LICENSE
├── build/
├── sources/
├── tools/
└── ...
```

## Installation and usage

### 1) Clone the repository

```bash
git clone https://github.com/andersrodrig/gldb.git
cd gldb
```

### 2) Make the script executable

```bash
chmod +x gldb.sh
```

### 3) Run it as root

```bash
sudo ./gldb.sh
```

The script will:

1. verify that the user is running as root;
2. install host dependencies if needed;
3. collect distribution configuration information;
4. download source packages;
5. compile the kernel, libraries and utilities;
6. assemble the root filesystem;
7. configure startup scripts and base system settings;
8. generate a bootable ISO image.

During execution, it will ask for:

- distribution name;
- version;
- hostname;
- root password;
- optional regular user;
- keyboard layout.

## Output

At the end of the build, the script produces an ISO image in the project directory, typically in the format:

```text
DistroName_1.x.iso
```

## Important notes

This project is a custom Linux build system and should be used with caution. It is intended for learning, prototyping, and lab environments. It is not a production-ready distro installer without review and environment-specific validation.

## License

This project is licensed under the GNU General Public License v3.0.

See the LICENSE file for full terms.

## Author

Anders Rodrig

## Contributions

Contributions are welcome. You can improve the build flow, documentation, tooling, and compatibility with additional environments.

---

GLDB is a practical way to create lightweight Linux distributions from source code while keeping the build process scripted and reproducible.
