{ callPackage, symlinkJoin, ... }@args:
let
  filteredArgs = removeAttrs args [ "callPackage" "symlinkJoin" ];
  ide = callPackage ./package.nix (filteredArgs // { appType = "Antigravity IDE"; });
  cli = callPackage ./cli.nix { };
in
symlinkJoin {
  name = "google-antigravity-ide";
  paths = [ ide cli ];
  meta = ide.meta;
}
