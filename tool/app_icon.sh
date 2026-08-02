#!/usr/bin/env bash
#
# (Re)génère les icônes de lancement depuis tool/icon/*.svg.
#
#   tool/app_icon.sh
#
# Les PNG de android/app/src/main/res/mipmap-*/ sont GÉNÉRÉS : ne pas les éditer,
# éditer les SVG et relancer — même convention que assets/sounds/ et
# tool/radar_tones.dart.
#
# Le rasteriseur est Chrome sans écran, faute d'ImageMagick ou de librsvg sur le
# poste. Ce n'est pas un choix d'élégance : c'est le seul moteur SVG déjà installé,
# et il rend le même sous-ensemble que celui des navigateurs, donc exactement ce que
# montre `public/icon.svg` du site.
#
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

CHROME=${CHROME:-google-chrome}
RES=android/app/src/main/res
SRC=tool/icon

command -v "$CHROME" >/dev/null || {
  echo "Erreur: $CHROME introuvable (définis CHROME=...)" >&2
  exit 1
}

render() { # <svg> <px> <destination>
  local svg=$1 px=$2 out=$3
  mkdir -p "$(dirname "$out")"
  # `--default-background-color=00000000` : sans lui Chrome peint un fond blanc, ce
  # qui donnerait une couche avant opaque — et un carré blanc derrière le masque du
  # lanceur au lieu du fond noir.
  "$CHROME" --headless --disable-gpu --no-sandbox --hide-scrollbars \
    --default-background-color=00000000 \
    --screenshot="$out" --window-size="$px,$px" \
    "file://$PWD/$svg" >/dev/null 2>&1
  printf '  %-56s %spx\n' "$out" "$px"
}

echo "Icône héritée (Android ≤ 7 : image posée telle quelle, fond compris)"
# 48 dp aux cinq densités.
render "$SRC/legacy.svg" 48 "$RES/mipmap-mdpi/ic_launcher.png"
render "$SRC/legacy.svg" 72 "$RES/mipmap-hdpi/ic_launcher.png"
render "$SRC/legacy.svg" 96 "$RES/mipmap-xhdpi/ic_launcher.png"
render "$SRC/legacy.svg" 144 "$RES/mipmap-xxhdpi/ic_launcher.png"
render "$SRC/legacy.svg" 192 "$RES/mipmap-xxxhdpi/ic_launcher.png"

echo "Couche avant de l'icône adaptative (Android 8+)"
# 108 dp aux mêmes densités : la couche est plus grande que l'icône visible, le
# lanceur y taille sa forme et s'en sert pour les animations de parallaxe.
render "$SRC/foreground.svg" 108 "$RES/mipmap-mdpi/ic_launcher_foreground.png"
render "$SRC/foreground.svg" 162 "$RES/mipmap-hdpi/ic_launcher_foreground.png"
render "$SRC/foreground.svg" 216 "$RES/mipmap-xhdpi/ic_launcher_foreground.png"
render "$SRC/foreground.svg" 324 "$RES/mipmap-xxhdpi/ic_launcher_foreground.png"
render "$SRC/foreground.svg" 432 "$RES/mipmap-xxxhdpi/ic_launcher_foreground.png"

echo "Fait."
