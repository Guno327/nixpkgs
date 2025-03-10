{
  lib,
  stdenv,
  stdenvNoCC,
  fetchFromGitHub,
  makeWrapper,
  cacert,
  gitMinimal,
  nodejs_20,
  yarn,
  nixosTests,
  nix-update-script,
}:
let
  version = "25.1.0";
  src = fetchFromGitHub {
    owner = "actualbudget";
    repo = "actual-server";
    tag = "v${version}";
    hash = "sha256-zpZNITXd9QOJNRz8RbAuHH1hrrWPEGsrROGWJuYXqrc=";
  };

  yarn_20 = yarn.override { nodejs = nodejs_20; };

  # We cannot use fetchYarnDeps because that doesn't support yarn2/berry
  # lockfiles (see https://github.com/NixOS/nixpkgs/issues/254369)
  offlineCache = stdenvNoCC.mkDerivation {
    name = "actual-server-${version}-offline-cache";
    inherit src;

    nativeBuildInputs = [
      cacert # needed for git
      gitMinimal # needed to download git dependencies
      yarn_20
    ];

    SUPPORTED_ARCHITECTURES = builtins.toJSON {
      os = [
        "darwin"
        "linux"
      ];
      cpu = [
        "arm"
        "arm64"
        "ia32"
        "x64"
      ];
      libc = [
        "glibc"
        "musl"
      ];
    };

    buildPhase = ''
      runHook preBuild

      export HOME=$(mktemp -d)
      yarn config set enableTelemetry 0
      yarn config set cacheFolder $out
      yarn config set --json supportedArchitectures "$SUPPORTED_ARCHITECTURES"
      yarn

      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall

      mkdir -p $out
      cp -r ./node_modules $out/node_modules

      runHook postInstall
    '';
    dontFixup = true;

    outputHashAlgo = "sha256";
    outputHashMode = "recursive";
    outputHash =
      {
        x86_64-linux = "sha256-N31aAAkznncKlygyeH5A3TrnOinXVz7CTQ8/G4QX6hY=";
        aarch64-linux = "sha256-j7BFAKXi+TKIlmHBjbx6rwaKuAo6gnOlv6FV8rnlld0=";
        aarch64-darwin = "sha256-YpUQYOLJHYxWuE6ToLFkXWEloAau9bLBvdbpNh8jRZQ=";
        x86_64-darwin = "sha256-AioO82Y6mK0blSQRhhZZtWmduUcYwyVAewcXEVClJUg=";
      }
      .${stdenv.hostPlatform.system} or (throw "Unsupported system: ${stdenv.hostPlatform.system}");
  };
in
stdenv.mkDerivation {
  pname = "actual-server";
  inherit version src;

  nativeBuildInputs = [
    makeWrapper
    yarn_20
  ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/{bin,lib,lib/actual}
    cp -r ${offlineCache}/node_modules/ $out/lib/actual
    cp -r ./ $out/lib/actual

    makeWrapper ${lib.getExe nodejs_20} "$out/bin/actual-server" \
      --add-flags "$out/lib/actual/app.js" \
      --set NODE_PATH "$out/node_modules"

    runHook postInstall
  '';

  passthru = {
    inherit offlineCache;
    tests = nixosTests.actual;
    passthru.updateScript = nix-update-script { };
  };

  meta = {
    changelog = "https://actualbudget.org/docs/releases";
    description = "Super fast privacy-focused app for managing your finances";
    homepage = "https://actualbudget.org/";
    mainProgram = "actual-server";
    license = lib.licenses.mit;
    maintainers = [
      lib.maintainers.oddlama
      lib.maintainers.patrickdag
    ];
  };
}
