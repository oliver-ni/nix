{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    colima
    docker-client
  ];
}
