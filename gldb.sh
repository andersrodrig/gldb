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

# -----------------------------------------------------------------------------
# Collect user configuration information (full validation)
# -----------------------------------------------------------------------------
collect_info() {
    while true; do
        clear
        echo -e "${BLUE}========================================================${NC}"
        echo -e "${CYAN}                  GLDB - CONFIGURATOR                  ${NC}"
        echo -e "${BLUE}========================================================${NC}"

        while true; do
            read -p "[-] Distribution name [DistroName]: " DISTRO_NAME
            DISTRO_NAME=${DISTRO_NAME:-DistroName}
            if [ -z "$DISTRO_NAME" ]; then
                echo -e "${RED}    Name cannot be empty.${NC}"
                continue
            fi
            break
        done

        while true; do
            read -p "[-] Version [1.x]: " DISTRO_VERSION
            DISTRO_VERSION=${DISTRO_VERSION:-1.x}
            if [ -z "$DISTRO_VERSION" ]; then
                echo -e "${RED}    Version cannot be empty.${NC}"
                continue
            fi
            break
        done

        SAFE_DISTRO_NAME=$(echo "$DISTRO_NAME" | tr ' ' '_' | tr '/' '-')
        SAFE_DISTRO_VERSION=$(echo "$DISTRO_VERSION" | tr ' ' '_' | tr '/' '-')

        while true; do
            read -p "[-] Hostname: " HOSTNAME_CFG
            HOSTNAME_CFG=${HOSTNAME_CFG:-DistroName-Example}
            if [ -z "$HOSTNAME_CFG" ]; then
                echo -e "${RED}    Hostname cannot be empty.${NC}"
                continue
            fi
            if [[ "$HOSTNAME_CFG" =~ [[:space:]] ]]; then
                echo -e "${RED}    Hostname cannot contain spaces.${NC}"
                continue
            fi
            break
        done

        echo -e "\n${BLUE}🔑 ROOT PASSWORD${NC}"
        while true; do
            read -s -p "    Root password: " ROOT_PASS1; echo
            if [ -z "$ROOT_PASS1" ]; then
                echo -e "${RED}    Password cannot be empty.${NC}"
                continue
            fi
            read -s -p "    Confirm: " ROOT_PASS2; echo
            if [ "$ROOT_PASS1" = "$ROOT_PASS2" ]; then
                ROOT_PASS="$ROOT_PASS1"
                break
            else
                echo -e "${RED}    Passwords do not match.${NC}"
            fi
        done

        if command -v openssl >/dev/null; then
            ROOT_HASH=$(openssl passwd -6 "$ROOT_PASS")
        elif command -v mkpasswd >/dev/null; then
            ROOT_HASH=$(mkpasswd -m sha-512 "$ROOT_PASS")
        else
            echo -e "${RED}    No password hash generator found (openssl or mkpasswd). Aborting.${NC}"
            exit 1
        fi

        CREATE_USER="n"
        read -p "[-] Create regular user? (y/N): " CREATE_USER_INPUT
        if [[ "$CREATE_USER_INPUT" =~ ^[yY]$ ]]; then
            CREATE_USER="y"
            while true; do
                read -p "    Username: " USER_NAME
                if [ -z "$USER_NAME" ]; then
                    echo -e "${RED}    User name cannot be empty.${NC}"
                    continue
                fi
                if ! [[ "$USER_NAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
                    echo -e "${RED}    Invalid username (use only letters, numbers, - and _).${NC}"
                    continue
                fi
                break
            done

            while true; do
                read -s -p "    Password: " USER_PASS1; echo
                if [ -z "$USER_PASS1" ]; then
                    echo -e "${RED}    Password cannot be empty.${NC}"
                    continue
                fi
                read -s -p "    Confirm: " USER_PASS2; echo
                if [ "$USER_PASS1" = "$USER_PASS2" ]; then
                    USER_PASS="$USER_PASS1"
                    break
                else
                    echo -e "${RED}    Passwords do not match.${NC}"
                fi
            done

            if command -v openssl >/dev/null; then
                USER_HASH=$(openssl passwd -6 "$USER_PASS")
            elif command -v mkpasswd >/dev/null; then
                USER_HASH=$(mkpasswd -m sha-512 "$USER_PASS")
            else
                echo -e "${RED}    No password hash generator found. Aborting.${NC}"
                exit 1
            fi
        fi

        echo -e "\n${BLUE}⌨️  KEYBOARD LAYOUT${NC}"
        echo "    Common options: br-abnt2, us, es, fr, de, it, uk, jp"
        echo "    Or enter another layout (example: br-abnt2)"
        read -p "Layout [br-abnt2]: " SELECTED_KEYMAP
        SELECTED_KEYMAP=${SELECTED_KEYMAP:-br-abnt2}

        echo -e "\n${GREEN}🔎 SUMMARY${NC}"
        echo -e "  Distro: $DISTRO_NAME $DISTRO_VERSION"
        echo -e "  Hostname: $HOSTNAME_CFG"
        echo -e "  Keyboard: $SELECTED_KEYMAP"
        [ "$CREATE_USER" == "y" ] && echo -e "  User: $USER_NAME (created)" || echo -e "  User: none"
        read -p "[?] Is this correct? (y/n): " CONFIRM
        if [[ "$CONFIRM" =~ ^[yY]$ ]]; then
            break
        else
            echo -e "${YELLOW}Restarting configuration...${NC}"
            sleep 1
        fi
    done
}
collect_info

# -----------------------------------------------------------------------------
# Download sources
# -----------------------------------------------------------------------------
download_sources() {
    echo "[+] Checking sources in $SOURCES_DIR..."
    mkdir -p "$SOURCES_DIR"
    cd "$SOURCES_DIR" || exit

    download_if_missing() {
        local url="$1"
        local filename=$(basename "$url")
        if [ -f "$filename" ]; then
            echo "    -> $filename already exists, skipping."
        else
            echo "    -> Downloading $filename ..."
            wget -nc "$url" || { echo "Failed to download $url"; exit 1; }
        fi
    }

    download_if_missing "https://ftp.gnu.org/gnu/grub/grub-${GRUB_VERSION}.tar.xz"
    download_if_missing "https://www.alsa-project.org/files/pub/lib/alsa-lib-${ALSA_LIB_VERSION}.tar.bz2"
    download_if_missing "https://www.alsa-project.org/files/pub/utils/alsa-utils-${ALSA_UTILS_VERSION}.tar.bz2"
    download_if_missing "https://mirrors.edge.kernel.org/pub/linux/utils/kbd/kbd-${KBD_VERSION}.tar.xz"
    download_if_missing "https://mirrors.edge.kernel.org/pub/linux/kernel/v6.x/linux-${LINUX_VERSION}.tar.xz"
    download_if_missing "https://busybox.net/downloads/busybox-${BUSYBOX_VERSION}.tar.bz2"
    download_if_missing "https://ftp.gnu.org/gnu/binutils/binutils-${BINUTILS_VERSION}.tar.xz"
    download_if_missing "https://ftp.gnu.org/gnu/glibc/glibc-${GLIBC_VERSION}.tar.xz"
    download_if_missing "https://unifoundry.com/pub/unifont/unifont-15.0.01/font-builds/unifont-15.0.01.pcf.gz"
    download_if_missing "https://www.cpan.org/src/5.0/perl-${PERL_VERSION}.tar.gz"
    download_if_missing "https://github.com/besser82/libxcrypt/releases/download/v${LIBXCRYPT_VERSION}/libxcrypt-${LIBXCRYPT_VERSION}.tar.xz"
    download_if_missing "https://ftp.gnu.org/gnu/ncurses/ncurses-${NCURSES_VERSION}.tar.gz"
    download_if_missing "https://ftp.gnu.org/gnu/make/make-${MAKE_VERSION}.tar.gz"
    download_if_missing "https://ftp.gnu.org/gnu/gcc/gcc-${GCC_VERSION}/gcc-${GCC_VERSION}.tar.xz"
    download_if_missing "https://github.com/facebook/zstd/releases/download/v${ZSTD_VERSION}/zstd-${ZSTD_VERSION}.tar.gz"
    download_if_missing "https://www.nano-editor.org/dist/v8/nano-${NANO_VERSION}.tar.xz"
    download_if_missing "https://matt.ucc.asn.au/dropbear/releases/dropbear-${DROPBEAR_VERSION}.tar.bz2"
    download_if_missing "https://zlib.net/zlib-${ZLIB_VERSION}.tar.gz"
    download_if_missing "https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz"
    download_if_missing "https://github.com/tukaani-project/xz/releases/download/v${XZ_VERSION}/xz-${XZ_VERSION}.tar.xz"
    download_if_missing "https://ftp.gnu.org/gnu/tar/tar-${TAR_VERSION}.tar.xz"
    download_if_missing "https://curl.se/download/curl-${CURL_VERSION}.tar.xz"
    download_if_missing "https://download.sourceforge.net/libpng/libpng-${LIBPNG_VERSION}.tar.xz"
    download_if_missing "https://download.savannah.gnu.org/releases/freetype/freetype-${FREETYPE_VERSION}.tar.xz"
    download_if_missing "https://download.savannah.gnu.org/releases/attr/attr-${ATTR_VERSION}.tar.gz"
    download_if_missing "https://download.savannah.gnu.org/releases/acl/acl-${ACL_VERSION}.tar.gz"
    download_if_missing "https://www.gnu.org/software/xorriso/xorriso-${XORRISO_VERSION}.tar.gz"
    download_if_missing "https://ftp.gnu.org/gnu/mtools/mtools-${MTOOLS_VERSION}.tar.gz"

    cd "$ROOT_DIR" || exit
}
download_sources

LINUX_DIR="${BUILD_DIR}/linux-${LINUX_VERSION}"
if [ ! -d "$LINUX_DIR" ]; then
    tar -xf "${SOURCES_DIR}/linux-${LINUX_VERSION}.tar.xz" -C "$BUILD_DIR"
fi

# =============================================================================
# BUILD FUNCTIONS
# =============================================================================

install_kernel_headers() {
    should_run_step "kernel_headers" || return 0
    echo -e "${CYAN}[+] Installing kernel headers...${NC}"
    cd "$LINUX_DIR"
    make mrproper
    make ARCH=$ARCH headers_install INSTALL_HDR_PATH="${ROOTFS_DIR}/usr"
    cd "$ROOT_DIR"
    mark_step_done "kernel_headers"
}

install_binutils() {
    should_run_step "binutils" || return 0
    echo -e "${CYAN}[+] Compiling binutils...${NC}"
    BINUTILS_DIR="${BUILD_DIR}/binutils-${BINUTILS_VERSION}"
    [ ! -d "$BINUTILS_DIR" ] && tar -xf "${SOURCES_DIR}/binutils-${BINUTILS_VERSION}.tar.xz" -C "$BUILD_DIR"
    mkdir -p "${BINUTILS_DIR}/build" && cd "$_"
    ../configure --prefix=/usr --build="${BUILD}" --host="${HOST}" --target="${TARGET}" \
        --with-sysroot=/ --with-build-sysroot="${ROOTFS_DIR}" --disable-static --enable-shared \
        --disable-nls --disable-werror --without-zstd --without-debuginfod \
        CFLAGS="-Os" CXXFLAGS="-Os"
    make -j${JOBS} && make DESTDIR="${ROOTFS_DIR}" install
    cd "$ROOT_DIR"
    for tool in as ld nm ar objcopy objdump strip; do
        [ -f "${ROOTFS_DIR}/usr/bin/${TARGET}-${tool}" ] && mv "${ROOTFS_DIR}/usr/bin/${TARGET}-${tool}" "${ROOTFS_DIR}/usr/bin/${tool}"
    done
    rm -rf "${ROOTFS_DIR}/usr/${TARGET}" 2>/dev/null || true
    strip "${ROOTFS_DIR}/usr/bin/"* 2>/dev/null || true
    mark_step_done "binutils"
}

compile_glibc_full() {
    should_run_step "glibc" || return 0
    echo -e "${CYAN}[+] Compiling glibc...${NC}"
    GLIBC_DIR="${BUILD_DIR}/glibc-${GLIBC_VERSION}"
    [ ! -d "$GLIBC_DIR" ] && tar -xf "${SOURCES_DIR}/glibc-${GLIBC_VERSION}.tar.xz" -C "$BUILD_DIR"
    cd "$GLIBC_DIR"
    if [ ! -f "${ROOTFS_DIR}/usr/include/linux/version.h" ]; then
        mkdir -p "${ROOTFS_DIR}/usr/include/linux"
        cat > "${ROOTFS_DIR}/usr/include/linux/version.h" << EOF
#define LINUX_VERSION_CODE $(echo ${LINUX_VERSION} | awk -F. '{print $1*65536+$2*256+$3}')
#define KERNEL_VERSION(a,b,c) (((a)<<16)+((b)<<8)+(c))
#define LINUX_VERSION_MAJOR $(echo ${LINUX_VERSION} | cut -d. -f1)
#define LINUX_VERSION_PATCHLEVEL $(echo ${LINUX_VERSION} | cut -d. -f2)
#define LINUX_VERSION_SUBLEVEL $(echo ${LINUX_VERSION} | cut -d. -f3)
EOF
    fi
    rm -rf build-glibc && mkdir build-glibc && cd build-glibc
    CFLAGS="-O2 -U_FORTIFY_SOURCE" CXXFLAGS="-O2 -U_FORTIFY_SOURCE" \
    ../configure --prefix=/usr --host="${TARGET}" --build="${BUILD}" \
        --with-headers="${ROOTFS_DIR}/usr/include" --enable-kernel=6.0.0 \
        --disable-werror --disable-nscd --disable-multilib --without-selinux \
        libc_cv_forced_unwind=yes libc_cv_c_cleanup=yes
    make -j${JOBS} && make install_root="${ROOTFS_DIR}" install
    mkdir -p "${ROOTFS_DIR}/lib64" "${ROOTFS_DIR}/lib"
    if [ -f "${ROOTFS_DIR}/lib/ld-linux-x86-64.so.2" ]; then
        ln -sf /lib/ld-linux-x86-64.so.2 "${ROOTFS_DIR}/lib64/ld-linux-x86-64.so.2"
    elif [ -f "${ROOTFS_DIR}/usr/lib/ld-linux-x86-64.so.2" ]; then
        ln -sf /usr/lib/ld-linux-x86-64.so.2 "${ROOTFS_DIR}/lib64/ld-linux-x86-64.so.2"
        ln -sf /usr/lib/ld-linux-x86-64.so.2 "${ROOTFS_DIR}/lib/ld-linux-x86-64.so.2"
    fi
    cat > "${ROOTFS_DIR}/etc/ld.so.conf" << 'EOF'
/usr/local/lib
/usr/lib
/lib
/lib64
EOF
    ldconfig -r "${ROOTFS_DIR}" 2>/dev/null || true
    cd "$ROOT_DIR"
    mark_step_done "glibc"
}

compile_zstd() {
    should_run_step "zstd" || return 0
    echo -e "${CYAN}[+] Compiling zstd...${NC}"
    ZSTD_DIR="${BUILD_DIR}/zstd-${ZSTD_VERSION}"
    [ ! -d "$ZSTD_DIR" ] && tar -xzf "${SOURCES_DIR}/zstd-${ZSTD_VERSION}.tar.gz" -C "$BUILD_DIR"
    cd "$ZSTD_DIR"
    make -j${JOBS} PREFIX=/usr LIBDIR=/usr/lib CC="gcc --sysroot=${ROOTFS_DIR}" CXX="g++ --sysroot=${ROOTFS_DIR}"
    make PREFIX=/usr LIBDIR=/usr/lib DESTDIR="${ROOTFS_DIR}" install
    ldconfig -r "${ROOTFS_DIR}" 2>/dev/null || true
    cd "$ROOT_DIR"
    mark_step_done "zstd"
}

compile_libxcrypt() {
    should_run_step "libxcrypt" || return 0
    echo -e "${CYAN}[+] Compiling libxcrypt...${NC}"
    LIBXCRYPT_DIR="${BUILD_DIR}/libxcrypt-${LIBXCRYPT_VERSION}"
    [ ! -d "$LIBXCRYPT_DIR" ] && tar -xf "${SOURCES_DIR}/libxcrypt-${LIBXCRYPT_VERSION}.tar.xz" -C "$BUILD_DIR"
    cd "$LIBXCRYPT_DIR"
    rm -rf build && mkdir build && cd build
    CC="gcc --sysroot=${ROOTFS_DIR}" \
    ../configure --prefix=/usr --libdir=/usr/lib --host=${TARGET} --build=${BUILD} \
        --enable-shared --disable-static --disable-werror --enable-obsolete-api=glibc
    make -j${JOBS} && make install DESTDIR="${ROOTFS_DIR}"
    ln -sf ../usr/lib/libcrypt.so.1 "${ROOTFS_DIR}/lib/libcrypt.so.1" 2>/dev/null || true
    ldconfig -r "${ROOTFS_DIR}" 2>/dev/null || true
    cd "$ROOT_DIR"
    mark_step_done "libxcrypt"
}

compile_ncurses() {
    should_run_step "ncurses" || return 0
    echo -e "${CYAN}[+] Compiling ncurses...${NC}"
    NCURSES_DIR="${BUILD_DIR}/ncurses-${NCURSES_VERSION}"
    [ ! -d "$NCURSES_DIR" ] && tar -xf "${SOURCES_DIR}/ncurses-${NCURSES_VERSION}.tar.gz" -C "$BUILD_DIR"
    cd "$NCURSES_DIR"
    CC="gcc --sysroot=${ROOTFS_DIR}" CXX="g++ --sysroot=${ROOTFS_DIR}" \
    ./configure --prefix=/usr --libdir=/usr/lib --host="${TARGET}" --with-shared \
        --without-debug --without-ada --enable-widec --with-sysroot="${ROOTFS_DIR}" \
        --enable-pc-files --with-pkg-config-libdir=/usr/lib/pkgconfig --with-termlib
    make -j${JOBS} && make DESTDIR="${ROOTFS_DIR}" install
    ln -sf libncursesw.so.6 "${ROOTFS_DIR}/usr/lib/libncurses.so"
    ln -sf libncursesw.so.6 "${ROOTFS_DIR}/usr/lib/libncurses.so.6"
    ln -sf libtinfow.so.6 "${ROOTFS_DIR}/usr/lib/libtinfo.so.6"
    ln -sf libtinfow.so.6 "${ROOTFS_DIR}/usr/lib/libtinfo.so"
    mkdir -p "${ROOTFS_DIR}/lib64"
    ln -sf ../usr/lib/libtinfow.so.6 "${ROOTFS_DIR}/lib64/libtinfo.so.6" 2>/dev/null || true
    ldconfig -r "${ROOTFS_DIR}" 2>/dev/null || true
    cd "$ROOT_DIR"
    mark_step_done "ncurses"
}

compile_perl() {
    should_run_step "perl" || return 0
    echo -e "${CYAN}[+] Compiling Perl...${NC}"
    PERL_DIR="${BUILD_DIR}/perl-${PERL_VERSION}"
    [ ! -d "$PERL_DIR" ] && tar -xzf "${SOURCES_DIR}/perl-${PERL_VERSION}.tar.gz" -C "$BUILD_DIR"
    cd "$PERL_DIR"
    export CC="gcc --sysroot=${ROOTFS_DIR}" LD="gcc --sysroot=${ROOTFS_DIR}"
    export LDFLAGS="-L${ROOTFS_DIR}/usr/lib -L${ROOTFS_DIR}/lib -Wl,-rpath-link=${ROOTFS_DIR}/usr/lib:${ROOTFS_DIR}/lib"
    export CPPFLAGS="-I${ROOTFS_DIR}/usr/include" CFLAGS="-Os"
    export LD_LIBRARY_PATH="${ROOTFS_DIR}/usr/lib:${ROOTFS_DIR}/lib:${LD_LIBRARY_PATH:-}"
    ./Configure -des -Dprefix=/usr -Dvendorprefix=/usr -Dsiteprefix=/usr \
        -Dman1dir=/usr/share/man/man1 -Dman3dir=/usr/share/man/man3 \
        -Dscriptdir=/usr/bin -Dcc="${CC}" -Dld="${LD}" -Dldflags="${LDFLAGS}" \
        -Dlddlflags="-shared ${LDFLAGS}" -Dcppflags="${CPPFLAGS}" \
        -Dlibpth="/usr/lib /lib" -Dincpth="/usr/include" -Duseshrplib -Doptimize="-Os" \
        -Dusethreads -Duse64bitint -Dinstallusrbinperl -Dd_crypt_r=undef
    make -j${JOBS} && make install DESTDIR="${ROOTFS_DIR}"
    cd "${ROOTFS_DIR}"
    rm -rf TAP::* Term::* Test::* Test2::* version::* pod2* prove ptar* shasum zipdetails corelist enc2xs h2ph h2xs instmodsh json_pp libnetcfg perlbug perldoc perlivp perlthanks piconv pl2pm splain xsubpp re.0 root.0 2>/dev/null || true
    unset CC LD LDFLAGS CPPFLAGS CFLAGS LD_LIBRARY_PATH
    cd "$ROOT_DIR"
    mark_step_done "perl"
}

compile_make() {
    should_run_step "make" || return 0
    echo -e "${CYAN}[+] Compiling GNU Make...${NC}"
    MAKE_DIR="${BUILD_DIR}/make-${MAKE_VERSION}"
    [ ! -d "$MAKE_DIR" ] && tar -xf "${SOURCES_DIR}/make-${MAKE_VERSION}.tar.gz" -C "$BUILD_DIR"
    cd "$MAKE_DIR"
    rm -rf build && mkdir build && cd build
    CC="gcc --sysroot=${ROOTFS_DIR}" ../configure --prefix=/usr --host="${TARGET}" --disable-nls
    make -j${JOBS} && make DESTDIR="${ROOTFS_DIR}" install
    cd "$ROOT_DIR"
    mark_step_done "make"
}

compile_gcc() {
    should_run_step "gcc" || return 0
    echo -e "${CYAN}[+] Compiling GCC (long process)...${NC}"
    GCC_DIR="${BUILD_DIR}/gcc-${GCC_VERSION}"
    [ ! -d "$GCC_DIR" ] && tar -xf "${SOURCES_DIR}/gcc-${GCC_VERSION}.tar.xz" -C "$BUILD_DIR" && \
        cd "$GCC_DIR" && ./contrib/download_prerequisites && cd "$ROOT_DIR"
    cd "$GCC_DIR"
    rm -rf build && mkdir build && cd build
    ../configure --prefix=/usr --build="${BUILD}" --host="${HOST}" --target="${TARGET}" \
        --with-sysroot=/ --with-build-sysroot="${ROOTFS_DIR}" --disable-multilib \
        --enable-languages=c,c++ --disable-nls --disable-bootstrap --disable-libsanitizer \
        --enable-default-pie --enable-default-ssp
    make -j${JOBS} && make DESTDIR="${ROOTFS_DIR}" install
    ln -sf gcc "${ROOTFS_DIR}/usr/bin/cc"
    ln -sf g++ "${ROOTFS_DIR}/usr/bin/c++"
    cd "$ROOT_DIR"
    mark_step_done "gcc"
}

compile_zlib() {
    should_run_step "zlib" || return 0
    echo -e "${CYAN}[+] Compiling zlib...${NC}"
    ZLIB_DIR="${BUILD_DIR}/zlib-${ZLIB_VERSION}"
    [ ! -d "$ZLIB_DIR" ] && tar -xzf "${SOURCES_DIR}/zlib-${ZLIB_VERSION}.tar.gz" -C "$BUILD_DIR"
    cd "$ZLIB_DIR"
    CC="gcc --sysroot=${ROOTFS_DIR}" ./configure --prefix=/usr --libdir=/usr/lib --shared
    make -j${JOBS} && make DESTDIR="${ROOTFS_DIR}" install
    ldconfig -r "${ROOTFS_DIR}" 2>/dev/null || true
    cd "$ROOT_DIR"
    mark_step_done "zlib"
}

compile_openssl() {
    should_run_step "openssl" || return 0
    echo -e "${CYAN}[+] Compiling OpenSSL...${NC}"
    OPENSSL_DIR="${BUILD_DIR}/openssl-${OPENSSL_VERSION}"
    [ ! -d "$OPENSSL_DIR" ] && tar -xzf "${SOURCES_DIR}/openssl-${OPENSSL_VERSION}.tar.gz" -C "$BUILD_DIR"
    cd "$OPENSSL_DIR"
    export CC="gcc --sysroot=${ROOTFS_DIR}"
    ./Configure linux-x86_64 --prefix=/usr --openssldir=/etc/ssl --libdir=lib shared zlib
    make -j${JOBS} && make DESTDIR="${ROOTFS_DIR}" install_sw
    unset CC
    ldconfig -r "${ROOTFS_DIR}" 2>/dev/null || true
    cd "$ROOT_DIR"
    mark_step_done "openssl"
}

compile_xz() {
    should_run_step "xz" || return 0
    echo -e "${CYAN}[+] Compiling xz-utils...${NC}"
    XZ_DIR="${BUILD_DIR}/xz-${XZ_VERSION}"
    [ ! -d "$XZ_DIR" ] && tar -xf "${SOURCES_DIR}/xz-${XZ_VERSION}.tar.xz" -C "$BUILD_DIR"
    cd "$XZ_DIR"
    CC="gcc --sysroot=${ROOTFS_DIR}" ./configure --prefix=/usr --host="${TARGET}" --disable-nls --disable-static
    make -j${JOBS} && make DESTDIR="${ROOTFS_DIR}" install
    cd "$ROOT_DIR"
    mark_step_done "xz"
}

compile_attr() {
    should_run_step "attr" || return 0
    echo -e "${CYAN}[+] Compiling attr...${NC}"
    ATTR_DIR="${BUILD_DIR}/attr-${ATTR_VERSION}"
    [ ! -d "$ATTR_DIR" ] && tar -xzf "${SOURCES_DIR}/attr-${ATTR_VERSION}.tar.gz" -C "$BUILD_DIR"
    cd "$ATTR_DIR"
    CC="gcc --sysroot=${ROOTFS_DIR}" \
    ./configure --prefix=/usr --host="${TARGET}" --disable-static --enable-shared \
        CFLAGS="-Os" LDFLAGS="-L${ROOTFS_DIR}/usr/lib -L${ROOTFS_DIR}/lib -Wl,-rpath-link=${ROOTFS_DIR}/usr/lib:${ROOTFS_DIR}/lib" || exit 1
    make -j${JOBS} || exit 1
    make DESTDIR="${ROOTFS_DIR}" install || exit 1
    ldconfig -r "${ROOTFS_DIR}" 2>/dev/null || true
    cd "$ROOT_DIR"
    mark_step_done "attr"
}

compile_acl() {
    should_run_step "acl" || return 0
    echo -e "${CYAN}[+] Compiling acl...${NC}"
    ACL_DIR="${BUILD_DIR}/acl-${ACL_VERSION}"
    [ ! -d "$ACL_DIR" ] && tar -xzf "${SOURCES_DIR}/acl-${ACL_VERSION}.tar.gz" -C "$BUILD_DIR"
    cd "$ACL_DIR"
    CC="gcc --sysroot=${ROOTFS_DIR}" \
    ./configure --prefix=/usr --host="${TARGET}" --disable-static --enable-shared \
        CFLAGS="-Os" LDFLAGS="-L${ROOTFS_DIR}/usr/lib -L${ROOTFS_DIR}/lib -Wl,-rpath-link=${ROOTFS_DIR}/usr/lib:${ROOTFS_DIR}/lib" || exit 1
    make -j${JOBS} || exit 1
    make DESTDIR="${ROOTFS_DIR}" install || exit 1
    ldconfig -r "${ROOTFS_DIR}" 2>/dev/null || true
    cd "$ROOT_DIR"
    mark_step_done "acl"
}

compile_tar() {
    should_run_step "tar" || return 0
    echo -e "${CYAN}[+] Compiling GNU tar (with ACL)...${NC}"
    TAR_DIR="${BUILD_DIR}/tar-${TAR_VERSION}"
    [ ! -d "$TAR_DIR" ] && tar -xf "${SOURCES_DIR}/tar-${TAR_VERSION}.tar.xz" -C "$BUILD_DIR"
    cd "$TAR_DIR"
    make distclean 2>/dev/null || true
    export FORCE_UNSAFE_CONFIGURE=1
    CC="gcc --sysroot=${ROOTFS_DIR}" CPPFLAGS="-I${ROOTFS_DIR}/usr/include" \
    LDFLAGS="-L${ROOTFS_DIR}/usr/lib -L${ROOTFS_DIR}/lib" \
    ./configure --prefix=/usr --host="${TARGET}" --build="${BUILD}" --with-sysroot="${ROOTFS_DIR}" \
        --disable-nls --without-selinux --with-acl --without-xattrs --without-libarchive
    make -j${JOBS} && make DESTDIR="${ROOTFS_DIR}" install
    unset FORCE_UNSAFE_CONFIGURE
    ldconfig -r "${ROOTFS_DIR}" 2>/dev/null || true
    mkdir -p "${ROOTFS_DIR}/bin"
    rm -f "${ROOTFS_DIR}/bin/tar"
    ln -sf ../usr/bin/tar "${ROOTFS_DIR}/bin/tar"
    cd "$ROOT_DIR"
    mark_step_done "tar"
}

compile_curl() {
    should_run_step "curl" || return 0
    echo -e "${CYAN}[+] Compiling curl...${NC}"
    CURL_DIR="${BUILD_DIR}/curl-${CURL_VERSION}"
    [ ! -d "$CURL_DIR" ] && tar -xf "${SOURCES_DIR}/curl-${CURL_VERSION}.tar.xz" -C "$BUILD_DIR"
    cd "$CURL_DIR"
    CC="gcc --sysroot=${ROOTFS_DIR}" \
    ./configure --prefix=/usr --host="${TARGET}" --with-openssl="${ROOTFS_DIR}/usr" \
        --with-zlib="${ROOTFS_DIR}/usr" --with-zstd="${ROOTFS_DIR}/usr" --disable-static \
        CPPFLAGS="-I${ROOTFS_DIR}/usr/include" LDFLAGS="-L${ROOTFS_DIR}/usr/lib -L${ROOTFS_DIR}/lib"
    make -j${JOBS} && make DESTDIR="${ROOTFS_DIR}" install
    cd "$ROOT_DIR"
    mark_step_done "curl"
}

compile_nano() {
    should_run_step "nano" || return 0
    echo -e "${CYAN}[+] Compiling nano...${NC}"
    NANO_DIR="${BUILD_DIR}/nano-${NANO_VERSION}"
    [ ! -d "$NANO_DIR" ] && tar -xf "${SOURCES_DIR}/nano-${NANO_VERSION}.tar.xz" -C "$BUILD_DIR"
    cd "$NANO_DIR"
    export LIBS="-ltinfow"
    CC="gcc --sysroot=${ROOTFS_DIR}" ./configure --prefix=/usr --host="${TARGET}" --disable-nls --enable-utf8 --with-sysroot="${ROOTFS_DIR}"
    make -j${JOBS} && make DESTDIR="${ROOTFS_DIR}" install
    unset LIBS
    cd "$ROOT_DIR"
    mark_step_done "nano"
}

compile_dropbear() {
    should_run_step "dropbear" || return 0
    echo -e "${CYAN}[+] Compiling dropbear...${NC}"
    DROPBEAR_DIR="${BUILD_DIR}/dropbear-${DROPBEAR_VERSION}"
    [ ! -d "$DROPBEAR_DIR" ] && tar -xf "${SOURCES_DIR}/dropbear-${DROPBEAR_VERSION}.tar.bz2" -C "$BUILD_DIR"
    cd "$DROPBEAR_DIR"
    CC="gcc --sysroot=${ROOTFS_DIR}" ./configure --prefix=/usr --host="${TARGET}"
    make -j${JOBS} PROGRAMS="dropbear dbclient dropbearkey dropbearconvert scp"
    make DESTDIR="${ROOTFS_DIR}" install PROGRAMS="dropbear dbclient dropbearkey dropbearconvert scp"
    mkdir -p "${ROOTFS_DIR}/etc/dropbear"
    chmod 755 "${ROOTFS_DIR}/etc/dropbear"
    cd "$ROOT_DIR"
    mark_step_done "dropbear"
}

compile_alsa_lib() {
    should_run_step "alsa_lib" || return 0
    echo -e "${CYAN}[+] Compiling alsa-lib...${NC}"
    ALSA_LIB_DIR="${BUILD_DIR}/alsa-lib-${ALSA_LIB_VERSION}"
    [ ! -d "$ALSA_LIB_DIR" ] && tar -xf "${SOURCES_DIR}/alsa-lib-${ALSA_LIB_VERSION}.tar.bz2" -C "$BUILD_DIR"
    cd "$ALSA_LIB_DIR"
    CC="gcc --sysroot=${ROOTFS_DIR}" ./configure --prefix=/usr --host="${TARGET}" --disable-python --with-sysroot="${ROOTFS_DIR}"
    make -j${JOBS} && make DESTDIR="${ROOTFS_DIR}" install
    find "${ROOTFS_DIR}/usr/lib" -name "*.la" -delete
    cd "$ROOT_DIR"
    mark_step_done "alsa_lib"
}

compile_alsa_utils() {
    should_run_step "alsa_utils" || return 0
    echo -e "${CYAN}[+] Compiling alsa-utils...${NC}"
    ALSA_UTILS_DIR="${BUILD_DIR}/alsa-utils-${ALSA_UTILS_VERSION}"
    [ ! -d "$ALSA_UTILS_DIR" ] && tar -xf "${SOURCES_DIR}/alsa-utils-${ALSA_UTILS_VERSION}.tar.bz2" -C "$BUILD_DIR"
    cd "$ALSA_UTILS_DIR"
    find "${ROOTFS_DIR}/usr/lib" -name "*.la" -delete
    export PKG_CONFIG_PATH="${ROOTFS_DIR}/usr/lib/pkgconfig"
    export PKG_CONFIG_LIBDIR="${ROOTFS_DIR}/usr/lib/pkgconfig"
    export PKG_CONFIG_SYSROOT_DIR="${ROOTFS_DIR}"
    CC="gcc --sysroot=${ROOTFS_DIR}" CPPFLAGS="-I${ROOTFS_DIR}/usr/include -I${ROOTFS_DIR}/usr/include/ncursesw" \
    LDFLAGS="-L${ROOTFS_DIR}/usr/lib -L${ROOTFS_DIR}/lib -ltinfow" \
    ./configure --prefix=/usr --host="${TARGET}" --disable-alsaconf --disable-bat --disable-xmlto
    unset PKG_CONFIG_PATH PKG_CONFIG_LIBDIR PKG_CONFIG_SYSROOT_DIR
    make -j${JOBS} && make DESTDIR="${ROOTFS_DIR}" install
    cd "$ROOT_DIR"
    mark_step_done "alsa_utils"
}

compile_kbd() {
    should_run_step "kbd" || return 0
    echo -e "${CYAN}[+] Compiling kbd...${NC}"
    KBD_DIR="${BUILD_DIR}/kbd-${KBD_VERSION}"
    [ ! -d "$KBD_DIR" ] && tar -xf "${SOURCES_DIR}/kbd-${KBD_VERSION}.tar.xz" -C "$BUILD_DIR"
    cd "$KBD_DIR"
    CC="gcc --sysroot=${ROOTFS_DIR}" ./configure --prefix=/usr --host="${TARGET}" --disable-vlock --disable-tests
    make -j${JOBS} && make DESTDIR="${ROOTFS_DIR}" install
    cd "$ROOT_DIR"
    mark_step_done "kbd"
}

compile_busybox() {
    should_run_step "busybox" || return 0
    echo -e "${CYAN}[+] Compiling BusyBox...${NC}"
    BUSYBOX_DIR="${BUILD_DIR}/busybox-${BUSYBOX_VERSION}"
    [ ! -d "$BUSYBOX_DIR" ] && tar -xf "${SOURCES_DIR}/busybox-${BUSYBOX_VERSION}.tar.bz2" -C "$BUILD_DIR"
    cd "$BUSYBOX_DIR"
    make distclean
    make defconfig
    sed -i 's/CONFIG_STATIC=y/CONFIG_STATIC=n/' .config
    sed -i 's/.*CONFIG_FEATURE_SH_STANDALONE.*/CONFIG_FEATURE_SH_STANDALONE=y/' .config
    sed -i 's/.*CONFIG_TC.*/CONFIG_TC=n/' .config
    sed -i 's/.*CONFIG_LOGIN.*/CONFIG_LOGIN=y/' .config
    sed -i 's/.*CONFIG_FEATURE_SHADOWPASSWDS.*/CONFIG_FEATURE_SHADOWPASSWDS=y/' .config
    sed -i 's/.*CONFIG_FEATURE_EDITING_FANCY_PROMPT.*/CONFIG_FEATURE_EDITING_FANCY_PROMPT=y/' .config
    sed -i 's/.*CONFIG_SU.*/CONFIG_SU=y/' .config
    sed -i 's/.*CONFIG_KILLALL5.*/CONFIG_KILLALL5=y/' .config
    sed -i 's/.*CONFIG_GETTY.*/CONFIG_GETTY=y/' .config
    sed -i 's/.*CONFIG_IPTABLES.*/CONFIG_IPTABLES=y/' .config
    sed -i 's/.*CONFIG_BRCTL.*/CONFIG_BRCTL=y/' .config
    sed -i 's/.*CONFIG_FEATURE_BRCTL_FDB.*/CONFIG_FEATURE_BRCTL_FDB=y/' .config
    sed -i 's/.*CONFIG_BEEP.*/CONFIG_BEEP=y/' .config
    sed -i 's/.*CONFIG_TAR=.*/# CONFIG_TAR is not set/' .config
    sed -i 's/.*CONFIG_DPKG=.*/# CONFIG_DPKG is not set/' .config
    sed -i 's/.*CONFIG_DPKG_DEB=.*/# CONFIG_DPKG_DEB is not set/' .config
    yes "" | make CC="gcc --sysroot=${ROOTFS_DIR}" oldconfig || true
    make CC="gcc --sysroot=${ROOTFS_DIR}" -j${JOBS}
    make CONFIG_PREFIX="${ROOTFS_DIR}" install
    chmod 4755 "${ROOTFS_DIR}/bin/busybox"
    [ ! -L "${ROOTFS_DIR}/bin/killall5" ] && [ ! -e "${ROOTFS_DIR}/bin/killall5" ] && ln -s busybox "${ROOTFS_DIR}/bin/killall5"
    cd "$ROOT_DIR"
    mark_step_done "busybox"
}

compile_kernel() {
    should_run_step "kernel" || return 0
    echo -e "${CYAN}[+] Compiling Kernel...${NC}"
    cd "$LINUX_DIR"
    make distclean
    make x86_64_defconfig
    ./scripts/config --enable DEVTMPFS
    ./scripts/config --enable DEVTMPFS_MOUNT
    ./scripts/config --enable BLK_DEV_INITRD
    ./scripts/config --enable RD_GZIP
    ./scripts/config --enable ATA
    ./scripts/config --enable SATA_AHCI
    ./scripts/config --enable BLK_DEV_NVME
    ./scripts/config --enable HW_RANDOM
    ./scripts/config --enable HW_RANDOM_INTEL
    ./scripts/config --enable HW_RANDOM_AMD
    ./scripts/config --enable HW_RANDOM_VIA
    ./scripts/config --enable EFI
    ./scripts/config --enable EFI_STUB
    ./scripts/config --enable EFI_PARTITION
    ./scripts/config --enable E1000
    ./scripts/config --enable E1000E
    ./scripts/config --enable R8169
    ./scripts/config --enable 8139CP
    ./scripts/config --enable VMXNET3
    ./scripts/config --enable USB_NET
    ./scripts/config --enable BRIDGE
    ./scripts/config --enable NETFILTER
    ./scripts/config --enable NF_CONNTRACK
    ./scripts/config --enable NF_NAT
    ./scripts/config --enable IP_NF_IPTABLES
    ./scripts/config --enable IP_NF_NAT
    ./scripts/config --enable IP_NF_TARGET_MASQUERADE
    ./scripts/config --enable FB
    ./scripts/config --enable FB_EFI
    ./scripts/config --enable FB_VESA
    ./scripts/config --enable FB_SIMPLE
    ./scripts/config --enable SYSFB_SIMPLEFB
    ./scripts/config --enable FB_CFB_FILLRECT
    ./scripts/config --enable FB_CFB_COPYAREA
    ./scripts/config --enable FB_CFB_IMAGEBLIT
    ./scripts/config --enable FRAMEBUFFER_CONSOLE
    ./scripts/config --enable LOGO
    ./scripts/config --enable LOGO_LINUX_CLUT224
    ./scripts/config --enable FB_BOOT_VESA_SUPPORT
    ./scripts/config --disable FRAMEBUFFER_CONSOLE_DEFERRED_TAKEOVER
    ./scripts/config --enable FRAMEBUFFER_CONSOLE_ROTATION
    ./scripts/config --enable FONTS
    ./scripts/config --enable FONT_8x16
    ./scripts/config --enable FONT_TER16x32
    ./scripts/config --enable VT
    ./scripts/config --enable VT_CONSOLE
    ./scripts/config --enable CONSOLE_TRANSLATIONS
    ./scripts/config --enable HW_CONSOLE
    ./scripts/config --enable NLS
    ./scripts/config --set-str NLS_DEFAULT "utf8"
    ./scripts/config --enable NLS_UTF8
    ./scripts/config --enable NLS_CODEPAGE_437
    ./scripts/config --enable NLS_ASCII
    ./scripts/config --enable NLS_ISO8859_1
    ./scripts/config --enable NLS_ISO8859_15
    ./scripts/config --enable DRM
    ./scripts/config --enable DRM_SIMPLEDRM
    ./scripts/config --enable DRM_VMBUS
    ./scripts/config --enable DRM_VMWGFX
    ./scripts/config --enable DRM_VMWGFX_FBCON
    ./scripts/config --enable DRM_VBOXVIDEO
    ./scripts/config --enable DRM_FBDEV_EMULATION
    ./scripts/config --set-val DRM_FBDEV_OVERALLOC 100
    ./scripts/config --enable DRM_KMS_HELPER
    ./scripts/config --enable DRM_KMS_FB_HELPER
    ./scripts/config --enable INPUT
    ./scripts/config --enable INPUT_KEYBOARD
    ./scripts/config --enable KEYBOARD_ATKBD
    ./scripts/config --enable INPUT_MOUSE
    ./scripts/config --enable MOUSE_PS2
    ./scripts/config --enable HID_GENERIC
    ./scripts/config --enable USB_HID
    ./scripts/config --enable SOUND
    ./scripts/config --enable SND
    ./scripts/config --enable SND_PCI
    ./scripts/config --enable SND_HDA_INTEL
    ./scripts/config --enable SND_HDA_INPUT_BEEP
    ./scripts/config --enable SND_HDA_CODEC_REALTEK
    ./scripts/config --enable SND_HDA_CODEC_ANALOG
    ./scripts/config --enable SND_HDA_CODEC_SIGMATEL
    ./scripts/config --enable SND_HDA_CODEC_VIA
    ./scripts/config --enable SND_HDA_CODEC_HDMI
    ./scripts/config --enable SND_HDA_CODEC_GENERIC
    ./scripts/config --enable SND_INTEL8X0
    ./scripts/config --enable SND_AC97_CODEC
    ./scripts/config --enable USB_PCMCIA
    ./scripts/config --enable EXT2_FS
    ./scripts/config --enable EXT2_FS_XATTR
    ./scripts/config --enable EXT2_FS_POSIX_ACL
    ./scripts/config --enable EXT4_FS
    ./scripts/config --enable EXT4_FS_POSIX_ACL
    ./scripts/config --enable FS_POSIX_ACL
    ./scripts/config --set-str CONFIG_LOCALVERSION "-${SAFE_DISTRO_NAME}-${SAFE_DISTRO_VERSION}"
    make olddefconfig
    make KCFLAGS="-Wno-array-bounds -Wno-stringop-overflow -Wno-enum-int-mismatch" -j${JOBS} bzImage
    cd "$ROOT_DIR"
    mark_step_done "kernel"
}

compile_libpng() {
    should_run_step "libpng" || return 0
    echo -e "${CYAN}[+] Compiling libpng...${NC}"
    PNG_DIR="${BUILD_DIR}/libpng-${LIBPNG_VERSION}"
    [ ! -d "$PNG_DIR" ] && tar -xf "${SOURCES_DIR}/libpng-${LIBPNG_VERSION}.tar.xz" -C "$BUILD_DIR"
    cd "$PNG_DIR"
    CC="gcc --sysroot=${ROOTFS_DIR}" \
    CPPFLAGS="-I${ROOTFS_DIR}/usr/include" \
    LDFLAGS="-L${ROOTFS_DIR}/usr/lib -L${ROOTFS_DIR}/lib -Wl,-rpath-link=${ROOTFS_DIR}/usr/lib:${ROOTFS_DIR}/lib" \
    ./configure --prefix=/usr --host="${TARGET}" --disable-static
    make -j${JOBS} && make DESTDIR="${ROOTFS_DIR}" install
    ldconfig -r "${ROOTFS_DIR}" 2>/dev/null || true
    cd "$ROOT_DIR"
    mark_step_done "libpng"
}

compile_freetype() {
    should_run_step "freetype" || return 0
    echo -e "${CYAN}[+] Compiling FreeType2...${NC}"
    FT_DIR="${BUILD_DIR}/freetype-${FREETYPE_VERSION}"
    [ ! -d "$FT_DIR" ] && tar -xf "${SOURCES_DIR}/freetype-${FREETYPE_VERSION}.tar.xz" -C "$BUILD_DIR"
    cd "$FT_DIR"
    CC="gcc --sysroot=${ROOTFS_DIR}" \
    ./configure --prefix=/usr --host="${TARGET}" --disable-static \
        --with-png=yes --with-zlib=yes \
        PKG_CONFIG_PATH="${ROOTFS_DIR}/usr/lib/pkgconfig" \
        PKG_CONFIG_LIBDIR="${ROOTFS_DIR}/usr/lib/pkgconfig" \
        PKG_CONFIG_SYSROOT_DIR="${ROOTFS_DIR}"
    make -j${JOBS} && make DESTDIR="${ROOTFS_DIR}" install
    ldconfig -r "${ROOTFS_DIR}" 2>/dev/null || true
    cd "$ROOT_DIR"
    mark_step_done "freetype"
}

compile_mtools() {
    should_run_step "mtools" || return 0
    echo -e "${CYAN}[+] Compiling mtools...${NC}"
    MTOOLS_DIR="${BUILD_DIR}/mtools-${MTOOLS_VERSION}"
    [ ! -d "$MTOOLS_DIR" ] && tar -xzf "${SOURCES_DIR}/mtools-${MTOOLS_VERSION}.tar.gz" -C "$BUILD_DIR"
    cd "$MTOOLS_DIR"
    CC="gcc --sysroot=${ROOTFS_DIR}" \
    ./configure --prefix=/usr --host="${TARGET}" --disable-static \
        CFLAGS="-Os" LDFLAGS="-L${ROOTFS_DIR}/usr/lib -L${ROOTFS_DIR}/lib -Wl,-rpath-link=${ROOTFS_DIR}/usr/lib:${ROOTFS_DIR}/lib" || exit 1
    make -j${JOBS} || exit 1
    make DESTDIR="${ROOTFS_DIR}" install || exit 1
    cd "$ROOT_DIR"
    mark_step_done "mtools"
}

compile_grub() {
    should_run_step "grub" || return 0
    echo -e "${CYAN}[+] Compiling GRUB ${GRUB_VERSION} (BIOS + UEFI)...${NC}"
    GRUB_DIR="${BUILD_DIR}/grub-${GRUB_VERSION}"
    [ ! -d "$GRUB_DIR" ] && tar -xf "${SOURCES_DIR}/grub-${GRUB_VERSION}.tar.xz" -C "$BUILD_DIR"
    cd "$GRUB_DIR"

    export PKG_CONFIG_PATH="${ROOTFS_DIR}/usr/lib/pkgconfig"
    export PKG_CONFIG_LIBDIR="${ROOTFS_DIR}/usr/lib/pkgconfig"
    export PKG_CONFIG_SYSROOT_DIR="${ROOTFS_DIR}"

    echo -e "${CYAN}  -> Compiling GRUB for BIOS...${NC}"
    make distclean 2>/dev/null || true
    ./configure --prefix=/usr --host="${TARGET}" --build="${BUILD}" --with-platform=pc \
        --enable-grub-mkfont --disable-werror --disable-efiemu \
        TARGET_CFLAGS="-Os" TARGET_CC="gcc --sysroot=${ROOTFS_DIR}" \
        CC="gcc --sysroot=${ROOTFS_DIR}" CFLAGS="-Os" || exit 1
    touch grub-core/extra_deps.lst
    make -j${JOBS} || exit 1
    make DESTDIR="${ROOTFS_DIR}" install || exit 1

    echo -e "${CYAN}  -> Compiling GRUB for UEFI...${NC}"
    make distclean 2>/dev/null || true
    ./configure --prefix=/usr --host="${TARGET}" --build="${BUILD}" --with-platform=efi \
        --enable-grub-mkfont --disable-werror --disable-efiemu \
        TARGET_CFLAGS="-Os" TARGET_CC="gcc --sysroot=${ROOTFS_DIR}" \
        CC="gcc --sysroot=${ROOTFS_DIR}" CFLAGS="-Os" || exit 1
    touch grub-core/extra_deps.lst
    make -j${JOBS} || exit 1
    make DESTDIR="${ROOTFS_DIR}" install || exit 1

    unset PKG_CONFIG_PATH PKG_CONFIG_LIBDIR PKG_CONFIG_SYSROOT_DIR

    for tool in grub-install grub-mkconfig grub-mkrescue grub-mkfont; do
        [ -f "${ROOTFS_DIR}/usr/bin/${tool}" ] && ln -sf /usr/bin/${tool} "${ROOTFS_DIR}/usr/sbin/${tool}" 2>/dev/null || true
    done

    cd "$ROOT_DIR"
    mark_step_done "grub"
}

compile_xorriso() {
    should_run_step "xorriso" || return 0
    echo -e "${CYAN}[+] Compiling xorriso...${NC}"
    XORRISO_DIR="${BUILD_DIR}/xorriso-${XORRISO_VERSION}"
    [ ! -d "$XORRISO_DIR" ] && tar -xzf "${SOURCES_DIR}/xorriso-${XORRISO_VERSION}.tar.gz" -C "$BUILD_DIR"
    cd "$XORRISO_DIR"
    CC="gcc --sysroot=${ROOTFS_DIR}" \
    ./configure --prefix=/usr --host="${TARGET}" --disable-static --enable-zlib \
        CFLAGS="-Os" LDFLAGS="-L${ROOTFS_DIR}/usr/lib -L${ROOTFS_DIR}/lib -Wl,-rpath-link=${ROOTFS_DIR}/usr/lib:${ROOTFS_DIR}/lib" || exit 1
    make -j${JOBS} || exit 1
    make DESTDIR="${ROOTFS_DIR}" install || exit 1
    cd "$ROOT_DIR"
    mark_step_done "xorriso"
}

configure_rootfs() {
    should_run_step "rootfs_config" || return 0
    echo -e "${CYAN}[+] Configuring root filesystem...${NC}"

    mkdir -p "${ROOTFS_DIR}/"{dev,proc,sys,etc/init.d,tmp,root,home,usr/share/udhcpc,bin,sbin,var/log,run/lock}

    echo -e "${YELLOW}[*] Injecting kernel into rootfs for offline installation...${NC}"
    mkdir -p "${ROOTFS_DIR}/boot"
    cp "${BUILD_DIR}/linux-${LINUX_VERSION}/arch/x86/boot/bzImage" "${ROOTFS_DIR}/boot/vmlinuz"

    chmod 1777 "${ROOTFS_DIR}/tmp"
    ln -sf ../run "${ROOTFS_DIR}/var/run"
    ln -sf ../run/lock "${ROOTFS_DIR}/var/lock"

    echo "$HOSTNAME_CFG" > "${ROOTFS_DIR}/etc/hostname"

    cat > "${ROOTFS_DIR}/etc/os-release" << EOF
NAME="${DISTRO_NAME}"
VERSION="${DISTRO_VERSION}"
ID=${SAFE_DISTRO_NAME}
PRETTY_NAME="${DISTRO_NAME} ${DISTRO_VERSION}"
HOME_URL="https://example.com"
EOF

    echo -e "${DISTRO_NAME} ${DISTRO_VERSION} \n \l" > "${ROOTFS_DIR}/etc/issue"

    cat > "${ROOTFS_DIR}/etc/nsswitch.conf" << 'EOF'
passwd:         files
group:          files
shadow:         files
hosts:          files dns
networks:       files
EOF

    touch "${ROOTFS_DIR}/etc/passwd" "${ROOTFS_DIR}/etc/group" "${ROOTFS_DIR}/etc/shadow"
    if ! grep -q "^root:" "${ROOTFS_DIR}/etc/passwd"; then
        echo "root:x:0:0:root:/root:/bin/sh" >> "${ROOTFS_DIR}/etc/passwd"
    fi
    if ! grep -q "^root:" "${ROOTFS_DIR}/etc/group"; then
        echo "root:x:0:" >> "${ROOTFS_DIR}/etc/group"
    fi
    if ! grep -q "^nogroup:" "${ROOTFS_DIR}/etc/group"; then
        echo "nogroup:x:65534:" >> "${ROOTFS_DIR}/etc/group"
    fi

    if [ -n "$ROOT_HASH" ]; then
        sed -i '/^root:/d' "${ROOTFS_DIR}/etc/shadow"
        echo "root:$ROOT_HASH:19000:0:99999:7:::" >> "${ROOTFS_DIR}/etc/shadow"
    else
        if ! grep -q "^root:" "${ROOTFS_DIR}/etc/shadow"; then
            echo "root::19000:0:99999:7:::" >> "${ROOTFS_DIR}/etc/shadow"
        fi
    fi

    if [ "$CREATE_USER" == "y" ]; then
        echo -e "${CYAN}[+] Creating user: $USER_NAME${NC}"
        mkdir -p "${ROOTFS_DIR}/home/$USER_NAME"
        sed -i "/^$USER_NAME:/d" "${ROOTFS_DIR}/etc/passwd"
        sed -i "/^$USER_NAME:/d" "${ROOTFS_DIR}/etc/shadow"
        echo "$USER_NAME:x:1000:1000:Linux User:/home/$USER_NAME:/bin/sh" >> "${ROOTFS_DIR}/etc/passwd"
        if ! grep -q "^users:x:1000:" "${ROOTFS_DIR}/etc/group"; then
            echo "users:x:1000:$USER_NAME" >> "${ROOTFS_DIR}/etc/group"
        else
            sed -i "s/^users:x:1000:.*/&,${USER_NAME}/" "${ROOTFS_DIR}/etc/group"
        fi
        if [ -n "$USER_HASH" ]; then
            echo "$USER_NAME:$USER_HASH:19000:0:99999:7:::" >> "${ROOTFS_DIR}/etc/shadow"
        else
            echo "$USER_NAME::19000:0:99999:7:::" >> "${ROOTFS_DIR}/etc/shadow"
        fi
        chown -R 1000:1000 "${ROOTFS_DIR}/home/$USER_NAME"
    fi

    cat > "${ROOTFS_DIR}/etc/profile" << 'EOF'
export PATH=/bin:/sbin:/usr/bin:/usr/sbin
export LANG=C.UTF-8
export LC_ALL=C
export PS1='\u@\h:\w\$ '
alias ll='ls -al'
echo -e "\033[1;36m==============================================\033[0m"
echo -e " Welcome to \033[1;32m$(grep PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '"')\033[0m"
echo -e " Kernel: $(uname -r)"
echo -e " \033[1;34mBuild Ready - GLDB Power User Mode\033[0m"
echo -e "\033[1;36m==============================================\033[0m"
EOF

    cat > "${ROOTFS_DIR}/etc/inittab" << 'EOF'
::sysinit:/etc/init.d/rcS
ttyS0::respawn:/sbin/getty -L ttyS0 115200 vt100
tty1::respawn:/sbin/getty -L tty1 115200 vt100
tty2::respawn:/sbin/getty -L tty2 115200 vt100
::ctrlaltdel:/sbin/reboot
::shutdown:/bin/killall5 -15
::shutdown:/bin/sleep 2
::shutdown:/bin/killall5 -9
::shutdown:/bin/umount -a -r 2>/dev/null
EOF

    cat > "${ROOTFS_DIR}/bin/net" << 'EOF'
#!/bin/sh
{
    ip link set lo up
    for iface in $(ls /sys/class/net | grep -v lo); do
        if [ -e "/sys/class/net/$iface" ]; then
            ip link set "$iface" up
            udhcpc -i "$iface" -b -q -s /usr/share/udhcpc/default.script
        fi
    done
} > /var/log/net.log 2>&1
EOF
    chmod +x "${ROOTFS_DIR}/bin/net"

    cat > "${ROOTFS_DIR}/usr/share/udhcpc/default.script" << 'EOF'
#!/bin/sh
if [ "$1" = "bound" ]; then
    ifconfig $interface $ip netmask $subnet
    [ -n "$router" ] && route add default gw $router dev $interface
    if [ -n "$dns" ]; then
        > /etc/resolv.conf
        for server in $dns; do echo "nameserver $server" >> /etc/resolv.conf; done
    fi
fi
EOF
    chmod +x "${ROOTFS_DIR}/usr/share/udhcpc/default.script"

    cat > "${ROOTFS_DIR}/bin/set-keymap" << 'EOF'
#!/bin/sh
if [ -n "$1" ]; then
    loadkeys -d "$1" && echo "✅ Keymap set to $1 (dead keys)" || echo "❌ Failed"
else
    echo "Usage: set-keymap <layout>"
fi
EOF
    chmod +x "${ROOTFS_DIR}/bin/set-keymap"

    cat > "${ROOTFS_DIR}/bin/netconfig" << 'EOF'
#!/bin/sh
configure_network() {
    echo "=============================================="
    echo "    NETWORK CONFIGURATION - netconfig"
    echo "=============================================="
    echo "1) Bridge"
    echo "2) NAT"
    echo "3) Automatic DHCP"
    echo "=============================================="
    while true; do
        read -p "Option [1-3]: " net_option
        case $net_option in 1|2|3) break ;; *) echo "Invalid";; esac
    done
    INTERFACES=$(ls /sys/class/net | grep -v lo)
    [ -z "$INTERFACES" ] && echo "ERROR: No interface found" && return 1
    case $net_option in
        1) PRIMARY_IFACE=$(echo "$INTERFACES" | head -1); brctl addbr br0 2>/dev/null; brctl addif br0 "$PRIMARY_IFACE" 2>/dev/null; ip link set up br0; ip link set up "$PRIMARY_IFACE"; udhcpc -i br0 -S -q -s /usr/share/udhcpc/default.script; echo "✅ Bridge configured";;
        2) echo 1 > /proc/sys/net/ipv4/ip_forward 2>/dev/null; iptables -t nat -A POSTROUTING -j MASQUERADE; for iface in $INTERFACES; do ip link set "$iface" up; udhcpc -i "$iface" -b -q -s /usr/share/udhcpc/default.script; done; echo "✅ NAT configured";;
        3) for iface in $INTERFACES; do ip link set "$iface" up; udhcpc -i "$iface" -b -q -s /usr/share/udhcpc/default.script; done; echo "✅ DHCP configured";;
    esac
}
configure_network
EOF
    chmod +x "${ROOTFS_DIR}/bin/netconfig"

    cat > "${ROOTFS_DIR}/etc/init.d/rcS" << EOF
