{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/e21fec321d73511849707a7585e4ea155ee4bf40";

  outputs = { nixpkgs, ... }:
    let
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
    in
    {
      packages.x86_64-linux = {
        electron = pkgs.electron_45;
        osslsigncode = pkgs.osslsigncode;
        gcclib = pkgs.stdenv.cc.cc.lib;
      };
      devShells.x86_64-linux.default = pkgs.mkShell {
        packages = with pkgs; [ nodejs_22 cargo rustc p7zip curl xxd imagemagick osslsigncode ];
      };
    };
}
