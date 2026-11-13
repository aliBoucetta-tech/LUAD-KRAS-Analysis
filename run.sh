#!/usr/bin/env bash
# =============================================================================
# run.sh - LUAD x KRAS pipeline (TCGA lung adenocarcinoma, cBioPortal)
#
# Question : are KRAS mutations associated with smoking history in LUAD?
# Steps    : 1 download + checksum (scripts/01_download.sh)
#            2 extract the needed raw files from the archive
#            3 clean -> data/processed/patients_kras_smoking.tsv (02_clean.sh)
#            4 analyse + figures (scripts/analyze.py)
#            5 dated tar.gz archive + sha256 (scripts/03_archive.sh)
#
# Exit codes (shared with scripts/lib.sh):
#   0 success         1 generic error        2 usage error
#   3 missing file    4 integrity / checksum 5 network (download failed)
#   6 missing tool    130 interrupted (Ctrl-C / SIGTERM)
# =============================================================================
set -euo pipefail

# ----------------------------- CONFIG ----------------------------------------
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

export PROJECT_DIR="$ROOT"
export LOG_DIR="$ROOT/logs"
RUN_ID="$(date +%Y%m%d_%H%M%S)"
mkdir -p "$LOG_DIR"
export LOG_FILE="$LOG_DIR/run_${RUN_ID}.log"      # one timestamped log per run

if [[ ! -f scripts/lib.sh ]]; then
  echo "ERROR: scripts/lib.sh not found (run ./run.sh from the project)" >&2
  exit 3
fi
# shellcheck disable=SC1091
source scripts/lib.sh      # log(), die(), require_tools(), EX_* exit codes

EX_GENERIC=1
EX_INTR=130

ARCHIVE_RAW="data/raw/luad_tcga.tar.gz"           # produced by 01_download.sh
STUDY_DIR="data/raw/luad_tcga"                    # extracted raw files (read-only)
CLEAN_TSV="data/processed/patients_kras_smoking.tsv"
RESULTS_DIR="results"
if [[ -z "${PYTHON:-}" && -x "$ROOT/.venv/bin/python" ]]; then
  PYTHON="$ROOT/.venv/bin/python"        # venv local créé par python3 -m venv .venv
else
  PYTHON="${PYTHON:-python3}"
fi
PY_MODULES="${PY_MODULES:-numpy pandas scipy matplotlib seaborn}"
NEEDED_RAW=(data_mutations.txt data_clinical_patient.txt data_clinical_sample.txt)
EXPECTED_HEADER=$'patient_id\tsex\tsmoking_category\tpack_years\tage\tkras_status'

SKIP_DOWNLOAD=0
FORCE_DOWNLOAD=0
RUN_TESTS=0
DRY_RUN=0
KEEP_TMP=0
TMP_DIR=""

# ----------------------------- FUNCTIONS -------------------------------------
usage() {
  cat <<USAGE
Usage: ./run.sh [options]

Runs the full LUAD x KRAS pipeline: download and verify the data, extract it,
clean it, run the Python analysis and archive the results.

Options:
  -h   show this help and exit
  -s   skip the download step (use the archive already in data/raw/)
  -f   force a new download (deletes the archive and its checksum)
  -t   also run the automatic tests (pytest tests/) before the analysis
  -n   dry run: print the steps without executing them
  -k   keep the temporary directory (debugging)

Exit codes: 0 ok | 1 error | 2 usage | 3 missing file | 4 checksum/integrity |
            5 network | 6 missing tool | 130 interrupted
Log: logs/run_<timestamp>.log   (safe to re-run at any time)
USAGE
}

require_file() {              # require_file <path> : exit 3 if missing or empty
  [[ -f "$1" ]] || die "$EX_MISSING_INPUT" "Missing file: $1"
  [[ -s "$1" ]] || die "$EX_MISSING_INPUT" "File is empty: $1"
}

# run_step <label> <cmd...> : run a script that logs by itself (lib.sh log()).
run_step() {
  local label="$1"; shift
  log "STEP: $label"
  if (( DRY_RUN )); then log "[dry-run] $*"; return 0; fi
  local rc=0
  "$@" || rc=$?
  return "$rc"
}

# run_step_tee <label> <cmd...> : same, but copies stdout+stderr of scripts that
# only print (02_clean.sh, analyze.py) into the log file. Returns the command's
# own exit code (not tee's).
run_step_tee() {
  local label="$1"; shift
  log "STEP: $label"
  if (( DRY_RUN )); then log "[dry-run] $*"; return 0; fi
  local rc=0
  set +e
  "$@" 2>&1 | tee -a "$LOG_FILE"
  rc=${PIPESTATUS[0]}
  set -e
  return "$rc"
}

