# Project-level configuration.
cmake_minimum_required(VERSION 3.14)
project(surf_file LANGUAGES CXX)

# The name of the executable created for the application. Change this to change
# the on-disk name of your application.
set(BINARY_NAME "surf_file")

# Explicitly opt in to modern CMake behaviors to avoid warnings with recent
# versions of CMake.
cmake_policy(VERSION 3.14...3.25)

# Define build configuration option.
get_property(IS_MULTICONFIG GLOBAL PROPERTY GENERATOR_IS_MULTI_CONFIG)
if(IS_MULTICONFIG)
  set(CMAKE_CONFIGURATION_TYPES "Debug;Profile;Release"
    CACHE STRING "" FORCE)
else()
  if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE "Debug" CACHE
      STRING "Flutter build mode" FORCE)
    set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS
      "Debug" "Profile" "Release")
  endif()
endif()
# Define settings for the Profile build mode.
set(CMAKE_EXE_LINKER_FLAGS_PROFILE "${CMAKE_EXE_LINKER_FLAGS_RELEASE}")
set(CMAKE_SHARED_LINKER_FLAGS_PROFILE "${CMAKE_SHARED_LINKER_FLAGS_RELEASE}")
set(CMAKE_C_FLAGS_PROFILE "${CMAKE_C_FLAGS_RELEASE}")
set(CMAKE_CXX_FLAGS_PROFILE "${CMAKE_CXX_FLAGS_RELEASE}")

# Use Unicode for all projects.
add_definitions(-DUNICODE -D_UNICODE)

# Compilation settings that should be applied to most targets.
#
# Be cautious about adding new options here, as plugins use this function by
# default. In most cases, you should add new options to specific targets instead
# of modifying this function.
function(APPLY_STANDARD_SETTINGS TARGET)
  target_compile_features(${TARGET} PUBLIC cxx_std_17)
  target_compile_options(${TARGET} PRIVATE /W4 /WX /wd"4100")
  target_compile_options(${TARGET} PRIVATE /EHsc)
  target_compile_definitions(${TARGET} PRIVATE "_HAS_EXCEPTIONS=0")
  target_compile_definitions(${TARGET} PRIVATE "$<$<CONFIG:Debug>:_DEBUG>")
endfunction()

# Flutter library and tool build rules.
set(FLUTTER_MANAGED_DIR "${CMAKE_CURRENT_SOURCE_DIR}/flutter")
add_subdirectory(${FLUTTER_MANAGED_DIR})

# Application build; see runner/CMakeLists.txt.
add_subdirectory("runner")


# The video and WebView plugins download incompatible NuGet versions to the
# same filename. Resolve one executable before configuring either plugin.
if(DEFINED NUGET AND NOT EXISTS "${NUGET}")
  unset(NUGET CACHE)
  unset(NUGET)
endif()
find_program(NUGET NAMES nuget)
if(NOT NUGET)
  set(NUGET_DOWNLOAD "${CMAKE_BINARY_DIR}/tools/nuget-7.6.0.exe")
  set(NUGET_DOWNLOAD_SHA256
    "751ee5e79481626a428c1241dc7f94bca2739b32588e669715bc5fb54d8fb8a2")
  if(NOT EXISTS "${NUGET_DOWNLOAD}")
    file(MAKE_DIRECTORY "${CMAKE_BINARY_DIR}/tools")
    file(DOWNLOAD
      "https://dist.nuget.org/win-x86-commandline/v7.6.0/nuget.exe"
      "${NUGET_DOWNLOAD}"
      EXPECTED_HASH "SHA256=${NUGET_DOWNLOAD_SHA256}"
      TLS_VERIFY ON
      STATUS NUGET_DOWNLOAD_STATUS)
    list(GET NUGET_DOWNLOAD_STATUS 0 NUGET_DOWNLOAD_CODE)
    if(NOT NUGET_DOWNLOAD_CODE EQUAL 0)
      list(GET NUGET_DOWNLOAD_STATUS 1 NUGET_DOWNLOAD_MESSAGE)
      file(REMOVE "${NUGET_DOWNLOAD}")
      message(FATAL_ERROR "NuGet download failed: ${NUGET_DOWNLOAD_MESSAGE}")
    endif()
  endif()
  file(SHA256 "${NUGET_DOWNLOAD}" NUGET_DOWNLOAD_HASH)
  if(NOT NUGET_DOWNLOAD_HASH STREQUAL NUGET_DOWNLOAD_SHA256)
    message(FATAL_ERROR "Integrity check for ${NUGET_DOWNLOAD} failed.")
  endif()
  set(NUGET "${NUGET_DOWNLOAD}" CACHE FILEPATH "NuGet executable for plugins" FORCE)
