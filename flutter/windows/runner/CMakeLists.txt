cmake_minimum_required(VERSION 3.14)
project(runner LANGUAGES CXX)

# Define the application target. To change its name, change BINARY_NAME in the
# top-level CMakeLists.txt, not the value here, or `flutter run` will no longer
# work.
#
# Any new source files that you add to the application should be added here.
add_executable(${BINARY_NAME} WIN32
  "flutter_window.cpp"
  "main.cpp"
  "utils.cpp"
  "win32_desktop.cpp"
  "win32_window.cpp"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
  "Runner.rc"
  "runner.exe.manifest"
)

# Apply the standard set of build settings. This can be removed for applications
# that need different build settings.
apply_standard_settings(${BINARY_NAME})

# Keep the Windows runner metadata aligned with the Rust runtime version.
file(STRINGS "${CMAKE_CURRENT_SOURCE_DIR}/../../../Cargo.toml"
  RUSTDESK_CARGO_VERSION_LINE
  REGEX "^version *= *\"[^\"]+\""
  LIMIT_COUNT 1)

if(NOT RUSTDESK_CARGO_VERSION_LINE)
  message(FATAL_ERROR "Failed to read RustDesk version from Cargo.toml")
endif()

string(REGEX REPLACE "^version *= *\"([^\"]+)\".*" "\\1"
  RUSTDESK_VERSION "${RUSTDESK_CARGO_VERSION_LINE}")
string(REGEX REPLACE "[-+].*$" "" RUSTDESK_VERSION "${RUSTDESK_VERSION}")
string(REPLACE "." ";" RUSTDESK_VERSION_PARTS "${RUSTDESK_VERSION}")
list(LENGTH RUSTDESK_VERSION_PARTS RUSTDESK_VERSION_PARTS_LEN)

set(RUSTDESK_VERSION_MAJOR 0)
set(RUSTDESK_VERSION_MINOR 0)
set(RUSTDESK_VERSION_PATCH 0)
set(RUSTDESK_VERSION_BUILD 0)

if(RUSTDESK_VERSION_PARTS_LEN GREATER 0)
  list(GET RUSTDESK_VERSION_PARTS 0 RUSTDESK_VERSION_MAJOR)
endif()
if(RUSTDESK_VERSION_PARTS_LEN GREATER 1)
  list(GET RUSTDESK_VERSION_PARTS 1 RUSTDESK_VERSION_MINOR)
endif()
if(RUSTDESK_VERSION_PARTS_LEN GREATER 2)
  list(GET RUSTDESK_VERSION_PARTS 2 RUSTDESK_VERSION_PATCH)
endif()

target_compile_definitions(${BINARY_NAME} PRIVATE "RUSTDESK_VERSION=\"${RUSTDESK_VERSION}\"")
target_compile_definitions(${BINARY_NAME} PRIVATE "RUSTDESK_VERSION_MAJOR=${RUSTDESK_VERSION_MAJOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "RUSTDESK_VERSION_MINOR=${RUSTDESK_VERSION_MINOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "RUSTDESK_VERSION_PATCH=${RUSTDESK_VERSION_PATCH}")
target_compile_definitions(${BINARY_NAME} PRIVATE "RUSTDESK_VERSION_BUILD=${RUSTDESK_VERSION_BUILD}")

# Disable Windows macros that collide with C++ standard library functions.
target_compile_definitions(${BINARY_NAME} PRIVATE "NOMINMAX")

# Add dependency libraries and include directories. Add any application-specific
# dependencies here.
target_link_libraries(${BINARY_NAME} PRIVATE flutter flutter_wrapper_app)
target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")

# Run the Flutter tool portions of the build. This must not be removed.
add_dependencies(${BINARY_NAME} flutter_assemble)