#!/bin/sh
dmesg -n 1
print_status() {
    local msg="\$1"; local status="\$2"
    printf "%-60s" "\$msg"
    if [ \$status -eq 0 ]; then
        echo -e "[ \033[1;32m OK \033[0m ]"
    else
        echo -e "[ \033[1;31mFAIL\033[0m ]"
    fi
}
echo -e "\nStarting system initialization...\n"

echo -ne "\033%G"
if [ -x /usr/bin/kbd_mode ]; then
    /usr/bin/kbd_mode -u
    print_status "Setting console UTF-8 mode" \$?
fi

mount -t proc proc /proc >/dev/null 2>&1; print_status "Mounting /proc" \$?
mount -t sysfs sysfs /sys >/dev/null 2>&1; print_status "Mounting /sys" \$?
mount -t devtmpfs devtmpfs /dev >/dev/null 2>&1; print_status "Mounting /dev" \$?
mkdir -p /dev/pts; mount -t devpts devpts /dev/pts >/dev/null 2>&1; print_status "Mounting /dev/pts" \$?
[ -x /sbin/ldconfig ] && /sbin/ldconfig > /dev/null 2>&1 && print_status "Updating dynamic linker cache" \$?

if [ -x /usr/bin/loadkeys ]; then
    /usr/bin/loadkeys -d ${SELECTED_KEYMAP:-br-abnt2} > /dev/null 2>&1
    print_status "Setting keyboard layout (${SELECTED_KEYMAP:-br-abnt2}) with dead keys" \$?