# extract_study : pull the 3 needed files out of the downloaded archive into
# data/raw/luad_tcga/ (read-only). Skipped if already up to date.
extract_study() {
  local f up=1
  for f in "${NEEDED_RAW[@]}"; do
    [[ -s "$STUDY_DIR/$f" && "$STUDY_DIR/$f" -nt "$ARCHIVE_RAW" ]] || up=0
  done
  if (( up )); then log "Raw files already extracted and up to date."; return 0; fi

  log "Extracting raw files from $ARCHIVE_RAW ..."
  mkdir -p "$TMP_DIR/extract" "$STUDY_DIR"
  tar -xzmf "$ARCHIVE_RAW" -C "$TMP_DIR/extract" --wildcards \
      '*data_mutations.txt' '*data_clinical_patient.txt' '*data_clinical_sample.txt' \
    || die "$EX_INTEGRITY" "Could not extract the expected files from $ARCHIVE_RAW (corrupted archive?)"
  local src
  for f in "${NEEDED_RAW[@]}"; do
    src="$(find "$TMP_DIR/extract" -type f -name "$f" -print -quit)"
    [[ -n "$src" ]] || die "$EX_MISSING_INPUT" "$f not found inside $ARCHIVE_RAW"
    rm -f "$STUDY_DIR/$f"
    mv -f "$src" "$STUDY_DIR/$f"
    chmod a-w "$STUDY_DIR/$f"                    # raw data read-only
  done
  log "Extracted: ${NEEDED_RAW[*]}"
}

cleanup() {                   # EXIT trap: removes only OUR temp dir
  local rc=$?
  if [[ -n "$TMP_DIR" && -d "$TMP_DIR" ]]; then
    if (( KEEP_TMP )); then log "Temporary directory kept: $TMP_DIR"
    else rm -rf -- "$TMP_DIR"; fi
  fi
  if (( rc == 0 )); then log "Pipeline finished OK (log: $LOG_FILE)"; fi
}
on_signal() { log WARN "Interrupted by $1: removing temporary files (finished results untouched)"; exit "$EX_INTR"; }
on_error()  { log ERROR "command failed at run.sh line $1 (exit code $2)"; }

trap cleanup EXIT
trap 'on_signal INT' INT
trap 'on_signal TERM' TERM
trap 'on_error $LINENO $?' ERR

# ----------------------------- ARGUMENTS -------------------------------------
while getopts ":hsftnk" opt; do
  case "$opt" in
    h) usage; exit 0 ;;
    s) SKIP_DOWNLOAD=1 ;;
    f) FORCE_DOWNLOAD=1 ;;
    t) RUN_TESTS=1 ;;
    n) DRY_RUN=1 ;;
    k) KEEP_TMP=1 ;;
    \?) usage >&2; die "$EX_USAGE" "Unknown option: -$OPTARG" ;;
  esac
