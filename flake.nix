{
    inputs = {
        nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
        flake-utils.url = "github:numtide/flake-utils";
    };

    outputs = { self, nixpkgs, flake-utils, ... }:
    let
        nixConfigs.nitter = { system }:
            nixpkgs.lib.nixosSystem {
                inherit system;
                pkgs = import nixpkgs { inherit system; };
                modules = [ ./nitter.nix ];
            };
    in
        (flake-utils.lib.eachDefaultSystem (system:
            let pkgs = import nixpkgs { inherit system; };
            in {
                containers = {
                    nitter = let
                        nixosSystem = (nixConfigs.nitter { inherit system; }).config.system.build.toplevel;

                        unitRunner = unitName: let 
                            script = pkgs.runCommand "scriptified-${unitName}.sh" {} ''
                            ${pkgs.python3}/bin/python ${./systemd-unit-scriptifier.py} --unit ${nixosSystem}/etc/systemd/system/${unitName}.service --out $out
                        '';
                        in "/bin/sh ${script}";

                        procfile = pkgs.writeText "Procfile"
                        ''
                            sh: /bin/sh
                            bb: ${pkgs.busybox}/bin/busybox sh
                            nitter: ${unitRunner "nitter"}
                            redis: ${unitRunner "redis-nitter"}
                        '';

                        entry = pkgs.writeShellScriptBin "entry" ''
                            # install busybox
                            #${pkgs.busybox}/bin/busybox mkdir /bin
                            #${pkgs.busybox}/bin/busybox mkdir /sbin
                            #${pkgs.busybox}/bin/busybox --install -s

                            # activate rootfs. it doesn't work completely, but many files will be in place.
                            ${nixosSystem}/activate

                            # fixups
                            ${pkgs.busybox}/bin/busybox rm -rf /bin # remove existing /bin so we don't get /bin/bin
                            ${pkgs.busybox}/bin/busybox ln -s ${nixosSystem}/sw/bin /
                            ${pkgs.busybox}/bin/busybox ln -s ${nixosSystem}/sw/sbin /
                            ${pkgs.busybox}/bin/busybox ln -s ${nixosSystem}/sw/lib /
                            source /etc/profile

                            cp ${procfile} /Procfile
                            export OVERMIND_SOCKET=/tmp/.overmind.sock
                            OVERMIND_ANY_CAN_DIE=1 ${pkgs.overmind}/bin/overmind s -D
                            ${pkgs.overmind}/bin/overmind c
                            echo "this is fallback shell"
                            /bin/sh
                        '';
                    in pkgs.dockerTools.streamLayeredImage {
                        name = "nitter-nixos";
                        tag = "dev";
                        config = {
                            Cmd = [ "${entry}/bin/entry" ];
                        };
                    };
                };

            }) // {
            # for use with nixos-container create --bridge br0 --flake .#nitter nitter
            nixosConfigurations.nitter = nixConfigs.nitter { system = "x86_64-linux"; };
        });
}
