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

export SCRIPTNAME="iSSH2"
export BASEPATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

#Functions

cleanupFail () {
  if [[ "$1" == true ]]; then
    >&2 echo "Build failed, cleaning up temporary files..."
    rm -rf "$LIBSSLDIR/src/" "$LIBSSLDIR/tmp/" "$LIBSSHDIR/src/" "$LIBSSHDIR/tmp/"
  else
    >&2 echo "Build failed, temporary files location: $TEMPPATH"
  fi
  exit 1
}

cleanupAll () {
  if [[ "$1" == true ]]; then
    echo "Cleaning up temporary files..."
    rm -rf "$TEMPPATH"
  else
    echo "Temporary files location: $TEMPPATH"
  fi
}

getLibssh2Version () {
  if type git >/dev/null 2>&1; then
    LIBSSH_VERSION="$(git ls-remote --tags --refs https://github.com/libssh2/libssh2.git \
      | sed -n 's#.*refs/tags/libssh2-\([0-9][0-9.]*[a-zA-Z]*\)$#\1#p' \
      | sort -t . -k1,1nr -k2,2nr -k3,3nr | head -n 1)"
    if [[ -z "$LIBSSH_VERSION" ]]; then
      >&2 echo "Unable to determine the latest Libssh2 version. Use --libssh2=VERS."
      exit 2
    fi
    LIBSSH_AUTO=true
  else
    >&2 echo "Install git to automatically get the latest Libssh2 version or use the --libssh2 argument"
    >&2 echo
    >&2 echo "Try '$SCRIPTNAME --help' for more information."
    exit 2
  fi
}

getOpensslVersion () {
  if type git >/dev/null 2>&1; then
    LIBSSL_VERSION="$(git ls-remote --tags --refs https://github.com/openssl/openssl.git \
      | sed -n \
        -e 's#.*refs/tags/openssl-\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\)$#\1#p' \
        -e 's#.*refs/tags/OpenSSL_\([0-9][0-9]*_[0-9][0-9]*_[0-9][0-9]*\)$#\1#p' \
      | tr '_' '.' \
      | sort -t . -k1,1nr -k2,2nr -k3,3nr \
      | head -n 1)"
    if [[ -z "$LIBSSL_VERSION" ]]; then
      >&2 echo "Unable to determine the latest OpenSSL version. Use --openssl=VERS."
      exit 2
    fi
    LIBSSL_AUTO=true
  else
    >&2 echo "Install git to automatically get the latest OpenSSL version or use the --openssl argument"
    >&2 echo
    >&2 echo "Try '$SCRIPTNAME --help' for more information."
    exit 2
  fi
}

getBuildSetting () {
  printf '%s\n' "$1" | awk -F= -v key="$2" '
    tolower($1) ~ "^[[:space:]]*" tolower(key) "[[:space:]]*$" {
      value=$0
      sub(/^[^=]*=[[:space:]]*/, "", value)
      sub(/[[:space:]]*$/, "", value)
      print value
      exit
    }'
}

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

usageHelp () {
  echo
  echo "Usage: $SCRIPTNAME.sh [options]"
  echo
  echo "This script download and build OpenSSL and Libssh2 libraries."
  echo
  echo "Options:"
  echo "  -a, --archs=[ARCHS]       build for [ARCHS] architectures"
  echo "  -p, --platform=PLATFORM   build for PLATFORM platform"
  echo "  -v, --min-version=VERS    set platform minimum version to VERS"
  echo "  -s, --sdk-version=VERS    use SDK version VERS"
  echo "  -l, --libssh2=VERS        download and build Libssh2 version VERS"
  echo "  -o, --openssl=VERS        download and build OpenSSL version VERS"
  echo "  -x, --xcodeproj=PATH      get info from the project (requires TARGET)"
  echo "  -t, --target=TARGET       get info from the target (requires XCODEPROJ)"
  echo "      --build-only-openssl  build OpenSSL and skip Libssh2"
  echo "      --only-print-env      validate options and print the build environment"
  echo "      --osx                 alias for --platform=macosx"
  echo "      --no-clean            do not clean build folder"
  echo "      --no-bitcode          don't embed bitcode"
  echo "  -h, --help                display this help and exit"
  echo
  echo "Valid platforms: iphoneos, iphonesimulator, macosx, appletvos, appletvsimulator, watchos, watchsimulator"
  echo
  echo "Xcodeproj and target or platform and min version must be set."
  echo
  exit "${1:-0}"
}