fi

if [ -x /usr/bin/setfont ]; then
    /usr/bin/setfont lat9w-16.psfu.gz 2>/dev/null || /usr/bin/setfont Lat9-VGA16.psfu.gz 2>/dev/null || true
    print_status "Setting console font (with accents)" \$?
fi

if [ -d /proc/asound/cards ] && [ "\$(cat /proc/asound/cards 2>/dev/null | wc -l)" -gt 0 ]; then
    if [ -x /usr/bin/amixer ]; then
        /usr/bin/amixer sset Master unmute > /dev/null 2>&1
        /usr/bin/amixer sset Master 80% > /dev/null 2>&1
        /usr/bin/amixer sset Speaker unmute > /dev/null 2>&1
        /usr/bin/amixer sset Headphone unmute > /dev/null 2>&1
        print_status "Initializing audio volume" \$?
    else
        print_status "Initializing audio volume (amixer not found)" 1
    fi
else
    print_status "Initializing audio volume (no sound card)" 0
fi

[ -f /etc/hostname ] && hostname -F /etc/hostname && print_status "Setting hostname" \$?
/bin/net > /dev/null 2>&1 & print_status "Starting network (background)" 0
[ -x /usr/sbin/dropbear ] && /usr/sbin/dropbear && print_status "Starting Dropbear SSH server" 0
echo -e "\nSystem initialization complete."
sleep 3
EOF
    chmod +x "${ROOTFS_DIR}/etc/init.d/rcS"

    cat > "${ROOTFS_DIR}/init" << 'EOF'
