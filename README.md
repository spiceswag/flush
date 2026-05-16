# Flush

A quick and dirty NixOS module that will rotate any filesystems you assign to it.
Rotate here means wiping (or archiving) an old filesystem, and replacing it with a clean one.
This notion comes up, with different names in NixOS systems that follow impermanence setups,
either [raw](https://grahamc.com/blog/erase-your-darlings/), or with the aptly named
[impermanence module](https://github.com/NixCommunity/impermanence).

Currently supported are ephemeral filesystems which are located on a btrfs partition,
however the implementation can be easily extended to any filesystem with a notion of _subvolumes_,
such as ZFS (which I don't plan on supporting since I boot on btrfs).

This module comes in with 10 options layed out in a structure similar to the `fileSystems.<name>` option.
```
flush.<name>.mountPoint
flush.<name>.device
flush.<name>.fsType (required)
flush.<name>.addedOptions
flush.<name>.neededForBoot
flush.<name>.activeSubvolume

flush.<name>.archive.enable
flush.<name>.archive.directory
flush.<name>.archive.format
flush.<name>.archive.retentionDays
```

_For documentation on these options, read the source code: src/default.nix_

In fact, a system booting btrfs needs only to remove mount options related to subvolumes and rename the field `addedOptions`,
set the fsType to `btrfs`, and changing the filesystem from the `fileSystems` option to the `flush` option. At that point
(and of course checking the default ephemeral subvolume names and changing existing subvolumes' names), you are ready to
boot an ephemeral system!

## Adding to your system

This module is distributed as a flake. To install it, follow the example from my own NixOS config:
```diff
{
  description = "The desktop";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-25.05";
+   flush.url = "github:spiceswag/flush";
  };

  outputs =
    {
      self,
      nixpkgs,
      # Snip!
      flush
    }@inputs:
    {
      nixosConfigurations."spicetop" = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";

        modules = [
          ./src/config.nix
          ./src/hardware.nix
+         flush.nixosModules.default
        ];
      };
    };
}
```
