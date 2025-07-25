# Explicitly disable ACME services
{ config, pkgs, ... }:

{
  # Disable ACME services
  security.acme = {
    acceptTerms = false;
    defaults.email = "";
    certs = {};
  };
  
  # Disable any systemd services related to ACME
  systemd.services."acme-localhost" = {
    enable = false;
  };
  
  systemd.timers."acme-localhost" = {
    enable = false;
  };
}