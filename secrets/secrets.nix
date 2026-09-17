let
  oliver = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHXDswYZKz5teffU3I4kxl1Rr4Z+9hdywNsBypb//Icv";
  ochazuke = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIDC3oviLnV+m939TBIk1PMyDZkBt0pCSixtNnT+B0Pr";
  keys = [
    oliver
    ochazuke
  ];
in
{
  "sonarr-api-key.age".publicKeys = keys;
  "radarr-api-key.age".publicKeys = keys;
  "prowlarr-api-key.age".publicKeys = keys;
}
