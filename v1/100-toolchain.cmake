# Copyright 2020 The Fuchsia Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

cmake_minimum_required(VERSION 3.13.4)

if(NOT LLVMBOX_BUILD_DIR)
  set(LLVMBOX_BUILD_DIR $ENV{LLVMBOX_BUILD_DIR})
endif()

if(NOT APPLE)
  set(CMAKE_SYSROOT "${LLVMBOX_BUILD_DIR}/musl-host")
endif()
