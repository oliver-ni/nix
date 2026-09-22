{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs?ref=nixos-unstable";

    agenix = {
      url = "github:ryantm/agenix/b027ee29d959fda4b60b57566d64c98a202e0feb";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.darwin.follows = "nix-darwin";
      inputs.home-manager.follows = "home-manager";
    };

    disko = {
      url = "github:nix-community/disko/de5708739256238fb912c62f03988815db89ec9a";
      inputs.nixpkgs.follows = "nixpkgs";
    };

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

    jellyfin-client = {
      url = "git+ssh://git@github.com/oliver-ni/jellyfin-client";
      flake = false;
    };
  };

  outputs =
    inputs@{
      nixpkgs,
      nix-index-database,
      nix-darwin,
      home-manager,
      ...
    }:
    let
      pkgsFor =
        system:
        import nixpkgs {
          inherit system;
          config.allowUnfree = true;
          overlays = [
            nix-index-database.overlays.nix-index
          ];
        };

      nixosSystem =
        system: host:
        nixpkgs.lib.nixosSystem {
          inherit system;
          pkgs = pkgsFor system;
          specialArgs.inputs = inputs;

          modules = [
            ./modules/nixos/base.nix
            inputs.agenix.nixosModules.default
            inputs.disko.nixosModules.disko
            home-manager.nixosModules.home-manager
            host
          ];
        };

      darwinSystem =
        host:
        nix-darwin.lib.darwinSystem rec {
          inherit inputs;
          system = "aarch64-darwin";
          pkgs = pkgsFor system;
          modules = [
            ./modules/darwin/base.nix
            host
          ];
        };

      homeManagerConfiguration =
        system: home:
        home-manager.lib.homeManagerConfiguration {
          pkgs = pkgsFor system;
          modules = [
            ./modules/home/base.nix
            home
          ];
        };

      forAllSystems =
        fn: nixpkgs.lib.genAttrs [ "x86_64-linux" "aarch64-darwin" ] (system: fn (pkgsFor system));
    in
    {
      formatter = forAllSystems (pkgs: pkgs.nixfmt-tree);

      nixosConfigurations.ochazuke = nixosSystem "x86_64-linux" ./hosts/nixos/ochazuke.nix;

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