#Config

export SDK_VERSION=
export LIBSSH_VERSION=
export LIBSSL_VERSION=
export MIN_VERSION=
export ARCHS=
export SDK_PLATFORM=
export EMBED_BITCODE="-fembed-bitcode"

BUILD_OSX=false
BUILD_SSL=true
BUILD_SSH=true
CLEAN_BUILD=true
ONLY_PRINT_ENV=false

XCODE_PROJECT=
TARGET_NAME=

requireOptionValue () {
  if [[ "$#" -lt 2 ]] || [[ -z "$2" ]]; then
    >&2 echo "$SCRIPTNAME: Option '$1' requires a value."
    >&2 echo "Run '$SCRIPTNAME --help' for more information."
    exit 1
  fi
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    -a|--archs)
      requireOptionValue "$1" "${2:-}"
      ARCHS="$2"
      shift 2
      ;;
    --archs=*) ARCHS="${1#*=}"; requireOptionValue "$1" "$ARCHS"; shift ;;
    -p|--platform)
      requireOptionValue "$1" "${2:-}"
      SDK_PLATFORM="$2"
      shift 2
      ;;
    --platform=*) SDK_PLATFORM="${1#*=}"; requireOptionValue "$1" "$SDK_PLATFORM"; shift ;;
    -v|--min-version)
      requireOptionValue "$1" "${2:-}"
      MIN_VERSION="$2"
      shift 2
      ;;
    --min-version=*) MIN_VERSION="${1#*=}"; requireOptionValue "$1" "$MIN_VERSION"; shift ;;
    -s|--sdk-version)
      requireOptionValue "$1" "${2:-}"
      SDK_VERSION="$2"
      shift 2
      ;;
    --sdk-version=*) SDK_VERSION="${1#*=}"; requireOptionValue "$1" "$SDK_VERSION"; shift ;;
    -l|--libssh2)
      requireOptionValue "$1" "${2:-}"
      LIBSSH_VERSION="$2"
      shift 2
      ;;
    --libssh2=*) LIBSSH_VERSION="${1#*=}"; requireOptionValue "$1" "$LIBSSH_VERSION"; shift ;;
    -o|--openssl)
      requireOptionValue "$1" "${2:-}"
      LIBSSL_VERSION="$2"
      shift 2
      ;;
    --openssl=*) LIBSSL_VERSION="${1#*=}"; requireOptionValue "$1" "$LIBSSL_VERSION"; shift ;;
    -x|--xcodeproj)
      requireOptionValue "$1" "${2:-}"
      XCODE_PROJECT="$2"
      shift 2
      ;;
    --xcodeproj=*) XCODE_PROJECT="${1#*=}"; requireOptionValue "$1" "$XCODE_PROJECT"; shift ;;
    -t|--target)
      requireOptionValue "$1" "${2:-}"
      TARGET_NAME="$2"
      shift 2
      ;;
    --target=*) TARGET_NAME="${1#*=}"; requireOptionValue "$1" "$TARGET_NAME"; shift ;;
    --build-only-openssl) BUILD_SSH=false; shift ;;
    --only-print-env) BUILD_SSL=false; BUILD_SSH=false; ONLY_PRINT_ENV=true; shift ;;
    --osx) BUILD_OSX=true; SDK_PLATFORM="macosx"; shift ;;
    --no-bitcode) EMBED_BITCODE=""; shift ;;
    --no-clean) CLEAN_BUILD=false; shift ;;
    -h|--help) usageHelp 0 ;;
    --) shift; break ;;
    -*)
      >&2 echo "$SCRIPTNAME: Invalid option '$1'"
      >&2 echo "Run '$SCRIPTNAME --help' for more information."
      exit 1
      ;;
    *)
      >&2 echo "$SCRIPTNAME: Unexpected argument '$1'"
      >&2 echo "Run '$SCRIPTNAME --help' for more information."
      exit 1
      ;;
  esac
