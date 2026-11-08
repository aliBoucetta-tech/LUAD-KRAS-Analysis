# Sources des données

Ce fichier documente la provenance exacte des données, la date d'accès, les
fichiers utilisés et ceux volontairement ignorés. Il complète `NOTES.md`
(exploration et décisions) et `README.md` (mode d'emploi).

---

## 1. Jeu de données

| Champ | Valeur |
|---|---|
| Projet | **TCGA-LUAD** — *The Cancer Genome Atlas, Lung Adenocarcinoma* |
| Identifiant cBioPortal | `luad_tcga` |
| Type de données | données publiques de séquençage et cliniques (niveau patient) |
| Page du jeu de données | <https://www.cbioportal.org/datasets> |
| Page de l'étude | <https://www.cbioportal.org/study/summary?id=luad_tcga> |
| Archive téléchargée | <https://datahub.assets.cbioportal.org/luad_tcga.tar.gz> |
| Nom local | `data/raw/luad_tcga.tar.gz` |
| Taille | ≈ 152 Mo |
| Date d'accès | **2 novembre 2026** |
| Téléchargement | manuel (Personne 1) pour l'exploration, puis automatisé par `scripts/01_download.sh` avec la même URL |

L'archive contient l'ensemble des fichiers de l'étude (mutations, données
cliniques, nombre de copies, expression ARN, méthylation, RPPA, MutSig, listes
de cas…). Seuls trois fichiers sont utilisés par le pipeline ; ils sont extraits
dans `data/raw/luad_tcga/` et passés en lecture seule.

Le jeu de données n'a pas de numéro de version explicite. La référence est
constituée par la **date d'accès** et par la **somme SHA-256 locale** créée au
premier lancement (voir section 5).

---

## 2. Fichiers utilisés

