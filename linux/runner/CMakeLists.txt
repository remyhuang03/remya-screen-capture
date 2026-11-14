cmake_minimum_required(VERSION 3.13)
project(runner LANGUAGES C CXX)

pkg_check_modules(LAYER_SHELL REQUIRED IMPORTED_TARGET gtk-layer-shell-0>=0.6)
pkg_check_modules(WAYLAND REQUIRED IMPORTED_TARGET wayland-client)
pkg_check_modules(GMODULE REQUIRED IMPORTED_TARGET gmodule-2.0)
pkg_get_variable(WAYLAND_PROTOCOLS_DIR wayland-protocols pkgdatadir)
find_program(WAYLAND_SCANNER wayland-scanner)
if(NOT WAYLAND_SCANNER OR NOT WAYLAND_PROTOCOLS_DIR)
  message(FATAL_ERROR "wayland-scanner and wayland-protocols are required")
endif()
set(XDG_OUTPUT_XML "${WAYLAND_PROTOCOLS_DIR}/unstable/xdg-output/xdg-output-unstable-v1.xml")
set(XDG_OUTPUT_HEADER "${CMAKE_CURRENT_BINARY_DIR}/xdg-output-client-protocol.h")
set(XDG_OUTPUT_SOURCE "${CMAKE_CURRENT_BINARY_DIR}/xdg-output-protocol.c")
add_custom_command(
  OUTPUT "${XDG_OUTPUT_HEADER}" "${XDG_OUTPUT_SOURCE}"
  COMMAND "${WAYLAND_SCANNER}" client-header "${XDG_OUTPUT_XML}" "${XDG_OUTPUT_HEADER}"
  COMMAND "${WAYLAND_SCANNER}" private-code "${XDG_OUTPUT_XML}" "${XDG_OUTPUT_SOURCE}"
  DEPENDS "${XDG_OUTPUT_XML}"
  VERBATIM
)

# Define the application target. To change its name, change BINARY_NAME in the
# top-level CMakeLists.txt, not the value here, or `flutter run` will no longer
# work.
#
# Any new source files that you add to the application should be added here.
add_executable(${BINARY_NAME}
  "main.cc"
  "my_application.cc"
  "capture_windows.cc"
  "${XDG_OUTPUT_HEADER}"
  "${XDG_OUTPUT_SOURCE}"
  "capture_plugins.cc"
)

# Apply the standard set of build settings. This can be removed for applications
# that need different build settings.
apply_standard_settings(${BINARY_NAME})

# Add preprocessor definitions for the application ID.
add_definitions(-DAPPLICATION_ID="${APPLICATION_ID}")

# Add dependency libraries. Add any application-specific dependencies here.
target_link_libraries(${BINARY_NAME} PRIVATE flutter)
target_link_libraries(${BINARY_NAME} PRIVATE PkgConfig::GTK)
target_link_libraries(${BINARY_NAME} PRIVATE PkgConfig::LAYER_SHELL PkgConfig::WAYLAND)
target_link_libraries(${BINARY_NAME} PRIVATE PkgConfig::GMODULE)

target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}" "${CMAKE_CURRENT_BINARY_DIR}")
