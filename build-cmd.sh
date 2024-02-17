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
            # Setup osx sdk platform
            SDKNAME="macosx"
            export SDKROOT=$(xcodebuild -version -sdk ${SDKNAME} Path)
            export MACOSX_DEPLOYMENT_TARGET=10.15

            # Setup build flags
            ARCH_FLAGS="-arch x86_64"
            SDK_FLAGS="-mmacosx-version-min=${MACOSX_DEPLOYMENT_TARGET} -isysroot ${SDKROOT}"
            DEBUG_COMMON_FLAGS="$ARCH_FLAGS $SDK_FLAGS -O0 -g -msse4.2 -fPIC -DPIC"
            RELEASE_COMMON_FLAGS="$ARCH_FLAGS $SDK_FLAGS -Ofast -ffast-math -g -msse4.2 -fPIC -DPIC -fstack-protector-strong"
            DEBUG_CFLAGS="$DEBUG_COMMON_FLAGS"
            RELEASE_CFLAGS="$RELEASE_COMMON_FLAGS"
            DEBUG_CXXFLAGS="$DEBUG_COMMON_FLAGS -std=c++17"
            RELEASE_CXXFLAGS="$RELEASE_COMMON_FLAGS -std=c++17"
            DEBUG_CPPFLAGS="-DPIC"
            RELEASE_CPPFLAGS="-DPIC"
            DEBUG_LDFLAGS="$ARCH_FLAGS $SDK_FLAGS -Wl,-headerpad_max_install_names"
            RELEASE_LDFLAGS="$ARCH_FLAGS $SDK_FLAGS -Wl,-headerpad_max_install_names"

            JOBS=`sysctl -n hw.ncpu`

            mkdir -p "build_debug"
            pushd "build_debug"
                CFLAGS="$DEBUG_CFLAGS" \
                CXXFLAGS="$DEBUG_CXXFLAGS" \
                CPPFLAGS="$DEBUG_CPPFLAGS" \
                LDFLAGS="$DEBUG_LDFLAGS" \
                cmake .. -G"Unix Makefiles" -DCMAKE_BUILD_TYPE="Debug" \
                    -DBUILD_SHARED_LIBS=OFF -DWEBP_BUILD_ANIM_UTILS=OFF \
                    -DWEBP_BUILD_CWEBP=OFF -DWEBP_BUILD_DWEBP=OFF \
                    -DWEBP_BUILD_EXTRAS=OFF -DWEBP_BUILD_GIF2WEBP=OFF \
                    -DWEBP_BUILD_IMG2WEBP=OFF -DWEBP_BUILD_VWEBP=OFF \
                    -DWEBP_BUILD_WEBPINFO=OFF -DWEBP_BUILD_WEBPMUX=OFF \
                    -DCMAKE_C_FLAGS="$DEBUG_CFLAGS" \
                    -DCMAKE_CXX_FLAGS="$DEBUG_CXXFLAGS" \
                    -DCMAKE_OSX_ARCHITECTURES:STRING=x86_64 \
                    -DCMAKE_OSX_DEPLOYMENT_TARGET=${MACOSX_DEPLOYMENT_TARGET} \
                    -DCMAKE_OSX_SYSROOT=${SDKROOT} \
                    -DCMAKE_MACOSX_RPATH=YES \
                    -DCMAKE_C_VISIBILITY_PRESET="hidden" \
                    -DCMAKE_CXX_VISIBILITY_PRESET="hidden" \
                    -DCMAKE_INSTALL_PREFIX=$stage

                cmake --build . -j$JOBS --config Debug

                cp -a *.a* "${stage}/lib/debug/"
            popd

            mkdir -p "build_release"
            pushd "build_release"
                CFLAGS="$RELEASE_CFLAGS" \
                CXXFLAGS="$RELEASE_CXXFLAGS" \
                CPPFLAGS="$RELEASE_CPPFLAGS" \
                LDFLAGS="$RELEASE_LDFLAGS" \
                cmake .. -G"Unix Makefiles" -DCMAKE_BUILD_TYPE="Release" \
                    -DBUILD_SHARED_LIBS=OFF -DWEBP_BUILD_ANIM_UTILS=OFF \
                    -DWEBP_BUILD_CWEBP=OFF -DWEBP_BUILD_DWEBP=OFF \
                    -DWEBP_BUILD_EXTRAS=OFF -DWEBP_BUILD_GIF2WEBP=OFF \
                    -DWEBP_BUILD_IMG2WEBP=OFF -DWEBP_BUILD_VWEBP=OFF \
                    -DWEBP_BUILD_WEBPINFO=OFF -DWEBP_BUILD_WEBPMUX=OFF \
                    -DCMAKE_C_FLAGS="$RELEASE_CFLAGS" \
                    -DCMAKE_CXX_FLAGS="$RELEASE_CXXFLAGS" \
                    -DCMAKE_OSX_ARCHITECTURES:STRING=x86_64 \
                    -DCMAKE_OSX_DEPLOYMENT_TARGET=${MACOSX_DEPLOYMENT_TARGET} \
                    -DCMAKE_OSX_SYSROOT=${SDKROOT} \
                    -DCMAKE_MACOSX_RPATH=YES \
                    -DCMAKE_C_VISIBILITY_PRESET="hidden" \
                    -DCMAKE_CXX_VISIBILITY_PRESET="hidden" \
                    -DCMAKE_INSTALL_PREFIX=$stage

                cmake --build . -j$JOBS --config Release

                cp -a *.a* "${stage}/lib/release/"
            popd

            # For dynamic library builds
            # pushd "${stage}/lib/debug"
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
            # Default target per --address-size
            opts="${TARGET_OPTS:--m$AUTOBUILD_ADDRSIZE}"

            # Setup build flags
            DEBUG_COMMON_FLAGS="$opts -Og -g -fPIC -DPIC"
            RELEASE_COMMON_FLAGS="$opts -O3 -g -fPIC -DPIC -fstack-protector-strong -D_FORTIFY_SOURCE=2"
            DEBUG_CFLAGS="$DEBUG_COMMON_FLAGS"
            RELEASE_CFLAGS="$RELEASE_COMMON_FLAGS"
            DEBUG_CXXFLAGS="$DEBUG_COMMON_FLAGS -std=c++17"
            RELEASE_CXXFLAGS="$RELEASE_COMMON_FLAGS -std=c++17"
            DEBUG_CPPFLAGS="-DPIC"
            RELEASE_CPPFLAGS="-DPIC"

            JOBS=`cat /proc/cpuinfo | grep processor | wc -l`

            # Handle any deliberate platform targeting
            if [ -z "${TARGET_CPPFLAGS:-}" ]; then
                # Remove sysroot contamination from build environment
                unset CPPFLAGS
            else
                # Incorporate special pre-processing flags
                export CPPFLAGS="$TARGET_CPPFLAGS"
            fi

            # Fix up path for pkgconfig
            if [ -d "$stage/packages/lib/release/pkgconfig" ]; then
                fix_pkgconfig_prefix "$stage/packages"
            fi

            OLD_PKG_CONFIG_PATH="${PKG_CONFIG_PATH:-}"

            # force regenerate autoconf
            autoreconf -fvi

            mkdir -p "build_debug"
            pushd "build_debug"
                # debug configure and build
                export PKG_CONFIG_PATH="$stage/packages/lib/debug/pkgconfig:${OLD_PKG_CONFIG_PATH}"

                CFLAGS="$DEBUG_CFLAGS" \
                CXXFLAGS="$DEBUG_CXXFLAGS" \
                ../configure --enable-static --disable-shared \
                    --enable-libwebpmux --enable-libwebpdemux --enable-libwebpdecoder --enable-libwebpextras \
                    --prefix="\${AUTOBUILD_PACKAGES_DIR}" --includedir="\${prefix}/include" --libdir="\${prefix}/lib/debug"
                make -j$JOBS
                make check
                make install DESTDIR="$stage"

                # conditionally run unit tests
                if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                    make check
                fi
            popd

            mkdir -p "build_release"
            pushd "build_release"
                # Release configure and build
                export PKG_CONFIG_PATH="$stage/packages/lib/release/pkgconfig:${OLD_PKG_CONFIG_PATH}"

                CFLAGS="$RELEASE_CFLAGS" \
                CXXFLAGS="$RELEASE_CXXFLAGS" \
                ../configure --enable-static --disable-shared \
                    --enable-libwebpmux --enable-libwebpdemux --enable-libwebpdecoder --enable-libwebpextras \
                    --prefix="\${AUTOBUILD_PACKAGES_DIR}" --includedir="\${prefix}/include" --libdir="\${prefix}/lib/release"
                make -j$JOBS
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
