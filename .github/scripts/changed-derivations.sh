#!/usr/bin/env bash
set -euo pipefail

out_dir="${1:-.github/changed-derivations}"
mkdir -p "$out_dir"
flake_ref="path:$PWD"

systems=(
  x86_64-linux
  aarch64-linux
  aarch64-darwin
)

snapshot() {
  local label="$1"
  local out="$out_dir/${label}.tsv"
  local names_file="$out_dir/${label}-names.txt"
  : > "$out"

  for system in "${systems[@]}"; do
    echo "Snapshotting ${label} derivations for ${system}" >&2
    nix eval --impure --json --expr "
      let
        flake = builtins.getFlake \"$flake_ref\";
        pkgs = import flake.inputs.nixpkgs {
          system = \"$system\";
          config = {
            allowUnfree = true;
            permittedInsecurePackages = [];
          };
        };
        packages = flake.packages.\"$system\";
        # RustDesk is intentionally updated and built independently of the
        # flake-input workflow because its vendored dependencies are fragile.
        excludedPackages = [ \"rustdesk\" ];
      in
        builtins.filter
          (name:
            name != \"default\"
            && !(builtins.elem name excludedPackages)
            && pkgs.lib.meta.availableOn pkgs.stdenv.hostPlatform packages.\${name}
          )
          (builtins.attrNames packages)
    " | jq -r '.[]' > "$names_file"

    while IFS= read -r attr; do
      local ref=".#packages.${system}.\"${attr}\".drvPath"
      local drv
      if drv="$(
        NIXPKGS_ALLOW_INSECURE=1 NIXPKGS_ALLOW_UNFREE=1 \
          nix eval --impure --raw "$ref" 2>"$out_dir/${label}-${system}-${attr}.err"
      )"; then
        printf '%s\t%s\t%s\n' "$system" "$attr" "$drv" >> "$out"
        rm -f "$out_dir/${label}-${system}-${attr}.err"
      else
        echo "warning: could not evaluate ${ref}; skipping" >&2
        sed 's/^/  /' "$out_dir/${label}-${system}-${attr}.err" >&2 || true
      fi
    done < "$names_file"
  done

  sort -o "$out" "$out"
}

to_keyed() {
  local input="$1"
  local output="$2"
  awk -F '\t' 'BEGIN { OFS = "\t" } { print $1 "|" $2, $3 }' "$input" | sort > "$output"
}

snapshot before

echo "Updating flake inputs" >&2
nix flake update

if [ -x packages/caddy-l4/update.sh ]; then
  echo "Refreshing Caddy L4 package metadata" >&2
  nix develop --command ./packages/caddy-l4/update.sh
fi

snapshot after

to_keyed "$out_dir/before.tsv" "$out_dir/before-keyed.tsv"
to_keyed "$out_dir/after.tsv" "$out_dir/after-keyed.tsv"

join -t $'\t' -a2 -e '' -o '0,1.2,2.2' \
  "$out_dir/before-keyed.tsv" \
  "$out_dir/after-keyed.tsv" \
  | awk -F '\t' 'BEGIN { OFS = "\t" } $2 != $3 { print $1, $2, $3 }' \
  > "$out_dir/changed.tsv"

jq -Rn '
  [
    inputs
    | split("\t")
    | select(length == 3)
    | .[0] as $key
    | ($key | split("|")) as $parts
    | {
        system: $parts[0],
        attr: $parts[1],
        before: .[1],
        after: .[2]
      }
  ]
  | sort_by(.system, .attr)
' < "$out_dir/changed.tsv" > "$out_dir/changed.json"

jq '
  def runner($system):
    if $system == "x86_64-linux" then "ubuntu-24.04"
    elif $system == "aarch64-linux" then "ubuntu-22.04-arm"
    elif $system == "aarch64-darwin" then "macos-15"
    else error("unsupported system: " + $system)
    end;

  sort_by(.system, .attr)
  | group_by(.system)
  | map({
      system: .[0].system,
      runner: runner(.[0].system),
      attrs: map(.attr)
    })
  | { include: . }
' "$out_dir/changed.json" > "$out_dir/matrix.json"

changed_count="$(jq 'length' "$out_dir/changed.json")"
if [ "$changed_count" -gt 0 ]; then
  changed=true
else
  changed=false
fi

if git diff --quiet -- flake.lock packages/caddy-l4; then
  has_diff=false
else
  has_diff=true
fi

{
  echo "changed=${changed}"
  echo "has_diff=${has_diff}"
  echo "matrix=$(jq -c . "$out_dir/matrix.json")"
  echo "changed_count=${changed_count}"
} >> "${GITHUB_OUTPUT:-/dev/null}"

{
  echo "## Changed package derivations"
  echo
  if [ "$changed_count" -eq 0 ]; then
    echo "No package derivations changed."
  else
    jq -r '.[] | "- `\(.system)` `\(.attr)`: `\(.before)` -> `\(.after)`"' "$out_dir/changed.json"
  fi
} > "$out_dir/summary.md"

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  cat "$out_dir/summary.md" >> "$GITHUB_STEP_SUMMARY"
fi
