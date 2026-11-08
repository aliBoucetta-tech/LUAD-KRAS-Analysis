#!/usr/bin/env bash
# scripts/01_download.sh : télécharge luad_tcga.tar.gz et vérifie son intégrité.
#   Codes de retour : 0 ok | 2 usage | 4 intégrité (checksum/taille/archive) | 5 réseau | 6 outil manquant
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

URL="${LUAD_URL:-https://datahub.assets.cbioportal.org/luad_tcga.tar.gz}"
ARCHIVE_NAME="luad_tcga.tar.gz"
RAW_DIR="$PROJECT_DIR/data/raw"
ARCHIVE="$RAW_DIR/$ARCHIVE_NAME"
PART="$ARCHIVE.part"
MIN_SIZE="${MIN_SIZE:-1000000}"   # < 1 Mo = pointeur Git LFS ou page d'erreur
FORCE=0
DOWNLOADED=0

usage() {
    cat <<USAGE
Usage : $(basename "$0") [-f] [-h]
  -f   forcer un nouveau téléchargement (supprime l'archive et son .sha256)
  -h   afficher cette aide
Variable optionnelle : LUAD_URL (remplace l'URL par défaut)
USAGE
}

while getopts ":fh" opt; do
    case "$opt" in
        f) FORCE=1 ;;
        h) usage; exit 0 ;;
        *) usage >&2; die "$EX_USAGE" "option inconnue : -${OPTARG}" ;;
    esac
done

require_tools curl tar wc
trap 'rm -f "$PART"' EXIT      # jamais de fichier partiel qui traîne
mkdir -p "$RAW_DIR"

if (( FORCE )); then
    log WARN "Option -f : suppression de l'archive existante."
    rm -f "$ARCHIVE" "$ARCHIVE.sha256"
fi

# 1. Téléchargement atomique (.part puis renommage)
if [[ -f "$ARCHIVE" ]]; then
    log "Archive déjà présente, pas de téléchargement."
else
    log "Téléchargement de $ARCHIVE_NAME ..."
    curl -fsSL --retry 3 --retry-delay 5 --connect-timeout 20 --max-time 3600 \
         "$URL" -o "$PART" \
        || die "$EX_NETWORK" "échec du téléchargement depuis $URL (réseau ou URL invalide)."
    mv "$PART" "$ARCHIVE"
    DOWNLOADED=1
fi

# 2. Si une somme de contrôle de référence existe, elle passe en premier
if [[ -f "$ARCHIVE.sha256" ]] && ! checksum_verify "$ARCHIVE"; then
    die "$EX_INTEGRITY" "somme de contrôle différente : fichier modifié ou corrompu. Relancez avec -f pour retélécharger."
fi

# 3. Validité de l'archive (taille, tar/gzip lisible)
validate_archive() {
    [[ -s "$ARCHIVE" ]] || { log ERROR "archive absente ou vide."; return 1; }
    local size; size="$(file_size "$ARCHIVE")"
    if (( size < MIN_SIZE )); then
        log ERROR "archive trop petite ($size octets < $MIN_SIZE) : pointeur Git LFS ou page d'erreur ?"
        return 1
    fi
    tar -tzf "$ARCHIVE" >/dev/null 2>&1 || { log ERROR "archive illisible (tar/gzip corrompu)."; return 1; }
}
if ! validate_archive; then
    (( DOWNLOADED )) && rm -f "$ARCHIVE"   # ne pas garder un mauvais fichier tout juste téléchargé
    die "$EX_INTEGRITY" "archive invalide. Relancez avec -f si le problème persiste."
fi

# 4. Première exécution : créer la somme de contrôle de référence
if [[ -f "$ARCHIVE.sha256" ]]; then
    log "Somme de contrôle vérifiée : OK."
else
    checksum_create "$ARCHIVE"
    log "Somme de contrôle créée (référence locale) : $(cut -d' ' -f1 "$ARCHIVE.sha256")"
fi

# 5. Données brutes en lecture seule
chmod a-w "$ARCHIVE" "$ARCHIVE.sha256"
log "Téléchargement et vérification terminés."
