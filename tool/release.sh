#!/usr/bin/env bash
#
# Construit l'APK de release du companion et le publie sur sports.logicraft.ch.
#
#   tool/release.sh
#
# Enchaîne `flutter build apk --release` (arm64, seule architecture distribuée)
# puis script/push-apk.sh du dépôt voisin sports-scope, qui lit versionName/
# versionCode DANS l'APK, vérifie la signature, dépose le binaire dans le volume
# `companion_apk` de production et demande confirmation avant de publier.
#
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

SPORTS_SCOPE_DIR=${SPORTS_SCOPE_DIR:-$HOME/dev/sports-scope}
PUSH_APK="$SPORTS_SCOPE_DIR/script/push-apk.sh"
APK="$PWD/build/app/outputs/flutter-apk/app-release.apk"

log() { printf '\n\033[1;34m==>\033[0m %s\n' "$1"; }
die() { printf '\n\033[1;31mErreur:\033[0m %s\n' "$1" >&2; exit 1; }

[ -f "$PUSH_APK" ] || die "$PUSH_APK introuvable (dépôt sports-scope absent ou déplacé — surcharge avec SPORTS_SCOPE_DIR=...)"

# Échoue tôt et clairement plutôt que de laisser Gradle le faire au milieu du
# build : cf. android/app/build.gradle.kts, qui refuse un build de release sans
# clé de signature plutôt que de retomber sur celle de debug.
[ -f android/key.properties ] || die "android/key.properties absent — voir HOWTO.md, « Construire un APK à distribuer »"

# ---------------------------------------------------------------------- version

current_version=$(sed -n 's/^version:[[:space:]]*//p' pubspec.yaml)
[ -n "$current_version" ] || die "impossible de lire 'version:' dans pubspec.yaml"

version_name=${current_version%%+*}
version_code=${current_version##*+}
suggested_version="${version_name}+$((version_code + 1))"

read -r -p $'\n'"Version actuelle : $current_version — nouvelle version [$suggested_version] : " new_version
new_version=${new_version:-$suggested_version}

[[ "$new_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+\+[0-9]+$ ]] \
  || die "format attendu X.Y.Z+N (versionName+versionCode), reçu : $new_version"

if [ "$new_version" != "$current_version" ]; then
  sed -i "s/^version:.*/version: $new_version/" pubspec.yaml
  log "pubspec.yaml : $current_version -> $new_version (à committer)"
fi

log "flutter pub get"
flutter pub get

log "flutter build apk --release --target-platform android-arm64"
flutter build apk --release --target-platform android-arm64

[ -f "$APK" ] || die "build terminé mais $APK introuvable"

log "Publication ($PUSH_APK)"
"$PUSH_APK" "$APK"
