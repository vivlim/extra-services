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
            let 
                pkgs = import nixpkgs { inherit system; };
                buildAndDeployScript = pkgs.writeShellScriptBin "nitter_fly" 
                ''
                    nix build .#containers.x86_64-linux.nitter_fly
                    if [ $? -ne 0 ]; then echo "build failed" && exit 1; fi
                    ./result | docker load
                    if [ $? -ne 0 ]; then echo "loading image failed" && exit 1; fi
                    ${pkgs.flyctl}/bin/flyctl deploy --local-only
                    if [ $? -ne 0 ]; then echo "deployment failed" && exit 1; fi
                '';
                runLocalScript = pkgs.writeShellScriptBin "nitter_local" 
                ''
                    nix build .#containers.x86_64-linux.nitter_dev
                    if [ $? -ne 0 ]; then echo "build failed" && exit 1; fi
                    ./result | docker load
                    if [ $? -ne 0 ]; then echo "loading image failed" && exit 1; fi
                    docker run -it -p 127.0.0.1:16969:16969 nitter-nixos:dev
                    if [ $? -ne 0 ]; then echo "running failed" && exit 1; fi
                '';
            in {
                containers = (let
                    nixosSystem = (nixConfigs.nitter { inherit system; }).config.system.build.toplevel;

                    unitRunner = unitName: let 
                        script = pkgs.runCommand "scriptified-${unitName}.sh" {} ''
                        ${pkgs.python3}/bin/python ${./systemd-unit-scriptifier.py} --unit ${nixosSystem}/etc/systemd/system/${unitName}.service --out $out
                    '';
                    in "/bin/sh ${script}";

                    procfile = pkgs.writeText "Procfile"
                    ''
                        nitter: sleep 10 && ${unitRunner "nitter"}
                        redis: ${unitRunner "redis-nitter"}
                        sh: /bin/sh
                        netdata: ${unitRunner "netdata"}
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

                        if [ "$1" == "interactive" ]; then
                            OVERMIND_ANY_CAN_DIE=1 ${pkgs.overmind}/bin/overmind s -D
                            sleep 3
                            ${pkgs.overmind}/bin/overmind c
                        else
                            ${pkgs.overmind}/bin/overmind s
                        fi
                    '';
                    in {
                        nitter_dev = pkgs.dockerTools.streamLayeredImage {
                            name = "nitter-nixos";
                            tag = "dev";
                            config = {
                                Cmd = [ "${entry}/bin/entry" "interactive" ];
                            };
                        };
                        nitter_fly = pkgs.dockerTools.streamLayeredImage {
                            name = "nitter-nixos";
                            tag = "fly";
                            config = {
                                Cmd = [ "${entry}/bin/entry" ];
                            };
                        };
                    });

                devShell = pkgs.mkShell {
                    buildInputs = with pkgs; [flyctl buildAndDeployScript runLocalScript];
                    shellHook = ''
                    '';
                };
                

            }) // {
            # for use with nixos-container create --bridge br0 --flake .#nitter nitter
            nixosConfigurations.nitter = nixConfigs.nitter { system = "x86_64-linux"; };
        });
}
