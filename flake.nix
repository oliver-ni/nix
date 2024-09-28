{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs?ref=28d1022cd5b977b02ba1419c464a418ee166dfa4";
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
    brew-api = {
      url = "github:BatteredBunny/brew-api";
      flake = false;
    };
    brew-nix = {
      url = "github:BatteredBunny/brew-nix";
      inputs.nix-darwin.follows = "nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.brew-api.follows = "brew-api";
    };
  };

  outputs = inputs@{ nixpkgs, nix-index-database, nix-darwin, home-manager, brew-nix, ... }:
    let
      system = "aarch64-darwin";
      fs = nixpkgs.lib.fileset;
      allNixFiles = fs.fileFilter (file: file.hasExt "nix") ./.;

      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
        overlays = [
          brew-nix.overlays.default
          nix-index-database.overlays.nix-index
        ];
      };

      commonModules = fs.toList (fs.intersection allNixFiles ./modules/common);
      nixosModules = fs.toList (fs.intersection allNixFiles ./modules/nixos);
      darwinModules = fs.toList (fs.intersection allNixFiles ./modules/darwin);
      homeModules = fs.toList (fs.intersection allNixFiles ./modules/home);

      nixosSystem = modules: nixpkgs.lib.nixosSystem {
        inherit pkgs;
        system = "x86_64-linux";
        modules = commonModules ++ nixosModules ++ modules;
        specialArgs = { inherit inputs; };
      };

      darwinSystem = modules: nix-darwin.lib.darwinSystem {
        inherit pkgs inputs;
        system = "aarch64-darwin";
        modules = commonModules ++ darwinModules ++ modules;
      };

      homeManagerConfiguration = modules: home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        modules = homeModules ++ modules;
      };
    in
    {
      formatter.${system} = pkgs.nixpkgs-fmt;

      nixosConfigurations = {
        wasabi = nixosSystem [ ./hosts/wasabi.nix ];
      };

      darwinConfigurations = {
        onigiri = darwinSystem [ ./hosts/onigiri.nix ];
      };

      homeConfigurations = {
        "oliver@onigiri" = homeManagerConfiguration [ ./home/${"oliver@onigiri"}.nix ];
      };
    };
}
