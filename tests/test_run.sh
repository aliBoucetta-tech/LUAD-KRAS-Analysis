#!/usr/bin/env bash
# tests/test_run.sh - robustness tests for run.sh (Person 3)
# Runs the REAL scripts (01_download, 02_clean, analyze.py, 03_archive) in a
# throw-away copy of the repo, on a tiny FAKE study served through file://, so
# it needs neither internet nor the 152 MB dataset.
# Usage (from the repo root, with the conda env / requirements installed):
#   bash tests/test_run.sh
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SANDBOX="$(mktemp -d)"
trap 'chmod -R u+w "$SANDBOX" 2>/dev/null; [[ -n "${KEEPSB:-}" ]] || rm -rf "$SANDBOX"; [[ -z "${KEEPSB:-}" ]] || echo "sandbox: $SANDBOX"' EXIT
PASS=0; FAIL=0
check() { if eval "$2"; then echo "  PASS  $1"; PASS=$((PASS+1)); else echo "  FAIL  $1"; FAIL=$((FAIL+1)); fi; }

# ---- sandbox copy of the project (code only, no data/results) ----
mkdir -p "$SANDBOX/p" "$SANDBOX/tmp" "$SANDBOX/fake/luad_tcga"
cp -r "$REPO/run.sh" "$REPO/scripts" "$REPO/tests" "$SANDBOX/p/"
cd "$SANDBOX/p" && mkdir -p data/raw data/processed results logs archives

# ---- tiny fake study with the same layout as luad_tcga ----
python3 - "$SANDBOX/fake/luad_tcga" <<'PY'
import sys, os
d = sys.argv[1]
pat_hdr = ["c%d" % i for i in range(1, 55)]
pat = ["#c1", "#c2", "#c3", "#c4", "\t".join(pat_hdr)]
samp = ["#s1", "#s2", "#s3", "#s4", "PATIENT_ID\tSAMPLE_ID"]
mut = ["Hugo_Symbol\t" + "\t".join("m%d" % i for i in range(2, 18))]
for i in range(1, 41):
    pid = "TCGA-AA-%04d" % i
    code = ["1", "2", "3", "4", "5"][i % 5] if i % 13 else "[Not Available]"
    row = ["x"] * 54
    row[1] = pid; row[6] = "Male" if i % 2 else "Female"; row[40] = code
    row[44] = "[Not Applicable]" if code == "1" else str(10 + i)
    row[53] = str(40 + i)
    pat.append("\t".join(row))
    samp.append("%s\t%s-01" % (pid, pid))
    for gene in (["TP53", "KRAS"] if i % 3 == 0 else ["TP53"]):
        r = [gene] + ["y"] * 15 + ["%s-01" % pid]
        mut.append("\t".join(r))
for name, lines in (("data_clinical_patient.txt", pat), ("data_clinical_sample.txt", samp), ("data_mutations.txt", mut)):
    open(os.path.join(d, name), "w").write("\n".join(lines) + "\n")
PY
( cd "$SANDBOX/fake" && tar -czf luad_tcga.tar.gz luad_tcga )

export TMPDIR="$SANDBOX/tmp" MIN_SIZE=100 LUAD_URL="file://$SANDBOX/fake/luad_tcga.tar.gz"
latest_log() { ls -t logs/run_*.log | head -n 1; }

echo "== 1. Help and options"
out=$(./run.sh -h 2>&1); rc=$?
check "-h exits 0 and prints usage" "[[ $rc -eq 0 && \"$out\" == *Usage* ]]"
out=$(./run.sh -z 2>&1); rc=$?
check "unknown option -> code 2 + clear message" "[[ $rc -eq 2 && \"$out\" == *'Unknown option: -z'* ]]"
out=$(./run.sh -s -f 2>&1); rc=$?
check "-s with -f -> code 2" "[[ $rc -eq 2 ]]"
out=$(./run.sh -n 2>&1); rc=$?
check "-n (dry run) exits 0 and downloads nothing" "[[ $rc -eq 0 && ! -e data/raw/luad_tcga.tar.gz ]]"