| Fichier (dans l'archive) | Rôle | Colonnes utilisées (1 = première) |
|---|---|---|
| `data_mutations.txt` | une ligne = une mutation dans un échantillon ; sert à définir le statut KRAS | 1 `Hugo_Symbol`, 10 `Variant_Classification`, 17 `Tumor_Sample_Barcode` |
| `data_clinical_patient.txt` | caractéristiques des patients (tabagisme, paquets-années, âge, sexe) | 2 `PATIENT_ID`, 7 `SEX`, 23 `AJCC_PATHOLOGIC_TUMOR_STAGE`, 41 `TOBACCO_SMOKING_HISTORY_INDICATOR`, 45 `SMOKING_PACK_YEARS`, 54 `AGE` |
| `data_clinical_sample.txt` | lien entre code-barres d'échantillon et identifiant patient | 1 `PATIENT_ID`, 2 `SAMPLE_ID`, 17 `SAMPLE_TYPE`, 18 `SAMPLE_TYPE_ID` |

Un quatrième fichier, `case_lists/cases_sequenced.txt`, a servi de **contrôle
de cohérence** pendant l'exploration : il liste les échantillons séquencés. Le
pipeline ne l'extrait pas, car `02_clean.sh` déduit les échantillons séquencés
directement de `data_mutations.txt` (les deux listes coïncident : 230
échantillons).

### Définitions dérivées

- **Patient séquencé** : patient dont au moins un échantillon figure dans
  `data_mutations.txt`. Seuls ces patients peuvent être déclarés « KRAS muté »
  ou « KRAS normal » ; les autres sont *inconnus* et sont exclus.
- **KRAS muté (`MUT`)** : au moins une ligne `Hugo_Symbol == KRAS` avec une
  mutation non silencieuse pour l'un des échantillons du patient.
  Un patient avec plusieurs échantillons ou plusieurs mutations ne compte
  qu'une fois.
- **Tabagisme** (colonne 41) : `1` = jamais fumé ; `2` = fumeur actuel ;
  `3`, `4`, `5` = ancien fumeur ; `[Not Available]` = manquant.
- **Paquets-années** (colonne 45) : valeur numérique, `[Not Available]` ou
  `[Not Applicable]` selon le fichier ; converti en `NA` dans la table finale.

---

## 3. Fichiers volontairement ignorés

Tous les autres fichiers de l'archive sont hors du périmètre de la question :

- nombre de copies (CNA) et segmentation ;
- expression ARN (mRNA, miRNA) et méthylation ;
- données protéiques RPPA ;
- résultats MutSig et autres analyses précalculées ;
- colonnes KRAS du fichier clinique (34 à 38) : `KRAS_MUTATION` n'est renseigné
  que pour 62 patients sur 522, alors que `data_mutations.txt` couvre les 230
  patients séquencés avec une méthode homogène ;
- années de début et d'arrêt du tabagisme (colonnes 43 et 44) : les
  paquets-années résument déjà l'exposition.

---

## 4. Effectifs de contrôle

Ces chiffres proviennent de l'exploration décrite dans `NOTES.md` et servent à
vérifier que le bon fichier a été téléchargé :

| Contrôle | Valeur |
|---|---|
| Patients dans `data_clinical_patient.txt` | 522 (527 lignes : 4 commentaires + en-tête + 522) |
| Échantillons dans `data_clinical_sample.txt` | 586 (584 tumeurs primaires, 2 récidives) |
| Patients avec au moins un échantillon séquencé | 230 |
| Lignes de mutations (tous gènes) | 72 542 |
| Lignes de mutations KRAS | 76, dans 75 échantillons |
| Patients KRAS mutés | 75 |
| Patients KRAS non mutés (parmi les 230) | 155 |
| Patients avec tabagisme exploitable | 221 |

---

## 5. Intégrité et somme de contrôle

Aucune somme de contrôle officielle n'est fournie avec cette archive.
Le pipeline applique donc deux contrôles :

1. **Taille et format** : rejet des fichiers de moins de 1 Mo (page d'erreur,
   pointeur Git LFS) et vérification que l'archive `tar.gz` est lisible.
2. **SHA-256 locale** : `scripts/01_download.sh` crée
   `data/raw/luad_tcga.tar.gz.sha256` au premier lancement, puis la vérifie à
   chaque lancement. Une différence renvoie le code 4. La commande
   `./scripts/01_download.sh -f` force un nouveau téléchargement.

Cette somme de contrôle est une **référence locale** : elle détecte une
corruption ou une modification après le premier téléchargement, mais ne prouve
pas l'authenticité de la source. Pour une vérification indépendante, comparer
la taille et les effectifs de la section 4, ou télécharger à nouveau l'archive
depuis l'URL officielle.

---

## 6. Références

- Cancer Genome Atlas Research Network. *Comprehensive molecular profiling of
  lung adenocarcinoma.* **Nature** 511, 543–550 (2014).
  <https://doi.org/10.1038/nature13385>
- Cerami E, Gao J, Dogrusoz U, *et al.* *The cBio cancer genomics portal: an
  open platform for exploring multidimensional cancer genomics data.*
  **Cancer Discovery** 2(5), 401–404 (2012).
  <https://doi.org/10.1158/2159-8290.CD-12-0095>
- Gao J, Aksoy BA, Dogrusoz U, *et al.* *Integrative analysis of complex cancer
  genomics and clinical profiles using the cBioPortal.* **Science Signaling**
  6(269), pl1 (2013). <https://doi.org/10.1126/scisignal.2004088>
- cBioPortal for Cancer Genomics — <https://www.cbioportal.org>

---

## 7. Éthique et licence

Les données TCGA sont des données publiques de recherche, diffusées par le
National Cancer Institute et cBioPortal. Le dépôt ne contient que des
identifiants TCGA (code-barres `TCGA-XX-XXXX`), sans nom, date de naissance ni
autre donnée personnelle identifiante. Aucune donnée brute n'est versionnée
dans Git : elle est téléchargée localement par `01_download.sh`.

---

## 8. Reproduire le téléchargement

```bash
# Depuis la racine du dépôt
bash scripts/01_download.sh          # télécharge et vérifie
bash scripts/01_download.sh -f       # force un nouveau téléchargement
bash scripts/01_download.sh -h       # aide
```

L'URL peut être remplacée sans modifier le script :

```bash
LUAD_URL="https://exemple.org/luad_tcga.tar.gz" bash scripts/01_download.sh
```
