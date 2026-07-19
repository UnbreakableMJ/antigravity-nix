{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  buildPythonPackage,
  absl-py,
  google-genai,
  mcp,
  pydantic,
  uvicorn,
  websockets,
  protobuf,
}:
let
  system = stdenv.hostPlatform.system;

  versions = builtins.fromJSON (builtins.readFile ../artifacts/versions.json);
  manifest =
    versions."Antigravity SDK".${system} or (throw "Unsupported system for Antigravity SDK: ${system}");

  # Extract version from the wheel filename in the URL
  version =
    let
      match = builtins.match ".*/google_antigravity-([0-9]+\\.[0-9]+\\.[0-9]+)-py3-.*\\.whl" manifest.url;
    in
    if match != null then builtins.elemAt match 0 else "unknown";
in
buildPythonPackage {
  pname = "google-antigravity";
  inherit version;
  format = "wheel";

  src = fetchurl {
    inherit (manifest) url;
    inherit (manifest) hash;
  };

  nativeBuildInputs = lib.optionals stdenv.hostPlatform.isLinux [
    autoPatchelfHook
  ];

  # The wheel bundles a prebuilt native binary (google/antigravity/bin/localharness)
  # dynamically linked only against glibc, so no extra buildInputs are needed
  # beyond what autoPatchelfHook already finds via stdenv.

  propagatedBuildInputs = [
    absl-py
    google-genai
    mcp
    pydantic
    uvicorn
    websockets
    protobuf
  ];

  doCheck = false;
  pythonImportsCheck = [ "google.antigravity" ];

  meta = with lib; {
    description = "Google Antigravity SDK - build custom agents on Antigravity and Gemini";
    homepage = "https://antigravity.google/docs/sdk/overview";
    license = licenses.asl20;
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
      "aarch64-darwin"
    ];
  };
}
