{ pkgs, ... }:

let
  python-packages = p: with p; [
    ipython
    black
    numpy
  ];
in
{
  environment.systemPackages = with pkgs; [
    (python311.withPackages python-packages)
    poetry
  ];
}

