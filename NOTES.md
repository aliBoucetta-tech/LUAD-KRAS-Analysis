# Exploration notes

## Download
- Study: luad_tcga (TCGA Lung Adenocarcinoma), downloaded from https://www.cbioportal.org/datasets
- Archive: luad_tcga.tar.gz, 152 MB
- Download date: 2026-11-02
## Files used
- data_mutations.txt: KRAS mutations
- data_clinical_patient.txt: smoking, pack-years, age, sex
- data_clinical_sample.txt: link between samples and patients
- case_lists/cases_sequenced.txt: which samples were sequenced
- Ignored: copy number, mRNA, methylation, RPPA, MutSig and all other files (not related to the question)
## data_clinical_patient.txt
- 527 lines: 4 comment lines (start with #), 1 header line, 522 patients
- Missing values are written [Not Available] or [Not Applicable]
- Columns kept: 2 PATIENT_ID, 7 SEX, 23 AJCC_PATHOLOGIC_TUMOR_STAGE (optional),
  41 TOBACCO_SMOKING_HISTORY_INDICATOR, 45 SMOKING_PACK_YEARS, 54 AGE
- Columns 43 and 44 (smoking year started and stopped) are dropped: pack-years already covers them
- Columns 34 to 38 (KRAS fields in the clinical file) are not used as KRAS status
## Smoking codes (column 41)
Meaning confirmed from the TCGA enrollment form :
- 1 = lifelong non-smoker: 75 patients
- 2 = current smoker: 122
- 3 = reformed smoker, quit more than 15 years ago: 137
- 4 = reformed smoker, quit 15 years ago or less: 170
- 5 = reformed smoker, duration not specified: 4
- [Not Available] = missing: 14
## Pack-years (column 45)
- All 75 never-smokers have no pack-years (not a smoker)
- Among 433 ever-smokers: 356 have a value, 77 are missing
- Values range from 0.15 to 154, no text or negative values
## Decisions
- never = code 1
- ever_smoker = codes 2, 3, 4, 5
- current = code 2
-  former = codes 3, 4, 5
- [Not Available] smoking status = excluded from analysis.
- Pack-years comparison:  Includes only ever-smokers with available values (356 patients)
## data_clinical_sample.txt
 - Sample file: 586 samples (584 primary tumor, 2 recurrence), 584 distinct patients. 582 patients have 1 sample and 2 patients have 2.
 - Columns kept: 1 PATIENT_ID, 2 SAMPLE_ID, 17 SAMPLE_TYPE, 18 SAMPLE_TYPE_ID.
 - 62 patients in the sample file have no clinical data and are excluded (no smoking information).
 - Still to decide: what to do with the 2 patients with 2 samples (probably keep the primary tumor only). We’ll check this when we look at the mutations.
## data_mutation.txt
- One line = one mutation found in one tumor sample. 72,542 lines, for all genes.
- It covers 230 samples. These are the same 230 as in case_lists/cases_sequenced.txt
  (the samples whose DNA was read).
- Columns used: 1 Hugo_Symbol (gene name), 10 Variant_Classification (type of mutation),
  17 Tumor_Sample_Barcode (which sample).
- There is no patient ID column. The link to the patient goes through the sample file.
- KRAS: 76 lines, in 75 different samples (one sample has 2 KRAS mutations).
  Types: 75 Missense_Mutation, 1 Nonsense_Mutation. Both change the protein.
  No Silent mutation appears for KRAS.
- All 75 mutated samples exist in the sample file.
## Who we study
- Only the 230 sequenced samples can be called "KRAS mutated" or "KRAS normal".
  A patient who was not sequenced is unknown, not normal.
- Among the 230: about 75 have a KRAS mutation (about 1 in 3), the others have normal KRAS.
- Patients without a smoking category are removed. The final group will be a bit smaller than 230.

## Decisions
- A patient is KRAS mutated if at least one of their samples has at least one KRAS mutation line.
- A patient with 2 samples or 2 KRAS mutations counts once.
- We keep only two things from the mutation file: the sample and the type of mutation.
  We do not study which exact KRAS change it is (we keep the question simple).

## Changes for the team
- The study group is about 230 patients, not 522.
- The final table does not have kras_variant and kras_codon any more.

## Final table (patients_kras_smoking.tsv)
- 230 rows (one per sequenced patient) plus a header.
- Columns: patient_id, sex, smoking_category, pack_years, age, kras_status
- smoking_category: never, current, former or NA. kras_status: MUT or WT.
- Missing values are written NA. Sex is written Male or Female (one "MALE" was fixed).
- Missing in the 230: 9 smoking category, 16 age, 72 pack-years
  (32 of them are never-smokers, where it does not apply).

## Counts among the 230 sequenced patients
| | KRAS mutated | KRAS normal |
|---|---|---|
| current | 17 | 28 |
| former | 50 | 94 |
| never | 5 | 27 |
| smoking unknown (NA) | 3 | 6 |
- Total: 75 mutated, 155 normal.
- Main test: 221 patients with a known smoking category
  (189 ever-smokers: 67 mutated and 122 normal; 32 never-smokers: 5 mutated and 27 normal).
- Never-smokers are few (32), which is a limit.
- All 230 sequenced patients have a row in the clinical file.
- Patient IDs in the clinical file: no duplicates, all in the format TCGA-XX-XXXX.

## Why the KRAS status comes from the mutation file
- The clinical file has KRAS columns (34 to 38), but KRAS_MUTATION is filled in for only
  62 of 522 patients (23 YES, 39 NO). The mutation file covers 230 patients with one method.

