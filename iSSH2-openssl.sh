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

XCODE_VERSION="$(xcodebuild -version 2>/dev/null | awk '/^Xcode / { print $2; exit }')"

version () {
  local value="${1:-0}"
  local major="${value%%.*}"
  local rest="${value#*.}"
  local minor="0"
  local patch="0"
  if [[ "$rest" != "$value" ]]; then
    minor="${rest%%.*}"
    rest="${rest#*.}"
    if [[ "$rest" != "$minor" ]]; then
      patch="${rest%%.*}"
    fi
  fi
  printf "%02d%02d%02d" "$major" "$minor" "$patch"
}

selectConfigureTarget () {
  local candidate
  local candidates

  case "$SDK_PLATFORM:$ARCH" in
    macosx:arm64) candidates="darwin64-arm64 darwin64-arm64-cc" ;;
    macosx:x86_64) candidates="darwin64-x86_64 darwin64-x86_64-cc" ;;
    iphoneos:arm64*) candidates="ios64-xcrun ios64-cross iphoneos-cross" ;;
    iphoneos:*) candidates="ios-xcrun ios-cross iphoneos-cross" ;;
    iphonesimulator:arm64*) candidates="iossimulator-arm64-xcrun ios64-cross iphoneos-cross" ;;
    iphonesimulator:x86_64) candidates="iossimulator-x86_64-xcrun iphoneos-cross darwin64-x86_64" ;;
    appletvsimulator:arm64*) candidates="darwin64-arm64" ;;
    appletvsimulator:x86_64) candidates="darwin64-x86_64" ;;
    watchsimulator:arm64*) candidates="darwin64-arm64" ;;
    watchsimulator:x86_64) candidates="darwin64-x86_64" ;;
    appletvos:arm64*|watchos:arm64*) candidates="darwin64-arm64" ;;
    *) candidates="darwin64-x86_64" ;;
  esac

  for candidate in $candidates; do
    if ./Configure LIST 2>/dev/null | grep -Eq "(^|[[:space:]])${candidate}([[:space:]]|$)"; then
      echo "$candidate"
      return 0
    fi
  done

  echo "No compatible OpenSSL Configure target was found for $SDK_PLATFORM/$ARCH." >&2
  return 1
}

set -e

mkdir -p "$LIBSSLDIR"

LIBSSL_TAR="openssl-$LIBSSL_VERSION.tar.gz"

#LIBSSL_TAR="openssl-3.5.0.tar.gz"

if ! downloadFile "https://github.com/openssl/openssl/releases/download/openssl-$LIBSSL_VERSION/$LIBSSL_TAR" "$LIBSSLDIR/$LIBSSL_TAR"; then
  downloadFile "https://www.openssl.org/source/$LIBSSL_TAR" "$LIBSSLDIR/$LIBSSL_TAR"
fi

LIBSSLSRC="$LIBSSLDIR/src/"
rm -rf "$LIBSSLSRC"
mkdir -p "$LIBSSLSRC"

echo "Extracting $LIBSSL_TAR"
tar -xzf "$LIBSSLDIR/$LIBSSL_TAR" -C "$LIBSSLSRC" --strip-components 1

echo "Building OpenSSL $LIBSSL_VERSION, please wait..."

LIPO_LIBSSL=()
LIPO_LIBCRYPTO=()

for ARCH in $ARCHS
do
  if [[ "$SDK_PLATFORM" == "macosx" ]]; then
    CONF=(no-shared no-async)
  else
    CONF=(no-asm no-hw no-shared no-async)
  fi

  PLATFORM="$(platformName "$SDK_PLATFORM" "$ARCH")"
  OPENSSLDIR="$LIBSSLDIR/${PLATFORM}_$SDK_VERSION-$ARCH"
  LIPO_LIBSSL+=("$OPENSSLDIR/libssl.a")
  LIPO_LIBCRYPTO+=("$OPENSSLDIR/libcrypto.a")

  if [[ -f "$OPENSSLDIR/libssl.a" ]] && [[ -f "$OPENSSLDIR/libcrypto.a" ]]; then
    echo "libssl.a and libcrypto.a for $ARCH already exist."
  else
    rm -rf "$OPENSSLDIR"
    mkdir -p "$OPENSSLDIR"
    cp -R "$LIBSSLSRC/." "$OPENSSLDIR/"
    cd "$OPENSSLDIR"

    LOG="$OPENSSLDIR/build-openssl.log"
    : > "$LOG"

    SDKROOT="$(xcrun --sdk "$SDK_PLATFORM" --show-sdk-path)"
    DEPLOYMENT_FLAG="$(deploymentTargetFlag "$SDK_PLATFORM")"
    HOST="$(selectConfigureTarget)"

    export CROSS_TOP="$DEVELOPER/Platforms/$PLATFORM.platform/Developer"
    export CROSS_SDK="$(basename "$SDKROOT")"
    export SDKROOT
    if [[ "$HOST" == *-xcrun ]]; then
      # The xcrun targets select the compiler themselves.  CROSS_COMPILE must
      # remain empty or OpenSSL prefixes the absolute compiler path twice.
      export CROSS_COMPILE=""
      export CC="$CLANG"
    else
      export CROSS_COMPILE="$DEVELOPER/Toolchains/XcodeDefault.xctoolchain/usr/bin/"
      export CC="clang"
    fi
    export CFLAGS="-arch $ARCH -isysroot $SDKROOT $DEPLOYMENT_FLAG=$MIN_VERSION ${EMBED_BITCODE:-}"
    export CPPFLAGS="$CFLAGS"
    export LDFLAGS="-arch $ARCH -isysroot $SDKROOT $DEPLOYMENT_FLAG=$MIN_VERSION"

    echo "Configuring OpenSSL target $HOST for $PLATFORM/$ARCH"
    ./Configure "$HOST" "${CONF[@]}" --prefix="$OPENSSLDIR" >> "$LOG" 2>&1

    make -j "$BUILD_THREADS" build_libs >> "$LOG" 2>&1

    echo "- $PLATFORM $ARCH done!"
  fi
done

lipoFatLibrary "$BASEPATH/openssl_$SDK_PLATFORM/lib/libssl.a" "${LIPO_LIBSSL[@]}"
lipoFatLibrary "$BASEPATH/openssl_$SDK_PLATFORM/lib/libcrypto.a" "${LIPO_LIBCRYPTO[@]}"

importHeaders "$OPENSSLDIR/include/" "$BASEPATH/openssl_$SDK_PLATFORM/include"

echo "Building done."