done
shift $((OPTIND - 1))
[[ $# -eq 0 ]] || { usage >&2; die "$EX_USAGE" "Unexpected argument: $1"; }
(( ! (SKIP_DOWNLOAD && FORCE_DOWNLOAD) )) || { usage >&2; die "$EX_USAGE" "Options -s and -f cannot be combined"; }

# ----------------------------- CHECKS ----------------------------------------
log "Starting pipeline (run id $RUN_ID)"
chmod +x run.sh scripts/*.sh scripts/analyze.py 2>/dev/null || true
tools=(awk sed grep cut sort uniq tar mktemp find "$PYTHON")
(( SKIP_DOWNLOAD )) || tools+=(curl)
require_tools "${tools[@]}"

modules="$PY_MODULES"; (( RUN_TESTS )) && modules="$modules pytest"
# shellcheck disable=SC2086
"$PYTHON" -c "import $(echo $modules | sed 's/ /, /g')" 2>/dev/null \
  || die "$EX_MISSING_TOOL" "Missing Python module(s) among: $modules. Activate the environment: conda env create -f environment.yml && conda activate luad-kras (or pip install -r requirements.txt)"
for s in scripts/01_download.sh scripts/02_clean.sh scripts/03_archive.sh scripts/analyze.py; do
  require_file "$s"
done

mkdir -p data/raw data/processed "$RESULTS_DIR" archives
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/luad_kras.XXXXXX")"
log "Temporary directory: $TMP_DIR"

# ----------------------------- 1. DOWNLOAD + CHECKSUM ------------------------
if (( SKIP_DOWNLOAD )); then
  log "Download skipped (-s)"
else
  dl_args=(); (( FORCE_DOWNLOAD )) && dl_args+=(-f)
  rc=0
  run_step "download and checksum verification" bash scripts/01_download.sh ${dl_args[@]+"${dl_args[@]}"} || rc=$?
  case "$rc" in
    0) ;;
    "$EX_INTEGRITY") die "$EX_INTEGRITY" "Archive failed the integrity check (checksum, size or format). Re-run with -f to download it again" ;;
    "$EX_NETWORK")   die "$EX_NETWORK" "Download failed. Check your internet connection. If data/raw/luad_tcga.tar.gz is already there, re-run with -s" ;;
    "$EX_MISSING_TOOL") die "$EX_MISSING_TOOL" "A tool needed by the download step is missing (see message above)" ;;
    *) die "$rc" "Download step failed with code $rc" ;;
  esac
fi

# ----------------------------- 2. EXTRACTION ---------------------------------
if (( DRY_RUN )); then
  log "STEP: extraction of raw files"; log "[dry-run] tar -xzmf $ARCHIVE_RAW -> $STUDY_DIR"
else
  require_file "$ARCHIVE_RAW"
  log "STEP: extraction of raw files"
  extract_study
  for f in "${NEEDED_RAW[@]}"; do require_file "$STUDY_DIR/$f"; done
fi

# ----------------------------- 3. CLEANING -----------------------------------
# Output goes to the temp dir first; moved to data/processed only if valid.
rc=0
run_step_tee "cleaning (KRAS status + smoking category per patient)" \
  bash scripts/02_clean.sh -i "$STUDY_DIR" -o "$TMP_DIR/patients_kras_smoking.tsv" || rc=$?
(( rc == 0 )) || die "$rc" "Cleaning step failed with code $rc (3 = input file missing)"

if (( ! DRY_RUN )); then
  require_file "$TMP_DIR/patients_kras_smoking.tsv"
  header="$(head -n 1 "$TMP_DIR/patients_kras_smoking.tsv")"
  [[ "$header" == "$EXPECTED_HEADER" ]] || die "$EX_GENERIC" "Unexpected header in cleaned table: $header"
  (( $(wc -l < "$TMP_DIR/patients_kras_smoking.tsv") > 1 )) || die "$EX_GENERIC" "Cleaned table has no data rows"
  mv -f "$TMP_DIR/patients_kras_smoking.tsv" "$CLEAN_TSV"

  # 3-command pipe on the data: patients per smoking category / KRAS status
  log "Patients per smoking category / KRAS status (cleaned table):"
  tail -n +2 "$CLEAN_TSV" | cut -f3,6 | sort | uniq -c | sed 's/^ */  /' | tee -a "$LOG_FILE" >&2
fi

# ----------------------------- 4. TESTS (optional) + ANALYSIS ----------------
if (( RUN_TESTS )); then
  rc=0
  run_step_tee "automatic tests (pytest)" "$PYTHON" -m pytest -q tests || rc=$?
  (( rc == 0 )) || die "$EX_GENERIC" "Automatic tests failed (pytest code $rc)"
fi

rc=0
run_step_tee "statistical analysis and figures" \
  "$PYTHON" scripts/analyze.py --input "$CLEAN_TSV" --output "$TMP_DIR/results" || rc=$?
(( rc == 0 )) || die "$rc" "analyze.py failed with code $rc (3 = input missing, 1 = unusable input)"

if (( ! DRY_RUN )); then
  require_file "$TMP_DIR/results/statistical_results.json"
  require_file "$TMP_DIR/results/contingency_table.csv"
  compgen -G "$TMP_DIR/results/figures/*.png" >/dev/null \
    || die "$EX_GENERIC" "analyze.py produced no figure (.png)"
  # Analysis succeeded: only now replace the previous results
  mkdir -p "$RESULTS_DIR"
  cp -rf "$TMP_DIR/results/." "$RESULTS_DIR/"
  log "Results written to $RESULTS_DIR/"
fi

# ----------------------------- 5. ARCHIVE ------------------------------------
rc=0
run_step "dated archive of results + checksum" bash scripts/03_archive.sh || rc=$?
(( rc == 0 )) || die "$rc" "Archiving failed with code $rc"
