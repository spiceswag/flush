#!@nushell@/bin/nu

# flush: A NixOS module
# Copyright (C) 2025  spicesw
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

$env.PATH = [
    "@coreutils@/bin",
    "@btrfs-progs@/bin",
    "@util-linuxMinimal@/bin"
]

# Flush a subvolume (delete its contents or archive them) on a btrfs filesystem.
def main [
    # The device on which the relevant btrfs filesystem exists.
    --device: string,
    # The path of the subvolume that is being flushed, relative to the btrfs device root subvolume.
    --flush: string
    # Whether to archive the old subvolume contents.
    --archive,
    # The location at which to place archived subvolumes, relative to the btrfs device root subvolume.
    --archiveDirectory: string,
    # The naming format of archived subvolumes, fed to nushell's `date format`.
    --archiveFormat: string,
    # The amount of time to keep archived subvolume contents.
    # Use null for no limit
    --archiveRetention: duration = 30day,
] {
    # TODO: theres a devious race condition that can yield EBUSY if two
    #       flushes happen at the same time, bringing down the boot process

    let mount = ^mktemp -d

    print $"Mounting device ($device) to ($mount)"
    ^mount -t btrfs $device $mount -o subvol="/"

    let active = $"($mount)/($flush)"
    mkdir $active

    if $archive {
        if ($active | path exists) {
            print $"Archiving subvolume ($active) for device ($device)"
            mkdir $"($mount)/($archiveDirectory)"
            let timestamp = (ls -lD $active).0.created | format date $archiveFormat
            mv $active $"($mount)/($archiveDirectory)/($timestamp)"
        }
        # remove old archives
        let old = ls -a $"($mount)/($archiveDirectory)"
            | where {|dir| (date now) - $dir.modified > $archiveRetention }

        print $"Deleting ($old | length) old subvolume archives"
        for dir in $old {
            let relative = $dir.name | path relative-to $mount
            delete subvolume $mount $relative
        }
    } else {
        print $"Deleting subvolume ($active) for device ($device)"
        if ($active | path exists) {
            delete subvolume $mount $flush
        }
    }
    ^btrfs subvolume create $active
    ^umount $mount
    rm $mount
}

# Recursively delete a subvolume on a btrfs filesystem
def "delete subvolume" [
    # The absolute path where the btrfs filesystem is mounted.
    deviceMount: string,
    # The subvolume path to delete, relative to the device mount point.
    subvolume: string
] {
    print $"Deleting subvolume ($subvolume) on device mounted at ($deviceMount) recursively"
    let children = ^btrfs subvolume list -t -o $"($deviceMount)/($subvolume)"
        | lines
        | skip 2
        | each { str replace -a -r '\s+' " " }
        | split column " " id gen top_level relative_path # path is relative to the btrfs root subvol

    for subvol in $children {
        delete subvolume $deviceMount $subvol.relative_path
    }

    ^btrfs subvolume delete $subvolume
    print $"Deleted subvolume ($subvolume) on device mounted at ($deviceMount)"
}
