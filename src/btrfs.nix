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
  lib,
  nushell,
  coreutils,
  btrfs-progs,
  writeScriptBin,
  util-linuxMinimal,
}:
{
  device,
  fsType,
  activeSubvolume,
  archive,
  ...
}:
assert fsType == "btrfs";
(writeScriptBin "flush-btrfs" ''
  #!${nushell}/bin/nu

  $env.PATH = [
    "${coreutils}/bin",
    "${btrfs-progs}/bin",
    "${util-linuxMinimal}/bin"
  ];

  def "delete subvolume" [
    mountPoint: string,
    subvolume: string
  ] {
    let children = ^btrfs subvolume list -t -o /
      | lines
      | skip 2 # remove column names
      | each { str replace -a -r '\s+' " " } # collapse whitespace
      | split column " " id gen top_level relative_path; # path is relative to the btrfs root subvol

    for subvol in $children {
      delete subvolume $mountPoint $"($mountPoint)/($subvol.relative_path)"
    }

    ^btrfs subvolume delete $subvolume
  }

  def main [] {
    let mount = ^mktemp -d;
    ^mount -t btrfs "${device}" $mount -o subvol="/";

    let active = $"($mount)/${activeSubvolume}";
    mkdir $active;

    if ${lib.boolToString archive.enable} {
      # archive current flush
      if ($active | path exists) {
        mkdir $"($mount)/${archive.directory}";

        let timestamp = (ls -lD $active).0.created
          | format date "${archive.format}";

        mv $active $"($mount)/${archive.directory}/($timestamp)";
      }

      # remove old archives
      let old = ls -a $"($mount)/${archive.directory}"
        | filter {|dir| (date now) - $dir.modified > ${toString archive.retentionDays}day };

      for dir in $old {
        delete subvolume $mount $"($mount)/${archive.directory}/($dir.name)";
      }
    } else {
      if ($active | path exists) {
        delete subvolume $mount $active;
      }
    }

    ^btrfs subvolume create $active;
    ^umount $mount;
    rm $mount;
  }
'')
// {
  dependencies = [ nushell ];
}
