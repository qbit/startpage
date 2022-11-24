{
  description = "startpage: a tool for displaying initial content in a browser start page.";

  inputs.nixpkgs.url = "nixpkgs/nixos-22.05";

  outputs = { self, nixpkgs }:
    let
      supportedSystems =
        [ "x86_64-linux" "x86_64-darwin" "aarch64-linux" "aarch64-darwin" ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
      nixpkgsFor = forAllSystems (system: import nixpkgs { inherit system; });
    in {
      packages = forAllSystems (system:
        let pkgs = nixpkgsFor.${system};
        in {
          startpage = pkgs.perlPackages.buildPerlPackage {
            pname = "startpage";
            version = "v0.0.1";
            src = ./.;
            buildInputs = with pkgs.perlPackages; [ PerlTidy perl ];
            nativeBuildInputs = with pkgs.perlPackages; [
              perl
              Mojolicious
              MojoSQLite
              IOSocketSSL
              JSON
              Git
            ];

            outputs = [ "out" "dev" ];

            installPhase = ''
              mkdir -p $out/bin
              install startpage.pl $out/bin/startpage
            '';
          };
        });

      defaultPackage = forAllSystems (system: self.packages.${system}.startpage);
      devShells = forAllSystems (system:
        let pkgs = nixpkgsFor.${system};
        in {
          default = pkgs.mkShell {
            shellHook = ''
              PS1='\u@\h:\@; '
              echo "Perl `${pkgs.perl}/bin/perl --version`"
            '';
            buildInputs = with pkgs.perlPackages; [ PerlTidy pkgs.sqlite PerlCritic ];
            nativeBuildInputs = with pkgs.perlPackages; [
              perl
              Mojolicious
              MojoSQLite
              IOSocketSSL
              JSON
              Git
            ];
          };
        });
    };
}

