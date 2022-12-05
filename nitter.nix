{ pkgs, system, ... }: {
    boot.isContainer = true;
    system.stateVersion = "23.05";
    services.nitter = {
        enable = true;
        server = {
            title = "bird";
            port = 16969;
            hostname = "bird.vvn.space";
            https = true;
        };
        preferences = {
            theme = "Dracula";
            autoplayGifs = false;
        };
        openFirewall = true;
        redisCreateLocally = true;
    };

    services.netdata = {
        enable = true;
        config = {
            global = {
                hostname = "bird.vvn.space";
            };
            db = {
                mode = "dbengine";
                "update every" = 5;
            };
            web = {
                "respect do not track policy" = "yes";
            };
            ml = {
                enabled = "no";
            };
        };
    };

    environment.systemPackages = with pkgs; [
        htop
        busybox
        overmind
        su
    ];

}
