{ pkgs, system, ... }: {
    boot.isContainer = true;
    system.stateVersion = "23.05";
    services.nitter = {
        enable = true;
        server = {
            title = "bird";
            port = 16969;
        };
        openFirewall = true;
        redisCreateLocally = true;
    };

    environment.systemPackages = with pkgs; [
        htop
        busybox
        overmind
        su
    ];

}
