#!/usr/bin/env bash
# Fabrique un zip de l'addon en local, SANS rien publier (pour tester en jeu).
# Usage : tools/make-zip.sh            -> /opt/wow/releases/NSRTAutoReminders-<version>.zip
#         OUT=~/zips tools/make-zip.sh -> autre dossier de sortie
set -euo pipefail

ADDON=NSRTAutoReminders
REPO=$(cd "$(dirname "$0")/.." && pwd)
OUT=${OUT:-/opt/wow/releases}

if   [ -f "$REPO/$ADDON.toc" ];        then SRC=$REPO
elif [ -f "$REPO/$ADDON/$ADDON.toc" ]; then SRC=$REPO/$ADDON
else echo "ERREUR : $ADDON.toc introuvable" >&2; exit 1; fi

TOC=$SRC/$ADDON.toc
VERSION=$(grep -m1 '^## Version:' "$TOC" | sed 's/^## Version:[[:space:]]*//' | tr -d '\r')
[ -n "$VERSION" ] || { echo "ERREUR : pas de '## Version:' dans le .toc" >&2; exit 1; }

# Chaque fichier liste dans le .toc doit exister (sinon erreur en jeu).
missing=0
while IFS= read -r line; do
  line=${line%$'\r'}
  [[ -z "$line" || "$line" == \#* ]] && continue
  f=${line//\\//}
  [ -f "$SRC/$f" ] || { echo "MANQUANT : $f" >&2; missing=1; }
done < "$TOC"
[ $missing -eq 0 ] || { echo "ERREUR : fichiers du .toc manquants" >&2; exit 1; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
mkdir "$TMP/$ADDON"
tar -C "$SRC" \
  --exclude=.git --exclude=.github --exclude=.venv --exclude=.env --exclude='*.env' \
  --exclude=__pycache__ --exclude='.cache*' --exclude=tools --exclude=docs \
  --exclude=releases --exclude='*.py' --exclude='*.zip' --exclude=.pkgmeta \
  --exclude=.gitignore --exclude=README.md --exclude=CHANGELOG.md \
  -cf - . | tar -C "$TMP/$ADDON" -xf -
# Addon dans un sous-dossier : le contenu de la racine du depot n'est pas copie.

mkdir -p "$OUT"
ZIP=$OUT/$ADDON-$VERSION.zip
rm -f "$ZIP"
(cd "$TMP" && zip -qr "$ZIP" "$ADDON")
echo "OK : $ZIP ($(du -h "$ZIP" | cut -f1))"
