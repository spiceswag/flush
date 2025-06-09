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

{ pkgs }:
{
  # mountPoint,
  device,
  fsType,
  # addedOptions,
  activeSubvolume,
  archive,
  ...
}:
assert fsType == "btrfs";
''
  set -uo pipefail
  export PATH="/bin:${pkgs.coreutils}/bin:${pkgs.findutils}/bin:${pkgs.util-linux}/bin:${pkgs.btrfs-progs}/bin"

  directory=$(mktemp -d)
  mount -t btrfs "${device}" "$directory" -o subvol=/
  active="$directory/${activeSubvolume}"
  mkdir -p "$active"

  delete_subvolume_recursively() {
    IFS=$'\n'
    for i in $(btrfs subvolume list -o "$1" | cut -f 9- -d ' '); do
      delete_subvolume_recursively "$active/$i"
    done
    btrfs subvolume delete "$1"
  }

  ${
    if archive.enable then
      ''
        # Archive current flush
        if [[ -e "$active" ]]; then
          mkdir -p "$directory/${archive.directory}"
          timestamp=$(date --date="@$(stat -c %Y $active)" "${archive.format}")
          mv "$active" "$directory/${archive.directory}/$timestamp"
        fi

        # Remove old archives
        for i in $(find "$directory/${archive.directory}/" -maxdepth 1 -mtime +${builtins.toString archive.retentionDays}); do
          delete_subvolume_recursively "$i"
        done
      ''
    else
      ''
        # Delete current flush
        if [[ -e "$active" ]]; then
          delete_subvolume_recursively "$active"
        fi
      ''
  }

  btrfs subvolume create "$active"
  umount $directory
  rmdir $directory
''
