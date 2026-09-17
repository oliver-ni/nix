{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    kubectl
    kubectx
    kubeseal
    kubetail
    kubernetes-helm
    krew
  ];
}
