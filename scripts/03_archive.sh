
#!/usr/bin/env bash
# scripts/03_archive.sh : archive tar.gz datée des résultats + somme de contrôle.
# Usage : scripts/03_archive.sh [dossier ...] (défaut : results data/processed)
# Sortie : archives/luad_kras_AAAAMMJJ_HHMMSS.tar.gz (+ .sha256)

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_tools tar date sha256sum

ARCHIVE_DIR="${ARCHIVE_DIR:-$PROJECT_DIR/archives}"
cd "$PROJECT_DIR"

targets=("$@")
(( ${#targets[@]} > 0 )) || targets=(results data/processed)

existing=()

for t in "${targets[@]}"; do
    if [[ -e "$t" ]]; then
        existing+=("$t")
    else
        log WARN "ignoré (absent) : $t"
    fi
done

(( ${#existing[@]} > 0 )) || die "$EX_MISSING_INPUT" "rien à archiver."

STAMP="$(date +%Y%m%d_%H%M%S)"
OUT="$ARCHIVE_DIR/luad_kras_$STAMP.tar.gz"

mkdir -p "$ARCHIVE_DIR"
trap 'rm -f "$OUT.part"' EXIT

# Création temporaire de l'archive
tar -czf "$OUT.part" "${existing[@]}"

# Renommage après réussite
mv "$OUT.part" "$OUT"

# Vérification de l'archive
tar -tzf "$OUT" >/dev/null \
    || die "$EX_INTEGRITY" "archive créée mais illisible : $OUT"

# Création du checksum SHA-256
checksum_create "$OUT"

log "Archive créée : $OUT"
log "Checksum créé : $OUT.sha256"
log "Archivage terminé avec succès."
