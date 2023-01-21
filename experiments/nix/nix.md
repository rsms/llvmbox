# Nix notes

## Installing nix on ubuntu

```sh
mkdir ~/.config/nix
echo "experimental-features = nix-command flakes" > ~/.config/nix/nix.conf
sh <(curl -L https://nixos.org/nix/install) --daemon
```

## Examples

```sh
nix-channel --add https://nixos.org/channels/nixos-22.11 nixpkgs
nix-channel --add https://nixos.org/channels/nixpkgs-unstable unstable
nix-channel --update
nix-channel --list

# you can now search for packages
nix search nixpkgs hello

# run (implicit build)
nix run -f '<nixpkgs>' hello

# run (implicit build) statically linked
nix run -f '<nixpkgs>' pkgsStatic.hello

# run (implicit build) with musl libc.so
nix run -f '<nixpkgs>' pkgsMusl.hello

# build with musl libc.so
nix build -f '<nixpkgs>' pkgsMusl.hello
./result/bin/hello
objdump -p ./result/bin/hello | grep NEEDED

# enter a REPL
nix repl '<nixpkgs>'
```

## Cross compilation

```sh
nix repl '<nixpkgs>'
nix-repl> pkgsCross.<TAB>
# list of all targets
# to get the actual "triple" of a target, look at
# .stdenv.hostPlatform.config:
nix-repl> pkgsCross.musl64.stdenv.hostPlatform.config
"x86_64-unknown-linux-musl"
nix-repl>
```

## llvm

LLVM can be built statically with `nix build -f '<nixpkgs>' pkgsStatic.llvmPackages_14`,
however the llvm libs will not be ABI compatible with musl since pkgsStatic will use libstdc++. So here's an attempt at a custom llvm build in nix:

```sh
nix build -f llvm-static-musl.nix
```


See also

- https://nix.dev/tutorials/cross-compilation
- https://nixos.wiki/wiki/Cheatsheet
- https://github.com/NixOS/nixpkgs/blob/master/pkgs/development/compilers/llvm/14/llvm/default.nix
- https://nix.dev/tutorials/towards-reproducibility-pinning-nixpkgs#pinning-nixpkgs
