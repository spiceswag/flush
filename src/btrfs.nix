/*
  flush: A NixOS module
  Copyright (C) 2025  spicesw

  This program is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  This program is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

{
  nushell,
  coreutils,
  btrfs-progs,
  util-linuxMinimal,
  replaceVars,
  runCommandLocal,
}:
let
  script = replaceVars ./btrfs.nu {
    inherit
      nushell
      coreutils
      btrfs-progs
      util-linuxMinimal
      ;
  };
in
runCommandLocal "flush-btrfs"
  {
    meta.mainProgram = "flush-btrfs";
    passthru.dependencies = [ nushell ];
  }
  ''
    mkdir -p $out/bin
    cp ${script} $out/bin/flush-btrfs
    chmod +x $out/bin/flush-btrfs
  ''
