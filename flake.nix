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
      fs = nixpkgs.lib.fileset;
      allNixFiles = fs.fileFilter (file: file.hasExt "nix") ./.;

      pkgsFor = system: import nixpkgs {
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

      nixosSystem = modules_: nixpkgs.lib.nixosSystem rec {
        system = "x86_64-linux";
        pkgs = pkgsFor system;
        modules = commonModules ++ nixosModules ++ modules_;
        specialArgs = { inherit inputs; };
      };

      darwinSystem = modules_: nix-darwin.lib.darwinSystem rec {
        inherit inputs;
        system = "aarch64-darwin";
        pkgs = pkgsFor system;
        modules = commonModules ++ darwinModules ++ modules_;
      };

      homeManagerConfiguration = system: modules_: home-manager.lib.homeManagerConfiguration rec {
        pkgs = pkgsFor system;
        modules = homeModules ++ modules_;
      };

      forAllSystems = fn: nixpkgs.lib.genAttrs [ "x86_64-linux" "aarch64-darwin" ] (system: fn (pkgsFor system));
    in
    {
      formatter = forAllSystems (pkgs: pkgs.nixpkgs-fmt);

      nixosConfigurations = {
        wasabi = nixosSystem [ ./hosts/wasabi.nix ];
      };

      darwinConfigurations = {
        onigiri = darwinSystem [ ./hosts/onigiri.nix ];
      };

      homeConfigurations = {
        "oliver@onigiri" = homeManagerConfiguration "aarch64-darwin" [ ./home/${"oliver@onigiri"}.nix ];
      };
    };
}