done

echo "Initializing..."

XCODE_VERSION="$(xcodebuild -version 2>/dev/null | awk '/^Xcode / { print $2; exit }')"
if [[ -z "$XCODE_VERSION" ]]; then
  >&2 echo "$SCRIPTNAME: Xcode was not found. Install Xcode and its command line tools."
  exit 1
fi

if [[ -n "$XCODE_PROJECT" ]] && [[ -z "$TARGET_NAME" ]]; then
  >&2 echo "$SCRIPTNAME: --xcodeproj requires --target."
  exit 1
elif [[ -z "$XCODE_PROJECT" ]] && [[ -n "$TARGET_NAME" ]]; then
  >&2 echo "$SCRIPTNAME: --target requires --xcodeproj."
  exit 1
elif [[ -n "$XCODE_PROJECT" ]] && [[ -n "$TARGET_NAME" ]]; then
  BUILD_SETTINGS="$(xcodebuild -project "$XCODE_PROJECT" -target "$TARGET_NAME" -showBuildSettings 2>/dev/null)"
  SDK_PLATFORM=`getBuildSetting "$BUILD_SETTINGS" "PLATFORM_NAME"`
  MIN_VERSION=`getBuildSetting "$BUILD_SETTINGS" "${SDK_PLATFORM}_DEPLOYMENT_TARGET"`
  TARGET_ARCHS=`getBuildSetting "$BUILD_SETTINGS" "ARCHS"`
  if [[ -z "$TARGET_ARCHS" ]]; then
    TARGET_ARCHS=`getBuildSetting "$BUILD_SETTINGS" "VALID_ARCHS"`
  fi
fi

if [[ -z "$SDK_PLATFORM" ]]; then
  >&2 echo "$SCRIPTNAME: Platform must be specified."
  >&2 echo "Specify --platform=PLATFORM or --xcodeproj=PATH and --target=TARGET"
  >&2 echo
  >&2 echo "Run '$SCRIPTNAME --help' for more information."
  exit 1
fi

if [[ -z "$MIN_VERSION" ]]; then
  >&2 echo "$SCRIPTNAME: Minimum platform version must be specified."
  >&2 echo "Specify --min-version=VERS or --xcodeproj=PATH and --target=TARGET"
  >&2 echo
  >&2 echo "Run '$SCRIPTNAME --help' for more information."
  exit 1
fi

case "$SDK_PLATFORM" in
  iphoneos|iphonesimulator|macosx|appletvos|appletvsimulator|watchos|watchsimulator)
    if [[ -z "$ARCHS" ]]; then
      ARCHS="$TARGET_ARCHS"
    fi

    if [[ -z "$ARCHS" ]]; then
      case "$SDK_PLATFORM" in
        iphoneos|appletvos) ARCHS="arm64" ;;
        watchos) ARCHS="arm64_32" ;;
        iphonesimulator|appletvsimulator|watchsimulator) ARCHS="arm64 x86_64" ;;
        macosx) ARCHS="arm64 x86_64" ;;
      esac
    fi
    ;;
  *)
  >&2 echo "$SCRIPTNAME: Unknown platform '$SDK_PLATFORM'"
  >&2 echo "Run '$SCRIPTNAME --help' for more information."
  exit 1
  ;;
esac

