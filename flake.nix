{
  description = "A nixos module for rotating persistent storage";

  outputs =
    { ... }:
    {
      nixosModules = rec {
        default = flush;
        flush = ./src;
      };
    };
}