endif()

# Generated plugin build rules, which manage building the plugins and adding
# them to the application.
include(flutter/generated_plugins.cmake)

# webview_flutter_windows is built as C++23, so MSBuild implicitly compiles
# std.ixx, which fails to link with _HAS_EXCEPTIONS=0 (unresolved
# std::_Raise_handler). The plugin does not use `import std`.
if(TARGET webview_flutter_windows_plugin)
  get_target_property(WEBVIEW_PLUGIN_SOURCES webview_flutter_windows_plugin SOURCES)
  get_target_property(WEBVIEW_PLUGIN_DIR webview_flutter_windows_plugin SOURCE_DIR)
  list(TRANSFORM WEBVIEW_PLUGIN_SOURCES PREPEND "${WEBVIEW_PLUGIN_DIR}/")
  set_source_files_properties(${WEBVIEW_PLUGIN_SOURCES}
    TARGET_DIRECTORY webview_flutter_windows_plugin
    PROPERTIES VS_SETTINGS "BuildStlModules=false")
endif()


# === Installation ===
# Support files are copied into place next to the executable, so that it can
# run in place. This is done instead of making a separate bundle (as on Linux)
# so that building and running from within Visual Studio will work.
set(BUILD_BUNDLE_DIR "$<TARGET_FILE_DIR:${BINARY_NAME}>")
# Make the "install" step default, as it's required to run.
set(CMAKE_VS_INCLUDE_INSTALL_TO_DEFAULT_BUILD 1)
if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
  set(CMAKE_INSTALL_PREFIX "${BUILD_BUNDLE_DIR}" CACHE PATH "..." FORCE)
endif()

set(INSTALL_BUNDLE_DATA_DIR "${CMAKE_INSTALL_PREFIX}/data")
set(INSTALL_BUNDLE_LIB_DIR "${CMAKE_INSTALL_PREFIX}")

install(TARGETS ${BINARY_NAME} RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_ICU_DATA_FILE}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)

if(PLUGIN_BUNDLED_LIBRARIES)
  install(FILES "${PLUGIN_BUNDLED_LIBRARIES}"
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endif()

# Copy the native assets provided by the build.dart from all packages.
set(NATIVE_ASSETS_DIR "${PROJECT_BUILD_DIR}native_assets/windows/")
install(DIRECTORY "${NATIVE_ASSETS_DIR}"
   DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
   COMPONENT Runtime)

# Fully re-copy the assets directory on each build to avoid having stale files
# from a previous install.
set(FLUTTER_ASSET_DIR_NAME "flutter_assets")
install(CODE "
  file(REMOVE_RECURSE \"${INSTALL_BUNDLE_DATA_DIR}/${FLUTTER_ASSET_DIR_NAME}\")
  " COMPONENT Runtime)
install(DIRECTORY "${PROJECT_BUILD_DIR}/${FLUTTER_ASSET_DIR_NAME}"
  DESTINATION "${INSTALL_BUNDLE_DATA_DIR}" COMPONENT Runtime)

# Install the AOT library on non-Debug builds only.
install(FILES "${AOT_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  CONFIGURATIONS Profile;Release
  COMPONENT Runtime)