#!/bin/sh
export PATH=/bin:/sbin:/usr/bin:/usr/sbin
[ -x /sbin/init ] && exec /sbin/init || exec /bin/sh
EOF
    chmod +x "${ROOTFS_DIR}/init"

    cat > "${ROOTFS_DIR}/bin/installdisk" << 'EOF'
#!/bin/sh
BLUE='\033[1;34m'; GREEN='\033[1;32m'; RED='\033[1;31m'; CYAN='\033[1;36m'; YELLOW='\033[1;33m'; NC='\033[0m'
clear
echo -e "${BLUE}========================================================${NC}"
echo -e "${CYAN}         GLDB - SYSTEM INSTALLER (BIOS/MBR)${NC}"
echo -e "${BLUE}========================================================${NC}"
[ "$(id -u)" -ne 0 ] && echo -e "${RED}Error: Run this as root!${NC}" && exit 1

echo -e "\n${YELLOW}[*] Scanning available disks...${NC}"
disk_list=""; count=0
while read -r major minor blocks name; do
    [ -z "$name" ] || [ "$name" = "name" ] && continue
    [ ! -b "/dev/$name" ] && continue
    case "$name" in loop*|ram*|sr*) continue;; esac
    count=$((count+1))
    eval "disk_${count}_name=\"$name\""
    eval "disk_${count}_info=\"$name\""
    disk_list="$disk_list $count"
