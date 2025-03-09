{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.clan.iwd;
in
{
  options.clan.iwd= {
    networks = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule (
          { name, ... }:
          {
            options = {
              ssid = lib.mkOption {
                type = lib.types.str;
                default = name;
                description = "The name of the wifi network";
              };
              AutoConnect = lib.mkOption {
                type = lib.types.bool;
                default = true;
                description = "Automatically try to join this wifi network";
              };
            };
          }
        )
      );
      default = { };
      description = "Wifi networks to predefine";
    };
  };
  
  config = lib.mkMerge [
    (lib.mkIf (cfg.networks != { }) {
      # Setup generators for WiFi passwords
      clan.core.vars.generators = lib.mapAttrs' (name: value:
        lib.nameValuePair "wifi-${value.ssid}" {
          prompts.password = {
            description = "WiFi password for '${value.ssid}'";
            type = "hidden";
          };
          files.config = {
            secret = true;
          };
          runtimeInputs = [ pkgs.coreutils ];
    script = ''
            # Get the password and escape special characters
            PASSWORD=$(cat $prompts/password | ${lib.getExe pkgs.gnused} 's/\\/\\\\/g; s/\t/\\t/g; s/\r/\\r/g; s/^ /\\s/g')
            
            # Create a properly formatted IWD network configuration file
            cat > "$out/config" << EOF
            [Settings]
              AutoConnect=${if value.AutoConnect then "true" else "false"}
            [Security]
              Passphrase=$PASSWORD
            EOF
          '';        }
      ) cfg.networks;
      
      # Create symlinks to the generated configuration files
      systemd.tmpfiles.rules = lib.mapAttrsToList (
        _: value: 
        "C /var/lib/iwd/${value.ssid}.psk 0600 root root - ${config.clan.core.vars.generators."wifi-${value.ssid}".files.config.path}"
      ) cfg.networks;
    })
    {
      # disable wpa supplicant
      networking.wireless.enable = false;
      # Set the network manager backend to iwd
      networking.networkmanager.wifi.backend = "iwd";
      # Use iwd instead of wpa_supplicant. It has a user friendly CLI
      networking.wireless.iwd = {
        enable = true;
        settings = {
          Network = {
            EnableIPv6 = true;
            RoutePriorityOffset = 300;
          };
          Settings.AutoConnect = true;
        };
      };
    }
  ];
}
