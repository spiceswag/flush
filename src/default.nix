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
  pkgs,
  config,
  modulesPath,
  ...
}:
let
  nixosUtilsPath = modulesPath + "/../lib/utils.nix";
  nixosUtils = pkgs.callPackage nixosUtilsPath { };

  inherit (lib) types mkOption mkIf;
  flushes = config.flush;

  # Stolen from nixpkgs
  addCheckDesc =
    desc: elemType: check:
    types.addCheck elemType check // { description = "${elemType.description} (with check: ${desc})"; };
  isNonEmpty = s: (builtins.match "[ \t\n]*" s) == null;
  nonEmptyWithoutTrailingSlash = addCheckDesc "non-empty without trailing slash" types.str (
    s: isNonEmpty s && (builtins.match ".+/" s) == null
  );

  flushFsOpts =
    { name, config, ... }:
    {
      options = {
        mountPoint = mkOption {
          example = "/";
          type = nonEmptyWithoutTrailingSlash;
          description = "Location of the mounted file system.";
        };

        device = mkOption {
          default = null;
          example = "/dev/sda";
          type = types.nullOr types.nonEmptyStr;
          description = "Location of the device.";
        };

        fsType = mkOption {
          example = "btrfs";
          type = types.enum [ "btrfs" ];
          description = ''
            The type of the filesystem to flush.
            All supported filesystem types have some concept of a tree-like subvolume structure.
          '';
        };

        addedOptions = mkOption {
          default = [ "defaults" ];
          example = [ "data=journal" ];
          description = "Additional options given to mount the filesystem.";
          type = types.nonEmptyListOf types.nonEmptyStr;
        };

        neededForBoot = mkOption {
          type = types.bool;
          description = ''
            If set, this file system will be mounted in the initial ramdisk. Note that the
            file system will always be mounted in the initial ramdisk if its mount point is
            one of the following: `/`, `/nix`, `/nix/store`, `/var`, `/var/log`, `/var/lib`,
            `/var/lib/nixos`, `/etc`, `/usr`.
          '';
          default = false;
        };

        # Flush settings

        activeSubvolume = mkOption {
          type = types.addCheck types.singleLineStr (value: !(lib.strings.hasPrefix "/" value));
          description = ''
            The path of the subvolume that's actively mounted for the filesystem.
            You are encouraged to follow the default, or at least place your active
            subvolume under a `flush/` subvolume directory as in the default.
          '';
        };

        archive = {
          enable = lib.mkEnableOption "archiving of flushed filesystems";

          directory = mkOption {
            type = nonEmptyWithoutTrailingSlash;
            description = ''
              The subvolume subdirectory to place flushed filesystem archives in.
              You are encouraged to follow the default, and adapt it if you plan on changing
              the {option}`activeSubvolume` option.
            '';
          };

          format = mkOption {
            type = types.addCheck types.singleLineStr (value: !(lib.strings.hasInfix "/" value));
            description = ''
              The naming format archived filesystems will follow.
              The format will be processed by the coreutils {command}`date` command.
            '';
            default = "+%Y-%m-%-d_%H:%M:%S";
          };

          retentionDays = mkOption {
            type = types.ints.unsigned;
            description = ''
              The upper limit on how old flushed filesystem archives are kept, in days.
            '';
            default = 30;
          };
        };
      };

      config = {
        mountPoint = lib.mkDefault name;

        activeSubvolume = lib.mkDefault (
          # Systemd escaping of filesystem names
          let
            escaped = lib.strings.replaceStrings [ "/" "-" ] [ "-" "\\x2d" ] config.mountPoint;
            trimmed =
              if lib.strings.hasPrefix "-" escaped then
                builtins.substring 1 (builtins.stringLength escaped) escaped
              else
                escaped;
          in
          "flush/@${trimmed}"
        );

        archive.directory = lib.mkDefault (
          let
            escaped = lib.strings.replaceStrings [ "/" "-" ] [ "-" "\\x2d" ] config.mountPoint;
            trimmed =
              if lib.strings.hasPrefix "-" escaped then
                builtins.substring 1 (builtins.stringLength escaped) escaped
              else
                escaped;
          in
          "flush/archive/@${trimmed}"
        );
      };
    };