if [[ "$SDK_PLATFORM" == "macosx" ]]; then
  # Bitcode is an Apple-platform feature and is not valid for macOS targets.
  EMBED_BITCODE=""
fi

ARCHS="$(printf '%s\n' "$ARCHS" | tr ', ' '\n\n' | awk 'NF' | sort -u | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
if [[ -z "$ARCHS" ]]; then
  >&2 echo "$SCRIPTNAME: At least one architecture must be specified."
  exit 1
fi

LIBSSH_AUTO=false
if [[ -z "$LIBSSH_VERSION" ]]; then
  getLibssh2Version
fi

LIBSSL_AUTO=false
if [[ -z "$LIBSSL_VERSION" ]]; then
  getOpensslVersion
fi

SDK_AUTO=false
if [[ -z "$SDK_VERSION" ]]; then
   SDK_VERSION="$(xcrun --sdk "$SDK_PLATFORM" --show-sdk-version 2>/dev/null)"
   if [[ -z "$SDK_VERSION" ]]; then
     >&2 echo "$SCRIPTNAME: Unable to determine the SDK version for '$SDK_PLATFORM'."
     exit 1
   fi
   SDK_AUTO=true
fi

BUILD_THREADS=""
if command -v sysctl >/dev/null 2>&1; then
  BUILD_THREADS="$(sysctl -n hw.ncpu 2>/dev/null || true)"
fi
if [[ ! "$BUILD_THREADS" =~ ^[1-9][0-9]*$ ]]; then
  BUILD_THREADS="$(getconf _NPROCESSORS_ONLN 2>/dev/null || true)"
fi
if [[ ! "$BUILD_THREADS" =~ ^[1-9][0-9]*$ ]]; then
  BUILD_THREADS=1
fi
export BUILD_THREADS

export CLANG="$(xcrun --find clang 2>/dev/null)"
export GCC="$(xcrun --find gcc 2>/dev/null || true)"
export DEVELOPER="$(xcode-select --print-path 2>/dev/null)"

if [[ -z "$CLANG" ]] || [[ -z "$DEVELOPER" ]]; then
  >&2 echo "$SCRIPTNAME: Xcode command line tools are not configured."
  exit 1
fi

export TEMPPATH="${TMPDIR:-/tmp}/$SCRIPTNAME"
export LIBSSLDIR="$TEMPPATH/openssl-$LIBSSL_VERSION"
export LIBSSHDIR="$TEMPPATH/libssh2-$LIBSSH_VERSION"

#Env

echo
if [[ $LIBSSH_AUTO == true ]]; then
  echo "Libssh2 version: $LIBSSH_VERSION (Automatically detected)"
else
  echo "Libssh2 version: $LIBSSH_VERSION"
fi

if [[ $LIBSSL_AUTO == true ]]; then
  echo "OpenSSL version: $LIBSSL_VERSION (Automatically detected)"
else
  echo "OpenSSL version: $LIBSSL_VERSION"
fi

if [[ $SDK_AUTO == true ]]; then
  echo "SDK version: $SDK_VERSION (Automatically detected)"
else
  echo "SDK version: $SDK_VERSION"
fi

echo "Xcode version: $XCODE_VERSION (Automatically detected)"
echo "Architectures: $ARCHS"
echo "Platform: $SDK_PLATFORM"
echo "Platform min version: $MIN_VERSION"
echo

#Build

set -e

if [[ $BUILD_SSL == true ]]; then
  "$BASEPATH/iSSH2-openssl.sh" || cleanupFail "$CLEAN_BUILD"
fi

if [[ $BUILD_SSH == true ]]; then
  "$BASEPATH/iSSH2-libssh2.sh" || cleanupFail "$CLEAN_BUILD"
fi

if [[ $BUILD_SSL == true ]] || [[ $BUILD_SSH == true ]]; then
  cleanupAll "$CLEAN_BUILD"
fi
