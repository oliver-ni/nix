
{ pkgs, ... }:

let
  python-packages = p: with p; [
    ipython
  ];
in
{
  home.packages = [
    (pkgs.python311.withPackages python-packages)
  ];
}