echo "== 2. Full run on the fake study"
./run.sh >/dev/null 2>&1; rc=$?
check "full run exits 0" "[[ $rc -eq 0 ]]"
check "archive downloaded + .sha256 reference created" "[[ -s data/raw/luad_tcga.tar.gz && -s data/raw/luad_tcga.tar.gz.sha256 ]]"
check "raw data is read-only" "[[ \"\$(stat -c %A data/raw/luad_tcga/data_mutations.txt data/raw/luad_tcga.tar.gz)\" != *w* ]]"
check "cleaned table: header + 40 patients" "[[ \$(wc -l < data/processed/patients_kras_smoking.tsv) -eq 41 ]]"
check "JSON + CSV + 3 figures produced" "[[ -s results/statistical_results.json && -s results/contingency_table.csv && \$(ls results/figures/*.png | wc -l) -eq 3 ]]"
check "dated archive + valid .sha256" "ls archives/luad_kras_*.tar.gz >/dev/null 2>&1 && (cd archives && sha256sum -c \$(ls *.sha256 | head -n 1) >/dev/null)"
check "timestamped log in logs/ with step lines" "grep -q 'STEP: statistical analysis' \$(latest_log)"
check "temp dir removed after the run" "[[ -z \"\$(ls $TMPDIR | grep luad_kras || true)\" ]]"
sleep 1
./run.sh >/dev/null 2>&1; rc=$?
check "re-run without manual cleanup exits 0" "[[ $rc -eq 0 ]]"
check "two archives now exist" "[[ \$(ls archives/*.tar.gz | wc -l) -eq 2 ]]"
sleep 1
./run.sh -s -t >/dev/null 2>&1; rc=$?
check "-s -t (skip download, run pytest) exits 0" "[[ $rc -eq 0 ]]"

echo "== 3. Missing files"
before=$(sha256sum results/statistical_results.json)
mv data/raw/luad_tcga.tar.gz /tmp/_hold_$$.tgz
out=$(./run.sh -s 2>&1); rc=$?
check "missing archive -> code 3 + clear message" "[[ $rc -eq 3 && \"$out\" == *'Missing file: data/raw/luad_tcga.tar.gz'* ]]"
mv /tmp/_hold_$$.tgz data/raw/luad_tcga.tar.gz
mv scripts/analyze.py /tmp/_hold_an_$$
out=$(./run.sh -s 2>&1); rc=$?
check "missing script -> code 3" "[[ $rc -eq 3 ]]"
mv /tmp/_hold_an_$$ scripts/analyze.py
check "finished results untouched" "[[ \"\$(sha256sum results/statistical_results.json)\" == \"$before\" ]]"

echo "== 4. No internet / checksum error (previous results must survive)"
out=$(LUAD_URL=file:///nonexistent.tgz ./run.sh -f 2>&1); rc=$?
check "download failure -> code 5 + advice about -s" "[[ $rc -eq 5 && \"$out\" == *'internet connection'* ]]"
./run.sh >/dev/null 2>&1   # restores the archive
chmod u+w data/raw/luad_tcga.tar.gz; echo "tampered" >> data/raw/luad_tcga.tar.gz; chmod a-w data/raw/luad_tcga.tar.gz
out=$(./run.sh 2>&1); rc=$?
check "tampered archive -> code 4 (checksum)" "[[ $rc -eq 4 ]]"
check "finished results untouched" "[[ \"\$(sha256sum results/statistical_results.json)\" == \"$before\" ]]"
check "temp dir removed after errors" "[[ -z \"\$(ls $TMPDIR | grep luad_kras || true)\" ]]"
./run.sh -f >/dev/null 2>&1; rc=$?
check "-f repairs the tampered archive (exit 0)" "[[ $rc -eq 0 ]]"
before=$(sha256sum results/statistical_results.json)

echo "== 5. Ctrl-C (SIGINT) during the analysis step"
cat > "$SANDBOX/slowpy" <<'SH'
#!/usr/bin/env bash
[[ "$*" == *analyze.py* ]] && sleep 3
exec python3 "$@"
SH
chmod +x "$SANDBOX/slowpy"
PYTHON="$SANDBOX/slowpy" timeout --preserve-status -s INT 1.5 ./run.sh -s >/dev/null 2>&1; rc=$?
check "interrupted run exits 130" "[[ $rc -eq 130 ]]"
check "temp dir removed on interruption" "[[ -z \"\$(ls $TMPDIR | grep luad_kras || true)\" ]]"
check "finished results untouched" "[[ \"\$(sha256sum results/statistical_results.json)\" == \"$before\" ]]"
./run.sh -s >/dev/null 2>&1; rc=$?
check "run after interruption works without cleanup" "[[ $rc -eq 0 ]]"

echo; echo "Result: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]

