with import <nixpkgs> {};
linuxPackages.bcc.overrideDerivation (old: {
  # overrideDerivation allows it to specify additional dependencies
  buildInputs = [ bashInteractive ninja ] ++ old.buildInputs;
})