in
{
  options = {
    flush = mkOption {
      type = types.attrsOf (types.submodule flushFsOpts);
      default = { };
      description = ''
        Configure filesystem mounts that need to be flushed on each boot.
      '';
    };
  };

  config = mkIf (builtins.length (lib.attrsToList flushes) != 0) {
    fileSystems = lib.mapAttrs (name: fs: {
      inherit (fs)
        mountPoint
        device
        fsType
        neededForBoot
        ;
      options =
        (
          if fs.fsType == "btrfs" then
            [ "subvol=${fs.activeSubvolume}" ]
          else
            throw "unsupported filesystem type"
        )
        ++ fs.addedOptions;
    }) flushes;

    # SCRIPTED INITRD IS UNTESTED; PLEASE REPORT FEEDBACK to https://github.com/spiceswag/flush/issues
    boot.initrd.postDeviceCommands = mkIf (flushes != { } && !config.boot.initrd.systemd.enable) (
      lib.concatStrings (
        lib.mapAttrsToList (
          _: fs: if fs.fsType == "btrfs" then import ./btrfs-initrd.nix fs else abort "impossible"
        ) (lib.filterAttrs (_: fs: nixosUtils.fsNeededForBoot fs) flushes)
      )
    );

    boot.initrd.systemd.services = mkIf (flushes != { } && config.boot.initrd.systemd.enable) (
      lib.foldl' lib.mergeAttrs { } (
        lib.mapAttrsToList (
          _: fs:
          let
            systemdMount = nixosUtils.escapeSystemdPath ("/sysroot/" + fs.mountPoint);
            systemdDevice = nixosUtils.escapeSystemdPath fs.device;
          in
          {
            "flush-${systemdMount}" = {
              description = "Flush ephemeral ${fs.mountPoint} filesystem in initrd";

              serviceConfig.Type = "oneshot";
              unitConfig.DefaultDependencies = "no";

              requiredBy = [ "${systemdMount}.mount" ];
              before = [ "${systemdMount}.mount" ];

              requires = [ "${systemdDevice}.device" ];
              after = [ "${systemdDevice}.device" ];

              script =
                if fs.fsType == "btrfs" then import ./btrfs-initrd.nix { inherit pkgs; } fs else abort "impossible";
            };
          }
        ) (lib.filterAttrs (_: fs: nixosUtils.fsNeededForBoot fs) flushes)
      )
    );

    systemd.services = mkIf (lib.filterAttrs (_: fs: nixosUtils.fsNeededForBoot fs) flushes != { }) (
      lib.foldl' lib.mergeAttrs { } (
        lib.mapAttrsToList (
          _: fs:
          let
            systemdMount = nixosUtils.escapeSystemdPath fs.mountPoint;
            systemdDevice = nixosUtils.escapeSystemdPath fs.device;
          in
          {
            "flush-${systemdMount}" = {
              description = "Flush ephemeral ${fs.mountPoint} filesystem";

              serviceConfig.Type = "oneshot";
              unitConfig.DefaultDependencies = "no";

              requiredBy = [ "${systemdMount}.mount" ];
              before = [ "${systemdMount}.mount" ];

              requires = [ "${systemdDevice}.device" ];
              after = [ "${systemdDevice}.device" ];

              script =
                if fs.fsType == "btrfs" then import ./btrfs-normal.nix { inherit pkgs; } fs else abort "impossible";
            };
          }
        ) (lib.filterAttrs (_: fs: !nixosUtils.fsNeededForBoot fs) flushes)
      )
    );

    assertions =
      [
        {
          assertion =
            let
              activeSubvolumes = lib.mapAttrsToList (name: fs: fs.activeSubvolume) flushes;
              normalized = lib.map lib.strings.normalizePath activeSubvolumes;
              deduplicated = lib.lists.unique normalized;
            in
            builtins.length normalized == builtins.length deduplicated;
          message = "Filesystems managed by flush must not share an activeSubvolume.";
        }
      ]
      ++ lib.optional (lib.any ({ value, ... }: value.archive.enable) (lib.attrsToList flushes)) {
        assertion =
          let
            filteredFlushes = lib.filter (fs: fs.archive.enable) (lib.mapAttrsToList (_: fs: fs) flushes);
            archiveDirectories = lib.map (fs: lib.strings.normalizePath fs.archive.directory) filteredFlushes;
            deduplicated = lib.lists.unique archiveDirectories;
          in
          builtins.length archiveDirectories == builtins.length deduplicated;
        message = "Filesystems managed by flush must not share archive directories, to avoid data loss.";
      };
  };
}
