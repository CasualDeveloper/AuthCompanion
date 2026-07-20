#!/bin/sh

set -eu

[ "$#" -eq 1 ] || {
    echo "usage: verify-release.sh <authcompanion-version.tar.gz>" >&2
    exit 2
}

archive=$1
[ -f "$archive" ] && [ ! -L "$archive" ] || {
    echo "release archive is missing or unsafe: $archive" >&2
    exit 1
}
archive_size=$(stat -f '%z' "$archive")
[ "$archive_size" -le 16777216 ] || {
    echo "release archive exceeds the 16 MiB compressed-size limit" >&2
    exit 1
}

archive_name=$(basename "$archive")
package_name=${archive_name%.tar.gz}
version=${package_name#authcompanion-}
[ "$package_name" = "authcompanion-$version" ] && \
    printf '%s\n' "$version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || {
    echo "archive name does not contain a semantic version" >&2
    exit 1
}

scratch_root=$(mktemp -d "${TMPDIR:-/tmp}/authcompanion-verify.XXXXXX")
cleanup() {
    [ ! -d "$scratch_root" ] || rm -rf -- "$scratch_root"
}
trap cleanup EXIT

tar -tzf "$archive" > "$scratch_root/entries"
tar -tvzf "$archive" > "$scratch_root/listing"
awk '
    /^\// { exit 1 }
    /(^|\/)\.\.($|\/)/ { exit 1 }
' "$scratch_root/entries" || {
    echo "archive contains an unsafe path" >&2
    exit 1
}
awk 'substr($1, 1, 1) != "-" && substr($1, 1, 1) != "d" { exit 1 }' \
    "$scratch_root/listing" || {
    echo "archive contains a non-regular entry" >&2
    exit 1
}
awk '
    $5 > 16777216 { exit 1 }
    { total += $5 }
    END { if (total > 67108864) exit 1 }
' "$scratch_root/listing" || {
    echo "archive exceeds the uncompressed size limits" >&2
    exit 1
}

cat > "$scratch_root/expected" <<EOF
$package_name/
$package_name/LICENSE
$package_name/README.md
$package_name/SECURITY.md
$package_name/SHA256SUMS
$package_name/bin/
$package_name/bin/authcompanion
EOF
LC_ALL=C sort "$scratch_root/entries" > "$scratch_root/entries.sorted"
LC_ALL=C sort "$scratch_root/expected" > "$scratch_root/expected.sorted"
diff -u "$scratch_root/expected.sorted" "$scratch_root/entries.sorted"

tar -xzf "$archive" -C "$scratch_root"
package="$scratch_root/$package_name"
find "$package" -type l -exec false {} +
(
    cd "$package"
    shasum -a 256 -c SHA256SUMS
)

cli="$package/bin/authcompanion"
[ "$(stat -f '%Lp' "$cli")" = "555" ] || {
    echo "CLI mode must be 0555" >&2
    exit 1
}
[ "$($cli --version)" = "authcompanion $version" ]
$cli --help | grep -Fq 'authcompanion setup --yes'

lipo "$cli" -verify_arch arm64
lipo "$cli" -verify_arch x86_64
[ "$(lipo -archs "$cli" | wc -w | tr -d ' ')" -eq 2 ]
codesign --verify --strict "$cli"
signature=$(codesign -d --verbose=4 "$cli" 2>&1)
printf '%s\n' "$signature" | grep -Fq 'Signature=adhoc'
printf '%s\n' "$signature" | grep -Eq '^CodeDirectory .*flags=.*\(adhoc,runtime\)'
for architecture in arm64 x86_64; do
    minos=$(vtool -arch "$architecture" -show-build "$cli" | \
        awk '/^[[:space:]]*minos / { print $2 }')
    [ "$minos" = "14.0" ]
    otool -arch "$architecture" -L "$cli" | sed -n '2,$p' | \
        awk '{ print $1 }' | while IFS= read -r dependency; do
            case "$dependency" in
                /usr/lib/*|/System/Library/*) ;;
                *) echo "unexpected linked dependency: $dependency" >&2; exit 1 ;;
            esac
        done
done

set +e
"$cli" status --format json > "$scratch_root/status.json" 2> "$scratch_root/status.stderr"
status_exit=$?
set -e
[ "$status_exit" -eq 0 ] || [ "$status_exit" -eq 1 ]
[ ! -s "$scratch_root/status.stderr" ]
python3 - "$scratch_root/status.json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    response = json.load(handle)
assert response["schemaVersion"] == 1
assert response["product"] == "AuthCompanion"
assert response["operation"] == "status"
assert response["changed"] is False
PY

echo "PASS: verified AuthCompanion $version release archive"
