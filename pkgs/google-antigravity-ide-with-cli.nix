{ callPackage, symlinkJoin, ... }@args:
let
  filteredArgs = removeAttrs args [ "callPackage" "symlinkJoin" ];
  ide = callPackage ./google-antigravity-ide.nix filteredArgs;
  cli = callPackage ./cli.nix { };
in
symlinkJoin {
  name = "google-antigravity-ide-with-cli";
  paths = [ ide cli ];
  meta = ide.meta;
}
