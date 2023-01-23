# Copyright 2020 The Fuchsia Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

cmake_minimum_required(VERSION 3.13.4)

string(TOLOWER ${CMAKE_HOST_SYSTEM_PROCESSOR} HOST_CPU)
if(HOST_CPU STREQUAL "x86_64")
  set(HOST_CPU "x64")
elseif(HOST_CPU STREQUAL "aarch64")
  set(HOST_CPU "arm64")
endif()
string(TOLOWER ${CMAKE_HOST_SYSTEM_NAME} HOST_OS)
if(HOST_OS STREQUAL "darwin")
  set(HOST_OS "mac")
endif()
set(HOST_PLATFORM "${HOST_OS}-${HOST_CPU}")

if(NOT LLVMBOX_SOURCE_DIR)
  get_filename_component(LLVMBOX_SOURCE_DIR "${CMAKE_CURRENT_LIST_DIR}/../.." ABSOLUTE)
  # message("LLVMBOX_SOURCE_DIR=${LLVMBOX_SOURCE_DIR}")
endif()

if(NOT LLVMBOX_BUILD_DIR)
  set(LLVMBOX_BUILD_DIR $ENV{LLVMBOX_BUILD_DIR})
  get_filename_component(LLVMBOX_BUILD_DIR "${LLVMBOX_BUILD_DIR}" ABSOLUTE)
  # message("LLVMBOX_BUILD_DIR=${LLVMBOX_BUILD_DIR}")
endif()

if(NOT LLVM_STAGE1)
  set(LLVM_STAGE1 $ENV{LLVM_STAGE1})
  get_filename_component(LLVM_STAGE1 "${LLVM_STAGE1}" ABSOLUTE)
endif()

if(NOT CLANG_PREFIX)
  get_filename_component(CLANG_PREFIX "${LLVM_STAGE1}/bin" ABSOLUTE)
endif()

if(NOT CLANG_TARGET)
  exec_program("${CLANG_PREFIX}/clang" ARGS --version OUTPUT_VARIABLE CLANG_VERSION)
  if("${CLANG_VERSION}" MATCHES "Target: ([A-Za-z0-9._-]+)")
    set(CLANG_TARGET "${CMAKE_MATCH_1}")
  else()
    message(FATAL_ERROR "Could not determine CLANG_TARGET ('clang --version' returned: '${CLANG_VERSION}')")
  endif()
endif()

if(NOT CMAKE_SYSROOT)
  get_filename_component(CMAKE_SYSROOT "$ENV{LLVMBOX_SYSROOT}" ABSOLUTE)
  # # NOTE: Match compiler target to our prebuilt sysroot/linux/usr/lib/<target>/ directories.
  # if("${CLANG_TARGET}" MATCHES "(x86_64|aarch64|arm|i386)-(.*-)?linux(-gnu|-gnueabihf)?")
  #   set(CMAKE_SYSROOT "${LLVMBOX_SOURCE_DIR}/prebuilt/third_party/sysroot/linux")
  # else()
  #   message(FATAL_ERROR "No sysroot available for ${CLANG_TARGET}")
  # endif()
endif()

set(EXTRA_LDFLAGS     "-L${CMAKE_SYSROOT}/lib --rtlib=compiler-rt")
set(EXTRA_LDFLAGS_CXX "-nostdlib++ -L${LLVM_STAGE1}/lib")

set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} ${EXTRA_LDFLAGS}")
set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} ${EXTRA_LDFLAGS}")
set(CMAKE_MODULE_LINKER_FLAGS "${CMAKE_MODULE_LINKER_FLAGS} ${EXTRA_LDFLAGS}")

set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} ${EXTRA_LDFLAGS_CXX}")
set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} ${EXTRA_LDFLAGS_CXX}")
set(CMAKE_MODULE_LINKER_FLAGS "${CMAKE_MODULE_LINKER_FLAGS} ${EXTRA_LDFLAGS_CXX}")

set(CMAKE_OSX_DEPLOYMENT_TARGET $ENV{LLVMBOX_TARGET_SYS_VERSION})
set(CMAKE_OSX_SYSROOT ${CMAKE_SYSROOT})

