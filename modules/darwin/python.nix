{ pkgs, ... }:

let
  python-packages = p: with p; [
    ipython
    black
  ];
in
{
  environment.systemPackages = [
    (pkgs.python311.withPackages python-packages)
  ];
}