done < /proc/partitions
[ "$count" -eq 0 ] && echo -e "${RED}No disks found!${NC}" && exit 1

echo -e "\n${CYAN}Select the target disk:${NC}"
for i in $disk_list; do eval "info=\$disk_${i}_info"; echo -e "  [${GREEN}$i${NC}] /dev/$info"; done
echo -e "  [${RED}0${NC}] Cancel"
while true; do
    echo -en "\n${CYAN}Option [0-$count]: ${NC}"; read OPTION
    if [ "$OPTION" -ge 0 ] 2>/dev/null && [ "$OPTION" -le "$count" ] 2>/dev/null; then break; fi
done
[ "$OPTION" -eq 0 ] && echo "Cancelled." && exit 0

eval "TARGET_DEV=\$disk_${OPTION}_name"
TARGET_PATH="/dev/$TARGET_DEV"

PART_ROOT="${TARGET_PATH}1"
case "$TARGET_DEV" in
    nvme*|mmcblk*) PART_ROOT="${TARGET_PATH}p1" ;;
esac

echo -e "\n${RED}⚠️ ALL DATA ON $TARGET_PATH WILL BE ERASED!${NC}"
read -p "Are you sure? (s/N): " CONFIRM
[ "$CONFIRM" != "s" ] && [ "$CONFIRM" != "S" ] && echo "Aborted." && exit 0

