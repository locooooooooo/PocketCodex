vcpkg_from_git(
    OUT_SOURCE_PATH SOURCE_PATH
    URL "https://aomedia.googlesource.com/aom"
    REF d6f30ae474dd6c358f26de0a0fc26a0d7340a84c
    HEAD_REF main
    PATCHES
        aom-rename-static.diff
        aom-uninitialized-pointer.diff
        export-config.diff
)

vcpkg_find_acquire_program(PERL)

vcpkg_cmake_configure(
    SOURCE_PATH ${SOURCE_PATH}
    OPTIONS
        -DAOM_TARGET_CPU=generic
        -DENABLE_DOCS=OFF
        -DENABLE_EXAMPLES=OFF
        -DENABLE_TESTDATA=OFF
        -DENABLE_TESTS=OFF
        -DENABLE_TOOLS=OFF
        -DTHREADS_PREFER_PTHREAD_FLAG=ON
        "-DPERL_EXECUTABLE=${PERL}"
)

vcpkg_cmake_install()
vcpkg_cmake_config_fixup()
vcpkg_copy_pdbs()
vcpkg_fixup_pkgconfig()

file(REMOVE_RECURSE
    "${CURRENT_PACKAGES_DIR}/debug/include"
    "${CURRENT_PACKAGES_DIR}/debug/share"
)

vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/LICENSE")
