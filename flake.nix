{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs?ref=nixos-unstable";
    nix-index-database = {
      url = "github:nix-community/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-darwin = {
      url = "github:lnl7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs@{ nixpkgs, nix-index-database, nix-darwin, home-manager, ... }:
    let
      pkgsFor = system: import nixpkgs {
        inherit system;
        config.allowUnfree = true;
        overlays = [
          nix-index-database.overlays.nix-index
        ];
      };

      darwinSystem = host: nix-darwin.lib.darwinSystem rec {
        inherit inputs;
        system = "aarch64-darwin";
        pkgs = pkgsFor system;
        modules = [ ./modules/darwin/base.nix host ];
      };

      homeManagerConfiguration = system: home: home-manager.lib.homeManagerConfiguration {
        pkgs = pkgsFor system;
        modules = [ ./modules/home/base.nix home ];
      };

      forAllSystems = fn: nixpkgs.lib.genAttrs [ "x86_64-linux" "aarch64-darwin" ] (system: fn (pkgsFor system));
    in
    {
      formatter = forAllSystems (pkgs: pkgs.nixpkgs-fmt);

      darwinConfigurations = {
        onigiri = darwinSystem ./hosts/darwin/onigiri.nix;
        tempura = darwinSystem ./hosts/darwin/tempura.nix;
      };

      homeConfigurations = {
        "oliver@onigiri" = homeManagerConfiguration "aarch64-darwin" ./home/${"oliver@onigiri"}.nix;
        "oliver@tempura" = homeManagerConfiguration "aarch64-darwin" ./home/${"oliver@tempura"}.nix;
      };
    };
}
