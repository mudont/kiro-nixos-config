# User account configuration
{ config, pkgs, ... }:

{
  # User configuration
  users.users.murali = {
    isNormalUser = true;
    description = "Murali - Development User";
    extraGroups = [ "wheel" "networkmanager" "docker" "samba" "audio" "video" ];
    shell = pkgs.zsh;
    home = "/home/murali";
    createHome = true;
    
    # SSH authorized keys for passwordless access from Mac
    openssh.authorizedKeys.keys = [
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDJOZDTATW1BrvtVR2pjgkFWZaawT5qKdNM3Z7o8KHmf59zB8LbRNnUXgRBe+Ir5jA0Wcsknup/u+eLGkPIJi0LqHtr2IPu5UFgJ10M0HQNqHrDZW+uiLWvZymSKHROOCnOOPvTWvV9zcIn16PDX0Zwdmg6tzTxkf4J657vj5+nSKkHm8v5Bfau7rWFzyLTAIDi+jEb+KDkvHrC6z8tYzHY+GoZoG8rHXXoxZQBKjPSNI5O4MI3K+GDBQmRgxQDyOnDAtbGSsFJCms0khEUl387VQTvtjUKRZo0gOnZkCiVKlGycydz8WyrozQ7JDQZkXKd2jELFyUWgOHzjekvyQTJ murali@Mac-Pro-de-Abhi.local"
    ];
    
    # Initial password for emergency access
    hashedPassword = "$6$rounds=4096$saltsalt$3MEaFIjKWrBtwbsw9/93/runLyXgbHjqq8FgGlrmJ.aJn/PgH.zWOQbp9Early60JmvKxZp.roQ6g/6Otx2e.";
  };
  
  # Create samba group for file sharing
  users.groups.samba = {};
  
  # Enable sudo for wheel group without password
  security.sudo = {
    enable = true;
    wheelNeedsPassword = false;
  };
  
  # Set default shell for new users
  users.defaultUserShell = pkgs.zsh;
}