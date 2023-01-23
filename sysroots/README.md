# sysroot templates

## macOS

macOS libSystem (aka libc) is always dynamically linked.
Symbol table files at `lib/any-macos/*.tbd` are manually copied from SDKs.

## .tbd files

A .tbd file is a text-based stub (yaml), that lists all the symbols of a dynamic library, that can be linked against in leui of the full dylib. This allows more parallelisation in the build system, allowing linking of libraries to proceed in parallel, even if they have dependencies between them.

