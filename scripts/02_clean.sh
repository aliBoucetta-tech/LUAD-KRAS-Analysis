#!/bin/bash
# 02_clean.sh : builds the table patients_kras_smoking.tsv
# Usage: ./02_clean.sh -i INPUT_FOLDER -o OUTPUT_FILE

usage="Usage: $0 -i INPUT_FOLDER -o OUTPUT_FILE"
input_dir=""
output_file=""

# Read the options: -i folder, -o file, -h help
while getopts "i:o:h" option; do
    case $option in
        i) input_dir=$OPTARG ;;
        o) output_file=$OPTARG ;;
        h) echo "$usage"; exit 0 ;;
        *) echo "$usage"; exit 2 ;;
    esac
done

# Both options are required
if [ -z "$input_dir" ] || [ -z "$output_file" ]; then
    echo "$usage"
    exit 2
fi

mutations="$input_dir/data_mutations.txt"
patients="$input_dir/data_clinical_patient.txt"
samples="$input_dir/data_clinical_sample.txt"

# Stop with code 3 if an input file is missing
for f in "$mutations" "$patients" "$samples"; do
    if [ ! -f "$f" ]; then
        echo "ERROR: missing input file: $f"
        exit 3
    fi
done

# Temporary folder for the in-between files
tmp=$(mktemp -d)

# STEP 1: the sequenced samples, then their patients
grep -v '^#' "$mutations" | tail -n +2 | cut -f17 | sort | uniq > "$tmp/seq_samples.txt"
grep -F -f "$tmp/seq_samples.txt" "$samples" | cut -f1 | sort | uniq > "$tmp/seq_patients.txt"

# STEP 2: the samples with a KRAS mutation, then their patients
awk -F'\t' '$1=="KRAS" {print $17}' "$mutations" | sort | uniq > "$tmp/kras_samples.txt"
grep -F -f "$tmp/kras_samples.txt" "$samples" | cut -f1 | sort | uniq > "$tmp/kras_patients.txt"

# STEP 3: the clinical columns (id, sex, smoking code, pack-years, age)
grep -v '^#' "$patients" | tail -n +2 | cut -f2,7,41,45,54 > "$tmp/clin_cols.tsv"

# STEP 4: keep only the sequenced patients
grep -F -f "$tmp/seq_patients.txt" "$tmp/clin_cols.tsv" > "$tmp/clin_seq.tsv"

# STEP 5: label each patient MUT (KRAS mutated) or WT (normal)
grep -F -f "$tmp/kras_patients.txt" "$tmp/clin_seq.tsv" | sed 's/$/\tMUT/' > "$tmp/mut.tsv"
grep -v -F -f "$tmp/kras_patients.txt" "$tmp/clin_seq.tsv" | sed 's/$/\tWT/' > "$tmp/wt.tsv"
cat "$tmp/mut.tsv" "$tmp/wt.tsv" | sort > "$tmp/labeled.tsv"

# STEP 6: smoking code to word (1 never, 2 current, 3-4-5 former, missing NA)
awk -F'\t' '$3==1' "$tmp/labeled.tsv" | sed 's/\t1\t/\tnever\t/' > "$tmp/s_never.tsv"
awk -F'\t' '$3==2' "$tmp/labeled.tsv" | sed 's/\t2\t/\tcurrent\t/' > "$tmp/s_current.tsv"
awk -F'\t' '$3==3 || $3==4 || $3==5' "$tmp/labeled.tsv" | sed 's/\t[345]\t/\tformer\t/' > "$tmp/s_former.tsv"
awk -F'\t' '$3=="[Not Available]"' "$tmp/labeled.tsv" | sed 's/\t\[Not Available\]\t/\tNA\t/' > "$tmp/s_na.tsv"
cat "$tmp/s_never.tsv" "$tmp/s_current.tsv" "$tmp/s_former.tsv" "$tmp/s_na.tsv" | sort > "$tmp/smoking.tsv"

# STEP 7: all other missing values become NA, and one "MALE" is fixed
sed 's/\[Not Available\]/NA/g' "$tmp/smoking.tsv" | sed 's/\[Not Applicable\]/NA/g' | sed 's/\tMALE\t/\tMale\t/' > "$tmp/final_rows.tsv"

# STEP 8: write the header, then the rows
echo -e "patient_id\tsex\tsmoking_category\tpack_years\tage\tkras_status" > "$output_file"
cat "$tmp/final_rows.tsv" >> "$output_file"

# Counts for the log
n_clinical=$(cat "$tmp/clin_cols.tsv" | wc -l)
n_kept=$(cat "$tmp/clin_seq.tsv" | wc -l)
n_dropped=$(( n_clinical - n_kept ))
n_mut=$(cat "$tmp/mut.tsv" | wc -l)
n_wt=$(cat "$tmp/wt.tsv" | wc -l)
n_final=$(cat "$tmp/final_rows.tsv" | wc -l)
na_smoking=$(cut -f3 "$tmp/final_rows.tsv" | grep -c '^NA$')
na_pack=$(cut -f4 "$tmp/final_rows.tsv" | grep -c '^NA$')
na_age=$(cut -f5 "$tmp/final_rows.tsv" | grep -c '^NA$')

# A patient must never be lost in the smoking step
if [ "$n_final" -ne "$n_kept" ]; then
    echo "ERROR: $n_kept patients before the smoking step, $n_final after"
    exit 1
fi

echo "$(date '+%Y-%m-%d %H:%M:%S') [02_clean] clinical patients: $n_clinical"
echo "$(date '+%Y-%m-%d %H:%M:%S') [02_clean] kept (sequenced): $n_kept"
echo "$(date '+%Y-%m-%d %H:%M:%S') [02_clean] dropped (not sequenced): $n_dropped"
echo "$(date '+%Y-%m-%d %H:%M:%S') [02_clean] KRAS mutated: $n_mut, normal: $n_wt"
echo "$(date '+%Y-%m-%d %H:%M:%S') [02_clean] NA values: smoking $na_smoking, pack-years $na_pack, age $na_age"
echo "$(date '+%Y-%m-%d %H:%M:%S') [02_clean] table written to $output_file"

rm -r "$tmp"