if(NOT CMAKE_SYSTEM_NAME)
  if("${CLANG_TARGET}" MATCHES ".*-linux(-gnu)?")
    set(SYSTEM_NAME "Linux")
  elseif("${CLANG_TARGET}" MATCHES ".*-darwin")
    set(SYSTEM_NAME "Darwin")
  elseif("${CLANG_TARGET}" MATCHES ".*-fuchsia")
    set(SYSTEM_NAME "Fuchsia")
  else()
    message(FATAL_ERROR "Could not determine system name")
  endif()
  # NOTE: We don't set this value if it matches host to avoid setting CMAKE_CROSSCOMPILING.
  if(NOT SYSTEM_NAME STREQUAL CMAKE_HOST_SYSTEM_NAME)
    set(CMAKE_SYSTEM_NAME ${SYSTEM_NAME})
  endif()
endif()

if(NOT CMAKE_SYSTEM_PROCESSOR)
  string(REGEX REPLACE "([A-Za-z0-9]*)-.*" "\\1" CMAKE_SYSTEM_PROCESSOR "${CLANG_TARGET}")
endif()

if(NOT CMAKE_SYSTEM_VERSION)
  if(CMAKE_SYSTEM_NAME STREQUAL "Linux")
    # NOTE: This matches Debian jessie.
    set(CMAKE_SYSTEM_VERSION "3.16.0")
  elseif(CMAKE_SYSTEM_NAME STREQUAL "Darwin")
    # NOTE: This matches macOS High Sierra.
    set(CMAKE_SYSTEM_VERSION "17.0.0")
  elseif(CMAKE_SYSTEM_NAME STREQUAL "Fuchsia")
    set(CMAKE_SYSTEM_VERSION "1")
  endif()
endif()

set(CMAKE_C_COMPILER "${CLANG_PREFIX}/clang")
set(CMAKE_C_CLANG_TARGET ${CLANG_TARGET} CACHE STRING "")
set(CMAKE_CXX_COMPILER "${CLANG_PREFIX}/clang++")
set(CMAKE_CXX_CLANG_TARGET ${CLANG_TARGET} CACHE STRING "")
set(CMAKE_ASM_COMPILER "${CLANG_PREFIX}/clang")
set(CMAKE_ASM_CLANG_TARGET ${CLANG_TARGET} CACHE STRING "")

set(CMAKE_ADDR2LINE "${CLANG_PREFIX}/llvm-addr2line" CACHE PATH "")
set(CMAKE_AR "${CLANG_PREFIX}/llvm-ar" CACHE PATH "")
set(CMAKE_LINKER "${CLANG_PREFIX}/ld.lld" CACHE PATH "")
set(CMAKE_LIPO "${CLANG_PREFIX}/llvm-lipo" CACHE PATH "")
set(CMAKE_NM "${CLANG_PREFIX}/llvm-nm" CACHE PATH "")
set(CMAKE_OBJCOPY "${CLANG_PREFIX}/llvm-objcopy" CACHE PATH "")
set(CMAKE_OBJDUMP "${CLANG_PREFIX}/llvm-objdump" CACHE PATH "")
set(CMAKE_RANLIB "${CLANG_PREFIX}/llvm-ranlib" CACHE PATH "")
set(CMAKE_READELF "${CLANG_PREFIX}/llvm-readelf" CACHE PATH "")
set(CMAKE_STRIP "${CLANG_PREFIX}/llvm-strip" CACHE PATH "")

if(CMAKE_SYSTEM_NAME STREQUAL "Darwin")
  set(CMAKE_LINKER "${CLANG_PREFIX}/ld64.lld" CACHE PATH "")
endif()

if(CMAKE_SYSTEM_NAME STREQUAL "Darwin")
  # must set CMAKE_LINKER=ld on macos since CompilerRTDarwinUtils.cmake calls
  # CMAKE_LINKER -v to detect supported archs:e
  # https://github.com/llvm/llvm-project/blob/32a2af44e1e882f13d1cc2817f0a8d4d8b375d4d/
  #   compiler-rt/cmake/Modules/CompilerRTDarwinUtils.cmake#L89
  set(CMAKE_LINKER "ld" CACHE PATH "")
  set(LLVM_USE_LINKER "ld" CACHE PATH "")
endif()

# if(CMAKE_SYSTEM_NAME STREQUAL "Linux")
#   # set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} -Wl,--thinlto-jobs=2")
#   # set(CMAKE_MODULE_LINKER_FLAGS "${CMAKE_MODULE_LINKER_FLAGS} -Wl,--thinlto-jobs=2")
#   # set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} -Wl,--thinlto-jobs=2")
#   set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} -static")
# endif()

set(CMAKE_FIND_ROOT_PATH ${CMAKE_SYSROOT})

set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