echo -e "\n${CYAN}[1/5] Erasing old data and MBR...${NC}"
dd if=/dev/zero of="$TARGET_PATH" bs=1M count=10 > /dev/null 2>&1
sync; sleep 2

echo -e "${CYAN}[2/5] Creating MBR partition table...${NC}"
printf "o\nn\np\n1\n2048\n\na\n1\nw\n" | fdisk "$TARGET_PATH" > /dev/null 2>&1

sync; sleep 2
blockdev --rereadpt "$TARGET_PATH" 2>/dev/null
partprobe "$TARGET_PATH" 2>/dev/null
sync; sleep 2

if [ ! -b "$PART_ROOT" ]; then
    echo -e "${RED}[!] Critical error: partition $PART_ROOT was not created.${NC}"
    exit 1
fi

echo -e "${CYAN}[3/5] Formatting ($PART_ROOT) with ext2 and mounting...${NC}"
mkfs.ext2 -F "$PART_ROOT" || { echo -e "${RED}[!] Failed to format $PART_ROOT${NC}"; exit 1; }

mkdir -p /mnt/target
mount "$PART_ROOT" /mnt/target || { echo -e "${RED}[!] Failed to mount $PART_ROOT${NC}"; exit 1; }

echo -e "${CYAN}[4/5] Copying base system and kernel...${NC}"
cp -a /bin /boot /etc /home /lib /lib64 /root /sbin /usr /var /init /mnt/target/ || { echo -e "${RED}[!] Error copying files!${NC}"; exit 1; }

