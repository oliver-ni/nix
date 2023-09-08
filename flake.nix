{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    darwin = {
      url = "github:lnl7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs@{ self, nixpkgs, home-manager, darwin }:
    let
      system = "aarch64-darwin";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
    in
    {
      darwinConfigurations.olivia = darwin.lib.darwinSystem {
        inherit pkgs system;
        modules = [
          home-manager.darwinModules.home-manager
          ./hosts/olivia/darwin.nix
        ];
      };
      darwinConfigurations.orange = darwin.lib.darwinSystem {
        inherit pkgs system;
        modules = [
          home-manager.darwinModules.home-manager
          ./hosts/orange/darwin.nix
        ];
      };
    };
}
