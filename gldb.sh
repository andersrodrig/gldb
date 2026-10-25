#!/bin/bash
# =============================================================================
# Generic Linux Distro Builder - GLDB
# Copyright (C) 2025-2026 Anders Rodrig
# GPLv3 - https://www.gnu.org/licenses/gpl-3.0.html
# =============================================================================
# Corrected version - console accent support via setfont.
# =============================================================================

if [ "$EUID" -ne 0 ]; then
    echo -e "\033[1;31m[!] Error: This script must be run as ROOT (sudo).\033[0m"
    exit 1
fi

set -e
set -u
set -o pipefail

START_TIME=$(date +%s)

# Colors
BLUE='\033[1;34m'
GREEN='\033[1;32m'
RED='\033[1;31m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
NC='\033[0m'

# Directories
ROOT_DIR="$(pwd)"
BUILD_DIR="${ROOT_DIR}/build"
SOURCES_DIR="${ROOT_DIR}/sources"
TOOLS_DIR="${ROOT_DIR}/tools"
ROOTFS_DIR="${BUILD_DIR}/rootfs"
ISO_DIR="${BUILD_DIR}/iso"
STAMP_DIR="${BUILD_DIR}/.stamps"

# Versions (Debian 13 / stable)
LINUX_VERSION="6.0.19"
BUSYBOX_VERSION="1.36.1"
GLIBC_VERSION="2.39"
BINUTILS_VERSION="2.39"
PERL_VERSION="5.38.2"
LIBXCRYPT_VERSION="4.4.36"
NCURSES_VERSION="6.4"
MAKE_VERSION="4.4.1"
GCC_VERSION="13.2.0"
ZSTD_VERSION="1.5.6"
NANO_VERSION="8.0"
DROPBEAR_VERSION="2024.85"
ZLIB_VERSION="1.3.2"
OPENSSL_VERSION="3.3.0"
XZ_VERSION="5.4.6"
TAR_VERSION="1.35"
CURL_VERSION="8.7.1"
ALSA_LIB_VERSION="1.2.12"
ALSA_UTILS_VERSION="1.2.12"
KBD_VERSION="2.6.4"
GRUB_VERSION="2.12"
LIBPNG_VERSION="1.6.43"
FREETYPE_VERSION="2.13.3"
ATTR_VERSION="2.5.2"
ACL_VERSION="2.3.2"
XORRISO_VERSION="1.5.4"
MTOOLS_VERSION="4.0.43"

export ARCH="x86_64"
JOBS=$(nproc)
[ "$JOBS" -eq 0 ] && JOBS=1
TARGET="x86_64-linux-gnu"
BUILD="x86_64-linux-gnu"
HOST="x86_64-linux-gnu"

LOG_FILE="${ROOT_DIR}/build_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1

mkdir -p "${STAMP_DIR}"

should_run_step() { [ ! -f "${STAMP_DIR}/${1}.done" ]; }
mark_step_done() { touch "${STAMP_DIR}/${1}.done"; echo -e "${GREEN}[OK] Step '${1}' completed.${NC}"; }

echo -e "${CYAN}[*] Log: $LOG_FILE${NC}"

# -----------------------------------------------------------------------------
# Optional clean-up
# -----------------------------------------------------------------------------
clean_previous_build() {
    echo -e "${YELLOW}Do you want to clean the previous build? (s/N): ${NC}"
    read -r CLEAN
    if [[ "$CLEAN" =~ ^[sS]$ ]]; then
        rm -rf "$BUILD_DIR" "$SOURCES_DIR" "$TOOLS_DIR"
        mkdir -p "$BUILD_DIR" "$SOURCES_DIR" "$TOOLS_DIR" "$ROOTFS_DIR" "$ISO_DIR" "$STAMP_DIR"
        echo -e "${GREEN}Previous build removed.${NC}"
    else
        mkdir -p "$SOURCES_DIR" "$BUILD_DIR" "$TOOLS_DIR" "$ROOTFS_DIR" "$ISO_DIR" "$STAMP_DIR"
    fi
}
clean_previous_build

# -----------------------------------------------------------------------------
# Host dependencies (apt)
# -----------------------------------------------------------------------------
install_dependencies() {
    echo "[*] Installing host dependencies..."
    DEPS="build-essential bison flex libssl-dev libelf-dev bc gawk wget tar xz-utils bzip2 xorriso grub-pc-bin grub-efi-amd64-bin mtools cpio pkg-config python3 texinfo rsync unzip patch zlib1g-dev openssl cmake autoconf automake libtool"
    if command -v apt-get >/dev/null; then
        apt-get update
        apt-get install -y $DEPS
    else
        echo "[!] apt-get not found. Install manually: $DEPS"
        sleep 2
    fi
}
install_dependencies

# ... rest of script unchanged
