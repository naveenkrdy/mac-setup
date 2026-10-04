#!/bin/bash
# Mac setup starter: gets a new Mac far enough to clone the private dot-files, then hands
# over to its bootstrap.sh. Run: bash -c "$(curl -fsSL <raw url of this file at a commit>)"
# Every step skips itself when it is already done, so a second run changes nothing.
set -uo pipefail
REPO=naveenkrdy/dot-files DIR="$HOME/Documents/Repo/dot-files" TOTAL=7 N=0
BREW="${MAC_SETUP_BREW:-/opt/homebrew}"   # the tests point it at a fake Homebrew
LOG_DIR="$HOME/Library/Logs/mac-setup"; (umask 077; mkdir -p "$LOG_DIR")
export SETUP_LOG="${SETUP_LOG:-$LOG_DIR/$(date +%Y-%m-%d-%H%M%S).log}"; (umask 077; : >> "$SETUP_LOG")
HB_URL=https://raw.githubusercontent.com/Homebrew/install/35da6871c4be7d7fdab2fd505fb7fa667926a2a5/install.sh
HB_SHA=5f333bbe53bc490e51e7ccb1df8779b3dd6ee73a1a7379efda216edb08ccb148  # run only on this sha256; move both together
G=$'\e[32m' R=$'\e[31m' Y=$'\e[1;33m' D=$'\e[2m' B=$'\e[1m' O=$'\e[0m'
[[ -t 1 ]] || G='' R='' Y='' D='' B='' O=''
stage() { N=$((N + 1)); T=$SECONDS; S=$(wc -l < "$SETUP_LOG"); L=$(printf '[%d/%d] %s' "$N" "$TOTAL" "$1"); printf '%-40s' "$L"; echo "== $L" >> "$SETUP_LOG"; }
line() { printf '\r\e[K%-40s %s %s(%d:%02d)%s\n' "$L" "$1" "$D" $(((SECONDS - T) / 60)) $(((SECONDS - T) % 60)) "$O"; }
ok() { line "${G}done$O${1:+ - $1}"; }
skip() { line "${D}already set up, skipped$O"; }
fail() { line "${R}failed$O: $1 - $2"; tail -n "+$((S + 2))" "$SETUP_LOG" | tail -n 15 | sed 's/^/      | /'; printf '\nFull log: %s\n' "$SETUP_LOG"; exit 1; }
note() { printf '\n\n%s  ACTION NEEDED%s\n  %s\n\n' "$Y" "$O" "$1"; }
ask() { note "$1"; printf '  %s ' "$2"; read -r < /dev/tty; echo; }
alive() { printf '\r\e[K%-40s %s %d:%02d' "$L" "$1" $(((SECONDS - $2) / 60)) $(((SECONDS - $2) % 60)); }
run() { # a command's output goes to the log; a spinner and the elapsed time show it is alive
  local s=$SECONDS i=0 f='|/-\'; "$@" >> "$SETUP_LOG" 2>&1 & local p=$!
  while kill -0 $p 2>/dev/null; do alive "${f:$((i++ % 4)):1}" "$s"; sleep 0.25; done; wait $p; }

[[ "$(uname -m)" == arm64 ]] || { echo "This setup is for Apple silicon Macs (arm64); this one is $(uname -m)."; exit 1; }
[[ "$(id -un)" == naveenkrdy ]] || { echo "Run this as the user naveenkrdy; you are $(id -un)."; exit 1; }
[[ -t 0 ]] || { echo "Run this in a terminal: it asks for your password and a GitHub login."; exit 1; }

printf '\n%sMac setup starter%s\n' "$B" "$O"
printf '  Installs the Xcode tools, Homebrew and GitHub CLI, logs in to GitHub,\n'
printf '  clones %s and runs its bootstrap.sh.\n  Log: %s\n\n' "$REPO" "$SETUP_LOG"

stage "Checks"; ok "Apple silicon, user naveenkrdy, terminal"
stage "Administrator password"
sudo -n true 2>/dev/null || note "Type your Mac login password below and press Enter (nothing shows while you type). Setup needs it to install tools."
sudo -v || fail "no password" "run the curl command again and type your Mac password"
( while kill -0 $$ 2>/dev/null; do sudo -n true; sleep 60; done ) > /dev/null 2>&1 & KEEP=$!
trap 'kill $KEEP 2>/dev/null' EXIT; ok "kept for this run"

stage "Xcode command-line tools"
if xcode-select -p > /dev/null 2>&1; then skip; else
  xcode-select --install >> "$SETUP_LOG" 2>&1
  note "A window asks to install the command-line developer tools: click Install, then Agree. This goes on by itself once they are in (up to 45 minutes)."
  s=$SECONDS; until xcode-select -p > /dev/null 2>&1; do
    ((SECONDS - s > 2700)) && fail "not in after 45 minutes" "run xcode-select --install, then the curl command again"
    alive "waiting" "$s"; sleep 5; done; ok; fi

stage "Homebrew"
if [[ -x "$BREW/bin/brew" ]]; then skip; else
  HB=$(curl -fsSL "$HB_URL" 2>> "$SETUP_LOG") || fail "the installer did not download" "check the internet, then run the curl command again"
  [[ "$(printf '%s\n' "$HB" | shasum -a 256 | cut -d' ' -f1)" == "$HB_SHA" ]] ||
    fail "the installer is not the pinned one" "tell the dot-files owner; nothing was run"
  if run env NONINTERACTIVE=1 /bin/bash -c "$HB"; then ok; else fail "the Homebrew installer stopped" "read the log, then run the curl command again"; fi; fi
eval "$("$BREW/bin/brew" shellenv)"

stage "GitHub CLI"
if command -v gh > /dev/null; then skip
elif run env HOMEBREW_NO_AUTO_UPDATE=1 brew install gh; then ok; else fail "brew install gh failed" "read the log, then run the curl command again"; fi

stage "GitHub login (personal account)"
if gh auth status -h github.com >> "$SETUP_LOG" 2>&1; then skip; else
  ask "Log in to your personal GitHub account. GitHub CLI shows a one-time code; press Enter in it to open the browser, then paste the code there." \
    "Press Enter to start:"
  if gh auth login --web --git-protocol https -h github.com -s admin:public_key; then ok; else fail "the login did not finish" "run the curl command again"; fi; fi

stage "Private dot-files"
CRED=(-c credential.helper= -c 'credential.helper=!gh auth git-credential')
if [[ -d "$DIR/.git" ]]; then
  old=$(git -C "$DIR" rev-parse HEAD)
  run git -C "$DIR" "${CRED[@]}" pull --ff-only || fail "git pull failed" "fix the clone at $DIR, then run the curl command again"
  if [[ "$(git -C "$DIR" rev-parse HEAD)" == "$old" ]]; then skip; else ok "updated"; fi
else
  mkdir -p "$(dirname "$DIR")"
  if run git "${CRED[@]}" clone "https://github.com/$REPO.git" "$DIR"; then ok "cloned"; else fail "the clone failed" "check gh auth status, then run the curl command again"; fi
fi

printf '\nHanding over to dot-files bootstrap.sh\n'
kill $KEEP 2>/dev/null; trap - EXIT
exec bash "$DIR/bootstrap.sh"
