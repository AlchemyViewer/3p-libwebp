#!/usr/bin/env bash

cd "$(dirname "$0")"

# turn on verbose debugging output for parabuild logs.
exec 4>&1; export BASH_XTRACEFD=4; set -x

# make errors fatal
set -e
# bleat on references to undefined shell variables
set -u

# Check autobuild is around or fail
if [ -z "$AUTOBUILD" ] ; then
    exit 1
fi
if [ "$OSTYPE" = "cygwin" ] ; then
    export AUTOBUILD="$(cygpath -u $AUTOBUILD)"
fi

top="$(pwd)"
stage="$(pwd)/stage"

mkdir -p "${stage}"

# Load autobuild provided shell functions and variables
source_environment_tempfile="$stage/source_environment.sh"
"$AUTOBUILD" source_environment > "$source_environment_tempfile"
. "$source_environment_tempfile"

LIBWEBP_SOURCE_DIR="libwebp"

# used in VERSION.txt but common to all bit-widths and platforms
build=${AUTOBUILD_BUILD_ID:=0}

# version will be (e.g.) "1.4.0"
version="1.1.0"

echo "${version}.${build}" > "${stage}/VERSION.txt"

# Create the staging folders
mkdir -p "$stage/lib"/{debug,release}
mkdir -p "$stage/include/webp"
mkdir -p "$stage/LICENSES"

pushd "$LIBWEBP_SOURCE_DIR"
    case "$AUTOBUILD_PLATFORM" in
        # ------------------------ windows, windows64 ------------------------
        windows*)
            load_vsvars

            nmake /f Makefile.vc CFG=debug-static RTLIBCFG=dynamic OBJDIR=output
            nmake /f Makefile.vc CFG=release-static RTLIBCFG=dynamic OBJDIR=output

            if [ "$AUTOBUILD_ADDRSIZE" = 32 ]
            then
                outarchdir="x86"
            else
                outarchdir="x64"
            fi

            cp -a output/debug-static/$outarchdir/lib/*.lib $stage/lib/debug/
            cp -a output/debug-static/$outarchdir/lib/*.pdb $stage/lib/debug/

            cp -a output/release-static/$outarchdir/lib/*.lib $stage/lib/release/
        ;;

        darwin*)
      
        ;;
        linux*)

        ;;
    esac

    cp -a src/webp/decode.h $stage/include/webp/
    cp -a src/webp/encode.h $stage/include/webp/
    cp -a src/webp/types.h $stage/include/webp/

    mkdir -p "$stage/LICENSES"
    cp COPYING "$stage/LICENSES/libwebp.txt"
popd
