#!/usr/bin/env bash
# Exercise installation and launcher dispatch without touching the installed app.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT
FIXTURE_DIR="$TEST_DIR/repo with spaces"
BIN_DIR="$TEST_DIR/bin with spaces"
mkdir -p "$FIXTURE_DIR" "$BIN_DIR"
cp "$REPO_DIR/install.sh" "$REPO_DIR/record-it" "$FIXTURE_DIR/"
for command in setup_mac restart kill; do
  printf '#!/usr/bin/env bash\necho "%s"\n' "$command" > "$FIXTURE_DIR/$command.sh"
done

assert_equal() {
  if [[ "$1" != "$2" ]]; then
    printf 'Expected <%s>, got <%s>\n' "$2" "$1" >&2
    exit 1
  fi
}

cd "$TEST_DIR"
bash "$FIXTURE_DIR/install.sh" "$BIN_DIR" >/dev/null
bash "$FIXTURE_DIR/install.sh" "$BIN_DIR" >/dev/null
assert_equal "$(readlink "$BIN_DIR/record-it")" "$FIXTURE_DIR/record-it"
assert_equal "$("$BIN_DIR/record-it" setup)" "setup_mac"
assert_equal "$("$BIN_DIR/record-it" install)" "setup_mac"
assert_equal "$("$BIN_DIR/record-it" restart)" "restart"
assert_equal "$("$BIN_DIR/record-it" stop)" "kill"
assert_equal "$("$BIN_DIR/record-it" kill)" "kill"

# Cover relative links and a second symlink in the chain too.
ln -s "repo with spaces/record-it" "$TEST_DIR/relative-launcher"
ln -s "$TEST_DIR/relative-launcher" "$TEST_DIR/chained-launcher"
assert_equal "$("$TEST_DIR/chained-launcher" setup)" "setup_mac"

mkdir -p "$TEST_DIR/mock-bin" "$TEST_DIR/Record It.app"
printf '#!/usr/bin/env bash\nprintf "opened:%%s\\n" "$1"\n' > "$TEST_DIR/mock-bin/open"
chmod +x "$TEST_DIR/mock-bin/open"
export PATH="$TEST_DIR/mock-bin:$PATH"
export RECORD_IT_APP_DIR="$TEST_DIR/Record It.app"
assert_equal "$("$BIN_DIR/record-it")" "opened:$RECORD_IT_APP_DIR"
rm -rf "$RECORD_IT_APP_DIR"
assert_equal "$("$BIN_DIR/record-it" start)" "$(printf 'setup_mac\nopened:%s' "$RECORD_IT_APP_DIR")"

if "$BIN_DIR/record-it" unknown >/dev/null 2>&1; then
  echo "An unknown launcher command should fail." >&2
  exit 1
else
  assert_equal "$?" "2"
fi
bash "$FIXTURE_DIR/install.sh" --help >/dev/null
if bash "$FIXTURE_DIR/install.sh" --unknown >/dev/null 2>&1; then
  exit 1
else
  assert_equal "$?" "2"
fi
mkdir -p "$TEST_DIR/directory-conflict/record-it"
if bash "$FIXTURE_DIR/install.sh" "$TEST_DIR/directory-conflict" >/dev/null 2>&1; then
  exit 1
fi
echo "Installer and launcher checks passed."
