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

# version will be (e.g.) "1.4.0"
version="1.3.2"

echo "${version}" > "${stage}/VERSION.txt"

# Create the staging folders
mkdir -p "$stage/lib"/{debug,release}
mkdir -p "$stage/include/webp"
mkdir -p "$stage/LICENSES"

pushd "$LIBWEBP_SOURCE_DIR"
    case "$AUTOBUILD_PLATFORM" in
        # ------------------------ windows, windows64 ------------------------
        windows*)
            load_vsvars

            if [ "$AUTOBUILD_ADDRSIZE" = 32 ]
            then
                archflag="x86"
            else
                archflag="x64"
            fi

            nmake /f Makefile.vc CFG=debug-static RTLIBCFG=dynamic OBJDIR=output ARCH=$archflag
            nmake /f Makefile.vc CFG=release-static RTLIBCFG=dynamic OBJDIR=output ARCH=$archflag

            cp -a output/debug-static/$archflag/lib/*.lib $stage/lib/debug/
            cp -a output/release-static/$archflag/lib/*.lib $stage/lib/release/

            cp -a src/webp/decode.h $stage/include/webp/
            cp -a src/webp/encode.h $stage/include/webp/
            cp -a src/webp/types.h $stage/include/webp/
        ;;

        darwin*)
            # Setup build flags
            C_OPTS_X86="-arch x86_64 $LL_BUILD_RELEASE_CFLAGS"
            C_OPTS_ARM64="-arch arm64 $LL_BUILD_RELEASE_CFLAGS"
            CXX_OPTS_X86="-arch x86_64 $LL_BUILD_RELEASE_CXXFLAGS"
            CXX_OPTS_ARM64="-arch arm64 $LL_BUILD_RELEASE_CXXFLAGS"
            LINK_OPTS_X86="-arch x86_64 $LL_BUILD_RELEASE_LINKER"
            LINK_OPTS_ARM64="-arch arm64 $LL_BUILD_RELEASE_LINKER"

            # deploy target
            export MACOSX_DEPLOYMENT_TARGET=${LL_BUILD_DARWIN_BASE_DEPLOY_TARGET}

            mkdir -p "build_release"
            pushd "build_release"
                CFLAGS="$C_OPTS_X86" \
                CXXFLAGS="$CXX_OPTS_X86" \
                LDFLAGS="$LINK_OPTS_X86" \
                cmake .. -G Ninja -DCMAKE_BUILD_TYPE="Release" \
                    -DBUILD_SHARED_LIBS=OFF -DWEBP_BUILD_ANIM_UTILS=OFF \
                    -DWEBP_BUILD_CWEBP=OFF -DWEBP_BUILD_DWEBP=OFF \
                    -DWEBP_BUILD_EXTRAS=OFF -DWEBP_BUILD_GIF2WEBP=OFF \
                    -DWEBP_BUILD_IMG2WEBP=OFF -DWEBP_BUILD_VWEBP=OFF \
                    -DWEBP_BUILD_WEBPINFO=OFF -DWEBP_BUILD_WEBPMUX=OFF \
                    -DCMAKE_C_FLAGS="$C_OPTS_X86" \
                    -DCMAKE_CXX_FLAGS="$CXX_OPTS_X86" \
                    -DCMAKE_OSX_ARCHITECTURES:STRING=x86_64 \
                    -DCMAKE_OSX_DEPLOYMENT_TARGET=${MACOSX_DEPLOYMENT_TARGET} \
                    -DCMAKE_MACOSX_RPATH=YES \
                    -DCMAKE_C_VISIBILITY_PRESET="hidden" \
                    -DCMAKE_CXX_VISIBILITY_PRESET="hidden" \
                    -DCMAKE_INSTALL_PREFIX=$stage

                cmake --build . -j$AUTOBUILD_CPU_COUNT --config Release

                cp -a *.a* "${stage}/lib/release/"
            popd

            # pushd "${stage}/lib/release"
            #     fix_dylib_id "libwebp.dylib"
            #     fix_dylib_id "libwebpdecoder.dylib"
            #     fix_dylib_id "libwebpdemux.dylib"
            #     dsymutil libwebp.dylib
            #     dsymutil libwebpdecoder.dylib
            #     dsymutil libwebpdemux.dylib
            #     strip -x -S libwebp.dylib
            #     strip -x -S libwebpdecoder.dylib
            #     strip -x -S libwebpdemux.dylib
            # popd

            cp -a src/webp/decode.h $stage/include/webp/
            cp -a src/webp/encode.h $stage/include/webp/
            cp -a src/webp/types.h $stage/include/webp/
        ;;
        linux*)
            # Linux build environment at Linden comes pre-polluted with stuff that can
            # seriously damage 3rd-party builds.  Environmental garbage you can expect
            # includes:
            #
            #    DISTCC_POTENTIAL_HOSTS     arch           root        CXXFLAGS
            #    DISTCC_LOCATION            top            branch      CC
            #    DISTCC_HOSTS               build_name     suffix      CXX
            #    LSDISTCC_ARGS              repo           prefix      CFLAGS
            #    cxx_version                AUTOBUILD      SIGN        CPPFLAGS
            #
            # So, clear out bits that shouldn't affect our configure-directed build
            # but which do nonetheless.
            #
            unset DISTCC_HOSTS CFLAGS CPPFLAGS CXXFLAGS

            # Default target per --address-size
            opts_c="${TARGET_OPTS:--m$AUTOBUILD_ADDRSIZE $LL_BUILD_RELEASE_CFLAGS}"
            opts_cxx="${TARGET_OPTS:--m$AUTOBUILD_ADDRSIZE $LL_BUILD_RELEASE_CXXFLAGS}"

            # Handle any deliberate platform targeting
            if [ -z "${TARGET_CPPFLAGS:-}" ]; then
                # Remove sysroot contamination from build environment
                unset CPPFLAGS
            else
                # Incorporate special pre-processing flags
                export CPPFLAGS="$TARGET_CPPFLAGS"
            fi

            # force regenerate autoconf
            autoreconf -fvi

            mkdir -p "build_release"
            pushd "build_release"
                # Release configure and build
                CFLAGS="$opts_c" \
                CXXFLAGS="$opts_cxx" \
                ../configure --enable-static --disable-shared \
                    --enable-libwebpmux --enable-libwebpdemux --enable-libwebpdecoder --enable-libwebpextras \
                    --prefix="\${AUTOBUILD_PACKAGES_DIR}" --includedir="\${prefix}/include" --libdir="\${prefix}/lib/release"
                make -j$AUTOBUILD_CPU_COUNT
                make check
                make install DESTDIR="$stage"

                # conditionally run unit tests
                if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                    make check
                fi
            popd
        ;;
    esac

    mkdir -p "$stage/LICENSES"
    cp COPYING "$stage/LICENSES/libwebp.txt"
popd
