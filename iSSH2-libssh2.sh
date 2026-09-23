#!/bin/bash
                                   #########
#################################### iSSH2 #####################################
#                                  #########                                   #
# Copyright (c) 2013 Tommaso Madonia. All rights reserved.                     #
#                                                                              #
# Permission is hereby granted, free of charge, to any person obtaining a copy #
# of this software and associated documentation files (the "Software"), to deal#
# in the Software without restriction, including without limitation the rights #
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell    #
# copies of the Software, and to permit persons to whom the Software is        #
# furnished to do so, subject to the following conditions:                     #
#                                                                              #
# The above copyright notice and this permission notice shall be included in   #
# all copies or substantial portions of the Software.                          #
#                                                                              #
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR   #
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,     #
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE  #
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER       #
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,#
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN    #
# THE SOFTWARE.                                                                #
################################################################################

if [[ -z "${BASEPATH:-}" ]]; then
  BASEPATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
fi

source "$BASEPATH/iSSH2-commons"

set -e

mkdir -p "$LIBSSHDIR"

LIBSSH_TAR="libssh2-$LIBSSH_VERSION.tar.gz"

if ! downloadFile "https://github.com/libssh2/libssh2/releases/download/libssh2-$LIBSSH_VERSION/$LIBSSH_TAR" "$LIBSSHDIR/$LIBSSH_TAR"; then
  downloadFile "https://www.libssh2.org/download/$LIBSSH_TAR" "$LIBSSHDIR/$LIBSSH_TAR"
fi

LIBSSHSRC="$LIBSSHDIR/src/"
rm -rf "$LIBSSHSRC"
mkdir -p "$LIBSSHSRC"

echo "Extracting $LIBSSH_TAR"
tar -xzf "$LIBSSHDIR/$LIBSSH_TAR" -C "$LIBSSHSRC" --strip-components 1

echo "Building Libssh2 $LIBSSH_VERSION:"

LIPO_SSH2=()

for ARCH in $ARCHS
do
  PLATFORM="$(platformName "$SDK_PLATFORM" "$ARCH")"
  OPENSSLDIR="$BASEPATH/openssl_$SDK_PLATFORM"
  PLATFORM_SRC="$LIBSSHDIR/${PLATFORM}_$SDK_VERSION-$ARCH/src"
  PLATFORM_OUT="$LIBSSHDIR/${PLATFORM}_$SDK_VERSION-$ARCH/install"
  LIPO_SSH2+=("$PLATFORM_OUT/lib/libssh2.a")

  if [[ -f "$PLATFORM_OUT/lib/libssh2.a" ]]; then
    echo "libssh2.a for $ARCH already exists."
  else
    rm -rf "$PLATFORM_SRC"
    rm -rf "$PLATFORM_OUT"
    mkdir -p "$PLATFORM_OUT"
    mkdir -p "$PLATFORM_SRC"
    cp -R "$LIBSSHSRC/." "$PLATFORM_SRC/"
    cd "$PLATFORM_SRC"

    LOG="$PLATFORM_OUT/build-libssh2.log"
    : > "$LOG"

    case "$ARCH" in
      arm64*) HOST="aarch64-apple-darwin" ;;
      armv7*) HOST="arm-apple-darwin" ;;
      *) HOST="$ARCH-apple-darwin" ;;
    esac

    SDKROOT="$(xcrun --sdk "$SDK_PLATFORM" --show-sdk-path)"
    DEPLOYMENT_FLAG="$(deploymentTargetFlag "$SDK_PLATFORM")"
    export DEVROOT="$DEVELOPER/Platforms/$PLATFORM.platform/Developer"
    export SDKROOT
    export CC="$CLANG"
    export CPP="$CLANG -E"
    export CFLAGS="-arch $ARCH -pipe -isysroot $SDKROOT $DEPLOYMENT_FLAG=$MIN_VERSION ${EMBED_BITCODE:-}"
    export CPPFLAGS="$CFLAGS"
    export LDFLAGS="-arch $ARCH -isysroot $SDKROOT $DEPLOYMENT_FLAG=$MIN_VERSION"

    if ./configure --help 2>/dev/null | grep -q -- '--with-crypto'; then
      CRYPTO_BACKEND_OPTIONS=(--with-crypto=openssl)
    else
      CRYPTO_BACKEND_OPTIONS=(--with-openssl)
    fi

    ./configure \
      --host="$HOST" \
      --prefix="$PLATFORM_OUT" \
      --disable-debug \
      --disable-dependency-tracking \
      --disable-silent-rules \
      --disable-examples-build \
      --with-libz \
      "${CRYPTO_BACKEND_OPTIONS[@]}" \
      --with-libssl-prefix="$OPENSSLDIR" \
      --disable-shared \
      --enable-static >> "$LOG" 2>&1

    make -j "$BUILD_THREADS" >> "$LOG" 2>&1
    make -j "$BUILD_THREADS" install >> "$LOG" 2>&1

    echo "- $PLATFORM $ARCH done!"
  fi
done

lipoFatLibrary "$BASEPATH/libssh2_$SDK_PLATFORM/lib/libssh2.a" "${LIPO_SSH2[@]}"

importHeaders "$LIBSSHSRC/include/" "$BASEPATH/libssh2_$SDK_PLATFORM/include"

echo "Building done."
