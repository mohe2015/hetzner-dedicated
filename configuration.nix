# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running `nixos-help`).

{ config, pkgs, ... }:

{
  imports =
    [
      # Include the results of the hardware scan.
      ./hardware-configuration.nix
    ];


  security.acme = {
    acceptTerms = true;
    defaults.email = "Moritz.Hedtke@t-online.de";
  };

  services.postgresql = {
    package = pkgs.postgresql_14;
  };

  #services.seafile = {
  #  enable = true;
  #  adminEmail = "Moritz.Hedtke@t-online.de";
  #  initialAdminPassword = "insecureseafilepassword";
  #  ccnetSettings.General.SERVICE_URL = "https://seafile.selfmade4u.de";
  #  seahubExtraConf = ''
  #  OFFICE_SERVER_TYPE = 'CollaboraOffice'
  #  ENABLE_OFFICE_WEB_APP = True
  #  OFFICE_WEB_APP_BASE_URL = 'https://office.selfmade4u.de/hosting/discovery'
  #  WOPI_ACCESS_TOKEN_EXPIRATION = 30 * 60   # seconds
  #  OFFICE_WEB_APP_FILE_EXTENSION = ('odp', 'ods', 'odt', 'xls', 'xlsb', 'xlsm', 'xlsx','ppsx', 'ppt', 'pptm', 'pptx', 'doc', 'docm', 'docx')
  #  ENABLE_OFFICE_WEB_APP_EDIT = True
  #  OFFICE_WEB_APP_EDIT_FILE_EXTENSION = ('odp', 'ods', 'odt', 'xls', 'xlsb', 'xlsm', 'xlsx','ppsx', 'ppt', 'pptm', 'pptx', 'doc', 'docm', 'docx')
  #  '';
  #};

  virtualisation.oci-containers = {
    # Since 22.05, the default driver is podman but it doesn't work
    # with podman. It would however be nice to switch to podman.
    backend = "docker";
    containers.collabora = {
      image = "collabora/code";
      imageFile = pkgs.dockerTools.pullImage {
        imageName = "collabora/code";
        imageDigest = "sha256:32c05e2d10450875eb153be11bfb7683fa0db95746e1f59d8c2fc3d988b45445";
        sha256 = "sha256-laQJldVH8ri54lFecJ26tGdlOGtnb+w7Bb+GJ/spzr8=";
      };
      ports = [ "9980:9980" ];
      environment = {
        domain = "nextcloud.selfmade4u.de|seafile.selfmade4u.de";
        extra_params = "--o:ssl.enable=false --o:ssl.termination=true";
      };
      extraOptions = [ "--cap-add" "SYS_ADMIN" ];
    };
  };

  services.nextcloud = {
    enable = true;
    hostName = "nextcloud.selfmade4u.de";
    package = pkgs.nextcloud27;
    extraApps = (with config.services.nextcloud.package.packages.apps; {
      # https://github.com/NixOS/nixpkgs/blob/master/pkgs/servers/nextcloud/packages/27.json
      inherit calendar contacts deck files_texteditor forms groupfolders impersonate mail maps news notes onlyoffice polls spreed tasks;
    }) // {
      richdocuments = pkgs.fetchNextcloudApp rec {
        license = "agpl3Plus";
        sha256 = "sha256-0kXZEgLBtCa5/EYe/Keni2SWizHjvokFTAv0t7RoOlY=";
        url = "https://github.com/nextcloud-releases/richdocuments/releases/download/v8.2.2/richdocuments-v8.2.2.tar.gz";
      };
    };
    extraAppsEnable = true;
    https = true;
    maxUploadSize = "5G";
    webfinger = true;
    database = {
      createLocally = true;
    };
    config = {
      dbtype = "pgsql";
      adminpassFile = "/etc/nextcloud-admin-pass";
      defaultPhoneRegion = "DE";
    };
    enableImagemagick = true;
    caching.apcu = true;
    configureRedis = true;
  };

  services.nginx = {
    enable = true;
    virtualHosts = {
      "seafile.selfmade4u.de" = {
        forceSSL = true;
        enableACME = true;

        locations."/".proxyPass = "http://unix:/run/seahub/gunicorn.sock";
        locations."/seafhttp" = {
          proxyPass = "http://127.0.0.1:8082";
          extraConfig = ''
            rewrite ^/seafhttp(.*)$ $1 break;
            client_max_body_size 0;
            proxy_connect_timeout  36000s;
            proxy_read_timeout  36000s;
            proxy_send_timeout  36000s;
            send_timeout  36000s;
            proxy_http_version 1.1;
          '';
        };
      };
      ${config.services.nextcloud.hostName} = {
        forceSSL = true;
        enableACME = true;
      };
      "office.selfmade4u.de" = {
        forceSSL = true;
        enableACME = true;
        locations = {
          # https://sdk.collaboraonline.com/docs/installation/Proxy_settings.html#reverse-proxy-with-nginx-webserver
          # static files
          "^~ /browser" = {
            priority = 0;
            proxyPass = "http://localhost:9980";
            extraConfig = ''
              proxy_set_header Host $host;
            '';
          };
          # WOPI discovery URL
          "^~ /hosting/discovery" = {
            priority = 100;
            proxyPass = "http://localhost:9980";
            extraConfig = ''
              proxy_set_header Host $host;
            '';
          };

          # Capabilities
          "^~ /hosting/capabilities" = {
            priority = 200;
            proxyPass = "http://localhost:9980";
            extraConfig = ''
              proxy_set_header Host $host;
            '';
          };

          # download, presentation, image upload and websocket
          "~ ^/cool/(.*)/ws$" = {
            priority = 300;
            proxyPass = "http://localhost:9980";
            extraConfig = ''
              proxy_set_header Upgrade $http_upgrade;
              proxy_set_header Connection "Upgrade";
              proxy_set_header Host $host;
              proxy_read_timeout 36000s;
            '';
          };

          # download, presentation and image upload
          "~ ^/(c|l)ool" = {
            priority = 400;
            proxyPass = "http://localhost:9980";
            extraConfig = ''
              proxy_set_header Host $host;
            '';
          };

          # Admin Console websocket
          "^~ /cool/adminws" = {
            priority = 500;
            proxyPass = "http://localhost:9980";
            extraConfig = ''
              proxy_set_header Upgrade $http_upgrade;
              proxy_set_header Connection "Upgrade";
              proxy_set_header Host $host;
              proxy_read_timeout 36000s;
            '';
          };
        };
      };
    };
  };


  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  boot.kernelPackages = pkgs.linuxPackages_latest;

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "dedicated"; # Define your hostname.
  # Pick only one of the below networking options.
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.
  # networking.networkmanager.enable = true;  # Easiest to use and most distros use this by default.

  systemd.network.enable = true;
  systemd.network.networks."10-wan" = {
    # match the interface by name
    matchConfig.Name = "enp1s0";
    address = [
      # configure addresses including subnet mask
      "88.99.224.186/32"
      "2a01:4f8:1c1b:5828::1/64"
    ];
    routes = [
      # create default routes for both IPv6 and IPv4
      { routeConfig.Gateway = "fe80::1"; }
      {
        routeConfig = {
          Gateway = "172.31.1.1";
          GatewayOnLink = true;
        };
      }
    ];
    # make the routes on this interface a dependency for network-online.target
    linkConfig.RequiredForOnline = "routable";
  };

  # Set your time zone.
  time.timeZone = "Europe/Berlin";

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";
  console = {
    #   font = "Lat2-Terminus16";
    keyMap = "de-latin1";
    #    useXkbConfig = true; # use xkbOptions in tty.
  };

  # Enable the X11 windowing system.
  # services.xserver.enable = true;




  # Configure keymap in X11
  # services.xserver.layout = "us";
  # services.xserver.xkbOptions = "eurosign:e,caps:escape";

  # Enable CUPS to print documents.
  # services.printing.enable = true;

  # Enable sound.
  # sound.enable = true;
  # hardware.pulseaudio.enable = true;

  # Enable touchpad support (enabled default in most desktopManager).
  # services.xserver.libinput.enable = true;

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.moritz = {
    isNormalUser = true;
    extraGroups = [ "wheel" ]; # Enable ‘sudo’ for the user.
    #  packages = with pkgs; [
    #    firefox
    #     tree
    #   ];
  };

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    git
    htop
    gh
    nixpkgs-fmt
    #   vim # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
    #   wget
  ];

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  services.openssh.enable = true;

  # Open ports in the firewall.
  networking.firewall.allowedTCPPorts = [ 80 443 ];
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # Copy the NixOS configuration file and link it from the resulting system
  # (/run/current-system/configuration.nix). This is useful in case you
  # accidentally delete configuration.nix.
  # system.copySystemConfiguration = true;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It's perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "23.11"; # Did you read the comment?

}