mkdir -p /mnt/target/dev /mnt/target/proc /mnt/target/sys /mnt/target/tmp /mnt/target/run
chmod 1777 /mnt/target/tmp

echo -e "${CYAN}[5/5] Installing GRUB and boot configuration...${NC}"
mkdir -p /mnt/target/boot/grub

mount --bind /dev /mnt/target/dev
mount --bind /proc /mnt/target/proc
mount --bind /sys /mnt/target/sys

chroot /mnt/target grub-install --target=i386-pc "$TARGET_PATH" || {
    grub-install --target=i386-pc --boot-directory=/mnt/target/boot "$TARGET_PATH"
}

printf 'set timeout=3\nset default=0\n\nmenuentry "GLDB Linux (BusyBox)" {\n    search --no-floppy --file --set=root /boot/vmlinuz\n    linux /boot/vmlinuz root=%s ro quiet\n}\n' "$PART_ROOT" > /mnt/target/boot/grub/grub.cfg

echo -e "${CYAN}Configuring fstab...${NC}"
echo "$PART_ROOT  /    ext2    defaults,noatime    0 1" > /mnt/target/etc/fstab

sync
umount -l /mnt/target/sys /mnt/target/proc /mnt/target/dev /mnt/target 2>/dev/null

echo -e "\n${GREEN}🎉 INSTALLATION COMPLETE!${NC} Reboot and remove the media."
EOF
chmod +x "${ROOTFS_DIR}/bin/installdisk"

    cat > "${ROOTFS_DIR}/bin/audioconfig" << 'EOF'
#!/bin/sh

if [ "$(id -u)" -ne 0 ]; then
    echo "Error: This script must be run as root." >&2
    exit 1
fi

echo "==> Checking system configuration files..."
mkdir -p /etc

if [ ! -f /etc/group ]; then
    echo "root:x:0:" > /etc/group
fi

if ! grep -q "^audio:" /etc/group; then
    echo "Creating group 'audio'..."
    echo "audio:x:29:" >> /etc/group
fi

echo "==> Adding all system users to audio group..."
while IFS=: read -r username _ uid gid _ _ shell; do
    if [ "$uid" -ge 1000 ] || [ "$username" = "root" ]; then
        if ! grep -q "^audio:.*:$username" /etc/group && ! grep -q "^audio:.*,$username" /etc/group; then
            if grep -q "^audio:x:29:$" /etc/group; then
                sed -i 's/^audio:x:29:$/audio:x:29:'"$username"'/' /etc/group
            else
                sed -i 's/^audio:x:29:/&'"$username"',/' /etc/group
            fi
            echo "-> User '$username' added to audio group."
        else
            echo "-> User '$username' is already in the audio group."
        fi
    fi
