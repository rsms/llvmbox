# see https://github.com/NixOS/nixpkgs/blob/master/pkgs/development/compilers/llvm/14/default.nix
#
{ pkgs ? (import (fetchTarball "https://github.com/NixOS/nixpkgs/archive/b83e7f5a04a3acc8e92228b0c4bae68933d504eb.tar.gz") {}).pkgsStatic
}:
# { pkgs ? (import <nixpkgs> {}).pkgsMusl
# }:

let
  # nixpkgs = import (builtins.fetchTarball {
  #   url    = "https://github.com/NixOS/nixpkgs/archive/004cb5a694e39bd91b27b0adddc127daf2cb76cb.tar.gz";
  #   sha256 = "0v5pfrisz0xspd3h54vx005fijmhrxwh0la7zmdk97hqm01x3mz4";
  # }) {};
  # pkgs = nixpkgs.pkgsMusl;

  llvmPkgs = pkgs.llvmPackages_14;
  stdenv = llvmPkgs.stdenv;

  hello_c_src = pkgs.writeText "hello.c" ''
    #include <stdio.h>
    int main() { printf("hello\n"); return 0; }
  '';
  hello_cc_src = pkgs.writeText "hello.cc" ''
    #include <iostream>
    int main() { std::cout << "hello\n"; return 0; }
  '';

  hello_cc = { stdenv }:
    stdenv.mkDerivation rec {
      name = "cc-test-${version}";
      version = "0.0";
      inherit hello_cc_src;

      unpackPhase = ":";
      configurePhase = ":";
      buildPhase = ''
        clang++ -Wall -std=gnu++17 -stdlib=libc++ -O2 -static -o hello_cc ${hello_cc_src}
        strip hello_cc
      '';
      installPhase = ''
        install -D -m555 hello_cc $out/bin/llvm-musl-hello_cc
      '';
    };

  drv = pkgs.callPackage hello_cc {
    stdenv = llvmPkgs.stdenv;
  };

in drv
