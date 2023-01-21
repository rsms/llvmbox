{ nixpkgs ? fetchTarball "https://github.com/NixOS/nixpkgs/archive/bba3474a5798b5a3a87e10102d1a55f19ec3fca5.tar.gz"
, pkgs ? (import nixpkgs {}).pkgsCross.aarch64-multiplatform
}:

# callPackage is needed due to https://github.com/NixOS/nixpkgs/pull/126844
pkgs.pkgsStatic.callPackage ({ mkShell, zlib, pkg-config, file }: mkShell {
  # these tools run on the build platform, but are configured to target the host platform
  nativeBuildInputs = [ pkg-config file ];
  # libraries needed for the host platform
  buildInputs = [ zlib ];
}) {}


# e.g.
#   nix-shell --run '$CC hello.c -o hello' cross-shell.nix
#   nix-shell --run 'file hello' cross-shell.nix