done < /etc/passwd

echo "==> Adjusting ALSA device permissions (/dev/snd/*)..."
if [ -d /dev/snd ]; then
    chown -R root:audio /dev/snd/* 2>/dev/null
    chmod -R 660 /dev/snd/* 2>/dev/null
    echo "-> Permissions applied successfully."
else
    echo "-> Warning: /dev/snd directory not found. Audio hardware may not be loaded."
fi

echo "==> Setting volume to 100%..."
if command -v amixer >/dev/null 2>&1; then
    amixer set Master 100% unmute 2>/dev/null || amixer set PCM 100% unmute 2>/dev/null
    echo "-> Volume adjusted."
else
    echo "-> Warning: 'amixer' not found, skipping volume adjustment."
fi

echo "==> Running audio test..."
if command -v speaker-test >/dev/null 2>&1; then
    speaker-test -t sine -f 1000 -l 1
else
    echo "Error: command 'speaker-test' not found." >&2
    exit 1
fi
EOF
    chmod +x "${ROOTFS_DIR}/bin/audioconfig"

    mark_step_done "rootfs_config"
}

generate_iso() {
    should_run_step "iso_generation" || return 0

    echo -e "${CYAN}[+] Generating initramfs...${NC}"
    cd "${ROOTFS_DIR}" || exit
    find . | cpio -H newc -o | gzip -9 > "${BUILD_DIR}/initramfs.cpio.gz"
    cd "$ROOT_DIR" || exit

    ISO_CHROOT_DIR="/tmp/iso"
    rm -rf "${ROOTFS_DIR}${ISO_CHROOT_DIR}"
    mkdir -p "${ROOTFS_DIR}${ISO_CHROOT_DIR}/boot/grub/fonts"

    cp "${LINUX_DIR}/arch/x86/boot/bzImage" "${ROOTFS_DIR}${ISO_CHROOT_DIR}/boot/vmlinuz"
    cp "${BUILD_DIR}/initramfs.cpio.gz" "${ROOTFS_DIR}${ISO_CHROOT_DIR}/boot/"

    echo -e "${CYAN}[+] Generating font with compiled grub-mkfont...${NC}"
    if [ ! -x "${ROOTFS_DIR}/usr/bin/grub-mkfont" ]; then
        echo -e "${RED}[ERROR] grub-mkfont not found in the sysroot.${NC}"
        exit 1
    fi
    cp "${SOURCES_DIR}/unifont-15.0.01.pcf.gz" "${ROOTFS_DIR}/tmp/"
    gunzip -c "${ROOTFS_DIR}/tmp/unifont-15.0.01.pcf.gz" > "${ROOTFS_DIR}/tmp/unifont.pcf"
    chroot "${ROOTFS_DIR}" ldconfig 2>&1 | grep -E "freetype|libpng" || true
    if ! chroot "${ROOTFS_DIR}" grub-mkfont -o /tmp/iso/boot/grub/fonts/unicode.pf2 /tmp/unifont.pcf; then
        echo -e "${RED}[ERROR] Failed to generate the font with grub-mkfont.${NC}"
        exit 1
    fi
    rm -f "${ROOTFS_DIR}/tmp/unifont.pcf" "${ROOTFS_DIR}/tmp/unifont-15.0.01.pcf.gz"

    mkdir -p "${ROOTFS_DIR}/usr/share/grub"
    cp "${ROOTFS_DIR}${ISO_CHROOT_DIR}/boot/grub/fonts/unicode.pf2" "${ROOTFS_DIR}/usr/share/grub/unicode.pf2"

    cat > "${ROOTFS_DIR}${ISO_CHROOT_DIR}/boot/grub/grub.cfg" << EOF
insmod all_video
insmod gfxterm
if [ -f /boot/grub/fonts/unicode.pf2 ]; then
    loadfont /boot/grub/fonts/unicode.pf2
    set gfxmode=auto
    terminal_output gfxterm
fi
set timeout=5
set default=0
menuentry "${DISTRO_NAME} ${DISTRO_VERSION} (UEFI Mode - Auto Res)" {
    set gfxpayload=keep
    linux /boot/vmlinuz loglevel=7 console=ttyS0,115200 console=tty0
    initrd /boot/initramfs.cpio.gz
}
menuentry "${DISTRO_NAME} ${DISTRO_VERSION} (BIOS Mode - Standard)" {
    set gfxpayload=text
    linux /boot/vmlinuz nomodeset fbcon=nodefer loglevel=7 console=ttyS0,115200 console=tty0
    initrd /boot/initramfs.cpio.gz
}
EOF

    OUTPUT_ISO="${ROOT_DIR}/${SAFE_DISTRO_NAME}_${SAFE_DISTRO_VERSION}.iso"
    echo -e "${CYAN}[+] Generating ISO via chroot (compiled grub-mkrescue)...${NC}"

    if [ ! -x "${ROOTFS_DIR}/usr/bin/grub-mkrescue" ]; then
        echo -e "${RED}[ERROR] grub-mkrescue not found in chroot.${NC}"
        exit 1
    fi

    mount --bind /dev "${ROOTFS_DIR}/dev"
    mount --bind /proc "${ROOTFS_DIR}/proc"
    mount --bind /sys "${ROOTFS_DIR}/sys"

    chroot "${ROOTFS_DIR}" grub-mkrescue -o /tmp/output.iso /tmp/iso

    umount "${ROOTFS_DIR}/sys"
    umount "${ROOTFS_DIR}/proc"
    umount "${ROOTFS_DIR}/dev"

    if [ -f "${ROOTFS_DIR}/tmp/output.iso" ]; then
        cp "${ROOTFS_DIR}/tmp/output.iso" "$OUTPUT_ISO"
        echo -e "${GREEN}ISO created successfully!${NC}"
    else
        echo -e "${RED}[ERROR] Failed to generate the ISO inside chroot.${NC}"
        exit 1
    fi

    rm -rf "${ROOTFS_DIR}${ISO_CHROOT_DIR}" "${ROOTFS_DIR}/tmp/output.iso" 2>/dev/null || true

    mark_step_done "iso_generation"
}

install_kernel_headers
install_binutils
compile_glibc_full
compile_zstd
compile_libxcrypt
compile_ncurses
compile_perl
compile_make
compile_gcc
compile_zlib
compile_openssl
compile_xz
compile_attr
compile_acl
compile_tar
compile_curl
compile_nano
compile_dropbear
compile_alsa_lib
compile_alsa_utils
compile_kbd
compile_busybox
compile_kernel
compile_libpng
compile_freetype
compile_mtools
compile_grub
compile_xorriso
configure_rootfs
generate_iso

echo -e "\n${BLUE}========================================================${NC}"
echo -e "${CYAN}             INTEGRITY CHECK                 ${NC}"
echo -e "${BLUE}========================================================${NC}"
[ -f "${ROOTFS_DIR}/usr/bin/gcc" ] && echo -e "  ${GREEN}✅ GCC${NC}" || echo -e "  ${RED}❌ GCC${NC}"
[ -f "${ROOTFS_DIR}/usr/bin/make" ] && echo -e "  ${GREEN}✅ Make${NC}" || echo -e "  ${RED}❌ Make${NC}"
[ -f "${ROOTFS_DIR}/bin/busybox" ] && echo -e "  ${GREEN}✅ BusyBox${NC}" || echo -e "  ${RED}❌ BusyBox${NC}"
[ -f "${ROOTFS_DIR}/usr/bin/perl" ] && echo -e "  ${GREEN}✅ Perl${NC}" || echo -e "  ${RED}❌ Perl${NC}"
[ -f "${OUTPUT_ISO}" ] && echo -e "  ${GREEN}✅ ISO${NC}" || echo -e "  ${RED}❌ ISO${NC}"
[ -f "${ROOTFS_DIR}/usr/bin/tar" ] && echo -e "  ${GREEN}✅ GNU Tar (with ACL)${NC}" || echo -e "  ${RED}❌ GNU Tar${NC}"
[ -f "${ROOTFS_DIR}/usr/bin/xz" ] && echo -e "  ${GREEN}✅ XZ${NC}" || echo -e "  ${RED}❌ XZ${NC}"
[ -f "${ROOTFS_DIR}/usr/sbin/grub-install" ] && echo -e "  ${GREEN}✅ GRUB${NC}" || echo -e "  ${RED}❌ GRUB${NC}"
[ -f "${ROOTFS_DIR}/usr/bin/grub-mkfont" ] && echo -e "  ${GREEN}✅ grub-mkfont${NC}" || echo -e "  ${RED}❌ grub-mkfont${NC}"
[ -f "${ROOTFS_DIR}/usr/bin/xorriso" ] && echo -e "  ${GREEN}✅ xorriso${NC}" || echo -e "  ${RED}❌ xorriso${NC}"
[ -f "${ROOTFS_DIR}/usr/bin/setfacl" ] && echo -e "  ${GREEN}✅ setfacl${NC}" || echo -e "  ${RED}❌ setfacl${NC}"
[ -f "${ROOTFS_DIR}/usr/bin/mformat" ] && echo -e "  ${GREEN}✅ mformat${NC}" || echo -e "  ${RED}❌ mformat${NC}"

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))
ELAPSED_MINUTES=$(($ELAPSED / 60))
ELAPSED_SECONDS=$(($ELAPSED % 60))
echo -e "\n${BLUE}========================================================${NC}"
echo -e "${GREEN}🎉 BUILD COMPLETED SUCCESSFULLY!${NC}"
echo -e "${BLUE}========================================================${NC}"
echo -e "💿 ISO:       ${YELLOW}${OUTPUT_ISO}${NC}"
echo -e "🐧 Distro:    ${CYAN}${DISTRO_NAME} ${DISTRO_VERSION}${NC}"
echo -e "⏱️ Time:      ${CYAN}${ELAPSED_MINUTES}m ${ELAPSED_SECONDS}s${NC}"
echo -e "📄 Log:       ${CYAN}${LOG_FILE}${NC}"
echo -e "${BLUE}========================================================${NC}"
