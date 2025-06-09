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
let
  # The mountpoint of the whole btrfs device
  workDir = "/flush/${activeSubvolume}";
in
''
  set -uo pipefail
  export PATH="/bin:${pkgs.coreutils}/bin:${pkgs.findutils}/bin:${pkgs.util-linux}/bin:${pkgs.btrfs-progs}/bin"

  mkdir -p "${workDir}"
  mount -t btrfs "${device}" "${workDir}" -o subvol=/

  delete_subvolume_recursively() {
    IFS=$'\n'
    for i in $(btrfs subvolume list -o "$1" | cut -f 9- -d ' '); do
      delete_subvolume_recursively "${workDir}/$i"
    done
    btrfs subvolume delete "$1"
  }

  ${
    if archive.enable then
      ''
        # Create archive directory
        mkdir -p "${workDir}/${archive.directory}"

        # Archive current flush
        if [[ -e "${workDir}/${activeSubvolume}" ]]; then
          timestamp=$(date --date="@$(stat -c %Y ${workDir}/${activeSubvolume})" "${archive.format}")
          mv "${workDir}/${activeSubvolume}" "${workDir}/${archive.directory}/$timestamp"
        fi

        # Remove old archives
        for i in $(find "${workDir}/${archive.directory}/" -maxdepth 1 -mtime +${builtins.toString archive.retentionDays}); do
          delete_subvolume_recursively "$i"
        done
      ''
    else
      ''
        # Delete current flush
        if [[ -e "${workDir}/${activeSubvolume}" ]]; then
          delete_subvolume_recursively "${workDir}/${activeSubvolume}"
        fi
      ''
  }

  btrfs subvolume create "${workDir}/${activeSubvolume}"
  umount "${workDir}"
''
