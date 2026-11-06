#!/usr/bin/env bash
# scripts/lib.sh : fonctions communes du projet LUAD x KRAS.
# À SOURCER (pas à exécuter) :  source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    echo "lib.sh se source, il ne s'exécute pas." >&2
    exit 2
fi
# Évite un double chargement (run.sh puis un script appelé)
[[ -n "${_LUAD_LIB_LOADED:-}" ]] && return 0
_LUAD_LIB_LOADED=1

PROJECT_DIR="${PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
LOG_DIR="${LOG_DIR:-$PROJECT_DIR/logs}"
LOG_FILE="${LOG_FILE:-$LOG_DIR/pipeline.log}"

# Codes de retour communs à tout le projet
EX_USAGE=2          # option inconnue / mauvais appel
EX_MISSING_INPUT=3  # fichier d'entrée manquant
EX_INTEGRITY=4      # checksum différent, archive trop petite ou corrompue
EX_NETWORK=5        # téléchargement impossible
EX_MISSING_TOOL=6   # commande requise absente

# log [INFO|WARN|ERROR] message...   -> écran (stderr) + logs/pipeline.log
log() {
    local level="INFO"
    case "${1:-}" in INFO|WARN|ERROR) level="$1"; shift ;; esac
    local line
    line="$(date '+%Y-%m-%d %H:%M:%S') [$level] [$(basename "$0")] $*"
    echo "$line" >&2
    { mkdir -p "$LOG_DIR" && echo "$line" >> "$LOG_FILE"; } 2>/dev/null || true
}

# die CODE message...   -> journalise en ERROR puis quitte avec CODE
die() {
    local code="$1"; shift
    log ERROR "$*"
    exit "$code"
}

# require_tools cmd1 cmd2 ...   -> quitte (code 6) si une commande manque
require_tools() {
    local t missing=()
    for t in "$@"; do
        command -v "$t" >/dev/null 2>&1 || missing+=("$t")
    done
    if (( ${#missing[@]} > 0 )); then
        die "$EX_MISSING_TOOL" "outils manquants : ${missing[*]}"
    fi
}

# Taille en octets (portable Linux/macOS)
file_size() { wc -c < "$1" | tr -d ' '; }

# sha256 portable (sha256sum sous Linux, shasum sous macOS)
_sha() {
    if command -v sha256sum >/dev/null 2>&1; then sha256sum "$@"; else shasum -a 256 "$@"; fi
}

# checksum_create FICHIER : écrit FICHIER.sha256 avec un chemin RELATIF
checksum_create() {
    ( cd "$(dirname "$1")" && _sha "$(basename "$1")" > "$(basename "$1").sha256" )
}

# checksum_verify FICHIER : code 0 si identique, 1 sinon
checksum_verify() {
    ( cd "$(dirname "$1")" && _sha -c "$(basename "$1").sha256" >/dev/null 2>&1 )
}
