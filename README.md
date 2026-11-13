# LUAD × KRAS — mutations KRAS et tabagisme dans l'adénocarcinome pulmonaire
> ⚡ **Exécution rapide** : voir la section **13. Exécution rapide** (cas Windows et cas Linux Ubuntu) à la fin du document.

Pipeline reproductible pour répondre à une question simple sur le jeu de données
public **TCGA-LUAD** (cBioPortal, étude `luad_tcga`) :

> Chez les patients atteints d'un adénocarcinome pulmonaire (LUAD) et séquencés,
> les mutations du gène **KRAS** sont-elles associées à l'**historique tabagique** ?

Le dépôt contient le téléchargement et la vérification des données, le nettoyage
en shell, l'analyse statistique en Python, les figures, les tests et l'archivage
daté des résultats. Tout se relance avec une seule commande : `./run.sh`.

Version fonctionnelle — 13 novembre 2026.

---

## 1. Installation et première exécution

Cette section est écrite pour une personne qui reçoit le projet et qui ne l'a
jamais lancé. Suivre les étapes dans l'ordre, sans sauter la vérification
finale. En cas de message d'erreur, voir la section **12. Dépannage**.

### 1.0 Choisir son système

| Système | Support | Section à suivre |
|---|---|---|
| Linux (Ubuntu, Debian, Fedora…) | ✅ testé | 1.2 |
| Windows 10/11 | ✅ via **WSL2** | 1.1 puis 1.2 |
| macOS | ⚠️ expérimental | 1.3 |
| Windows sans WSL (`cmd`, PowerShell) | ❌ non supporté | installer WSL2 (1.1) |

Le projet est un enchaînement de scripts **Bash** : il ne fonctionne pas dans
l'invite de commandes Windows ni dans PowerShell. Sous Windows, il faut passer
par WSL2 (un vrai Linux intégré à Windows).

### 1.1 Windows 10/11 : installer WSL2 et Ubuntu

Ouvrir **PowerShell en administrateur**, puis :

```powershell
wsl --install -d Ubuntu
```

Redémarrer l'ordinateur si demandé, lancer **Ubuntu** depuis le menu Démarrer,
puis créer un nom d'utilisateur et un mot de passe Linux.

> Toutes les commandes suivantes se font **dans le terminal Ubuntu**, pas dans
> PowerShell. Pour éviter les problèmes de lenteur et de permissions, placer le
> projet dans le dossier personnel Linux (`~/`) et non dans `/mnt/c/...`.

Mettre à jour Ubuntu et installer les outils de base :

```bash
sudo apt update
sudo apt install -y git curl tar gzip
```

Vérifier :

```bash
git --version
curl --version
bash --version
```

Puis passer à la section **1.4**.

### 1.2 Linux

Installer les outils de base selon la distribution.

**Ubuntu / Debian :**

```bash
sudo apt update
sudo apt install -y git curl tar gzip
```

**Fedora :**

```bash
sudo dnf install -y git curl tar gzip
```

Vérifier que Bash est en version 4 ou plus :

```bash
bash --version
```

### 1.3 macOS (support expérimental)

macOS fournit Bash 3.2 et des outils BSD, alors que le pipeline utilise
quelques commandes GNU. Le projet n'est pas testé automatiquement sur macOS :
en cas de blocage, préférer Linux, WSL2 ou une machine virtuelle Linux.

Pour essayer sur macOS, installer Homebrew (https://brew.sh) puis :

```bash
brew install bash gnu-tar coreutils findutils
```

Créer un dossier de liens vers les versions GNU et l'ajouter au `PATH` :

```bash
mkdir -p "$HOME/.luad-gnu"
ln -sf "$(brew --prefix gnu-tar)/libexec/gnubin/tar"      "$HOME/.luad-gnu/tar"
ln -sf "$(brew --prefix coreutils)/libexec/gnubin/sha256sum" "$HOME/.luad-gnu/sha256sum"
ln -sf "$(brew --prefix coreutils)/libexec/gnubin/stat"      "$HOME/.luad-gnu/stat"
ln -sf "$(brew --prefix coreutils)/libexec/gnubin/timeout"   "$HOME/.luad-gnu/timeout"
ln -sf "$(brew --prefix findutils)/libexec/gnubin/find"      "$HOME/.luad-gnu/find"
export PATH="$HOME/.luad-gnu:$(brew --prefix)/bin:$PATH"
```

Pour conserver ce `PATH`, ajouter la dernière ligne `export PATH=...` à la fin
de `~/.zshrc`, puis rouvrir le terminal.

### 1.4 Récupérer le projet

Deux possibilités.

**A. Depuis GitHub** (si le dépôt est privé, demander à être ajouté comme
collaborateur, sinon le `git clone` échouera) :

```bash
git clone https://github.com/aliBoucetta-tech/LUAD-KRAS-Analysis.git
cd LUAD-KRAS-Analysis
```

**B. Depuis une archive ZIP ou un dossier copié :**

```bash
unzip LUAD-KRAS-Analysis.zip
cd LUAD-KRAS-Analysis
```

> Ne pas copier le dossier `.venv/` d'un autre ordinateur, ni `data/raw/` :
> ils sont spécifiques à la machine. L'environnement Python sera recréé à
> l'étape 1.5 et les données brutes seront téléchargées au premier lancement.

### 1.5 Installer Python 3.11 et les bibliothèques

Il faut **Python 3.11**. Les versions épinglées ne fonctionnent pas avec
Python 3.13 ou 3.14.

#### Méthode recommandée : conda / Miniconda

Si `conda` est déjà installé :

```bash
conda env create -f environment.yml
conda activate luad-kras
```

Si `conda` n'est pas installé (Linux ou WSL), installer Miniconda :

```bash
curl -fsSL -o /tmp/miniconda.sh \
  https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh
bash /tmp/miniconda.sh -b -p "$HOME/miniconda3"
eval "$("$HOME/miniconda3/bin/conda" shell.bash hook)"
conda init bash
```

Fermer puis rouvrir le terminal, et reprendre à `conda env create ...`.

> Sur macOS, télécharger l'installateur Miniconda adapté (Intel ou Apple
> Silicon) depuis https://docs.conda.io/en/latest/miniconda.html.

#### Méthode de secours : venv + pip

À utiliser si conda n'est pas disponible. Sous Ubuntu, si `python3.11` est
disponible dans les dépôts :

```bash
sudo apt install -y python3.11 python3.11-venv
```

Si ce paquet n'existe pas pour ta version d'Ubuntu, utiliser conda (méthode
recommandée) plutôt que d'installer Python 3.11 depuis une source externe.

Puis :

```bash
python3.11 -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip
pip install -r requirements.txt
```

L'environnement conda (ou le venv) doit être activé **avant** `./run.sh` : le
script vérifie la présence des modules Python et s'arrête avec le code 6 sinon.

### 1.6 Vérifier l'installation avant de lancer le pipeline

```bash
python --version
# doit afficher : Python 3.11.x

python -c "import numpy, pandas, scipy, matplotlib, seaborn; print('modules OK')"
# doit afficher : modules OK
```

Puis lancer les tests, qui utilisent de fausses données et **ne nécessitent
pas internet** :

```bash
bash tests/test_run.sh
python -m pytest -q tests/test_analyze.py
```

Résultat attendu :

```text
Result: 27 passed, 0 failed
5 passed
```

Si ces deux commandes passent, l'installation est correcte et le pipeline
complet peut être lancé (section 2).

---

## 2. Mode d'emploi

### 2.1 Premier lancement (pas à pas)

1. Se placer dans le dossier du projet et activer l'environnement Python :

```bash
cd LUAD-KRAS-Analysis
conda activate luad-kras        # ou, avec la méthode venv : source .venv/bin/activate
python --version                # doit afficher Python 3.11.x
```

2. Lancer le pipeline :

```bash
chmod +x run.sh scripts/*.sh scripts/analyze.py   # seulement si "Permission denied"
./run.sh
```

Au premier lancement, le script télécharge l'archive `luad_tcga.tar.gz` (152 Mo)
depuis cBioPortal, en crée la somme de contrôle, l'extrait, nettoie les données,
lance l'analyse, produit les figures puis archive les résultats. Compter
quelques minutes pour le téléchargement (selon la connexion), puis environ
30 secondes pour le reste. Les lancements suivants réutilisent l'archive locale.

Le script doit se terminer par :

```text
[INFO] [run.sh] Pipeline finished OK (log: logs/run_....log)
```

et le code de retour doit être **0**.

3. Vérifier les fichiers produits :

```bash
ls results
# contingency_table.csv  figures  statistical_results.json

ls results/figures
# barplot_kras_smoking.png  boxplot_pack_years.png  hist_pack_years.png

wc -l data/processed/patients_kras_smoking.tsv
# 231  (1 en-tête + 230 patients)

ls archives
# une archive luad_kras_AAAAMMJJ_HHMMSS.tar.gz et son .sha256
```

4. Consulter les résultats :

- `results/statistical_results.json` : effectifs, tableau 2×2, Fisher, Mann-Whitney ;
- `results/contingency_table.csv` : tableau de contingence ;
- `results/figures/*.png` : les trois figures ;
- `logs/run_AAAAMMJJ_HHMMSS.log` : journal complet de l'exécution.

Sous WSL, pour ouvrir le dossier dans l'Explorateur Windows :

```bash
explorer.exe .
```

5. Relancer plus tard :

```bash
./run.sh -s        # réutilise l'archive déjà téléchargée (hors ligne possible)
./run.sh -s -t     # relance + tests automatiques
./run.sh -f        # force un nouveau téléchargement
```

> Les données brutes ne sont pas versionnées (voir `.gitignore`) : le premier
> lancement nécessite une connexion internet. Utiliser `-s` pour travailler
> hors ligne si `data/raw/luad_tcga.tar.gz` est déjà présent.

### 2.2 Vérifier que le résultat est conforme

Après un lancement réussi, l'analyse doit afficher :

```text
Tableau de contingence (Fumeur / Jamais fumeur x MUT / WT) :
kras_status    MUT   WT
smoking_group
Smoker          67  122
Never smoker     5   27
Patients analysés : 221 (exclus, tabagisme manquant : 9)
Fisher : OR = 2.97 [IC95 % 1.09 - 8.06], p = 0.0263
Mann-Whitney (pack-years) : p = 0.7579
```

La table nettoyée doit contenir **231 lignes** (en-tête compris) et les
résultats doivent correspondre à la section **5. Résultats attendus**. Un écart
significatif indique soit une erreur d'environnement, soit une donnée source
différente (voir section 12).

### 2.3 Options de `run.sh`

| Option | Effet |
|---|---|
| `-h` | affiche l'aide et quitte (code 0) |
| `-s` | saute le téléchargement (utilise l'archive déjà présente) |
| `-f` | force un nouveau téléchargement (supprime l'archive et son `.sha256`) |
| `-t` | lance aussi les tests `pytest` avant l'analyse |
| `-n` | simulation (*dry run*) : affiche les étapes sans rien exécuter |
| `-k` | conserve le dossier temporaire (débogage) |

`-s` et `-f` sont incompatibles. Une option inconnue ou un argument inattendu
renvoie le code 2 et affiche l'aide.

### 2.4 Codes de retour

| Code | Signification |
|---|---|
| 0 | succès |
| 1 | erreur générique (données inutilisables, test échoué…) |
| 2 | erreur d'usage (option inconnue, mauvais appel) |
| 3 | fichier d'entrée manquant ou vide |
| 4 | intégrité : somme de contrôle différente, archive trop petite ou corrompue |
| 5 | téléchargement impossible (réseau, URL) |
| 6 | outil ou module Python manquant |
| 130 | interruption (Ctrl-C / SIGTERM), fichiers temporaires nettoyés |

### 2.5 Ce que fait `run.sh`, étape par étape

1. **Téléchargement et vérification** — `scripts/01_download.sh` : téléchargement
   atomique (`.part` puis renommage), rejet des fichiers anormalement petits
   (pointeur Git LFS ou page d'erreur), archive `tar.gz` lisible, somme SHA-256
   créée au premier lancement puis vérifiée à chaque lancement.
2. **Extraction** — seuls les trois fichiers utiles sont extraits de l'archive
   dans `data/raw/luad_tcga/`, puis passés en lecture seule.
3. **Nettoyage** — `scripts/02_clean.sh` construit une ligne par patient
   séquencé : statut KRAS, catégorie de tabagisme, paquets-années, sexe, âge.
4. **Analyse** — `scripts/analyze.py` : test exact de Fisher (odds ratio et
   IC 95 %), test de Mann-Whitney sur les paquets-années, tableau de
   contingence, résultats JSON/CSV et trois figures.
5. **Archivage** — `scripts/03_archive.sh` : archive `tar.gz` datée des
   résultats et de la table nettoyée, avec somme SHA-256.

Les résultats d'analyse ne sont remplacés qu'**après** le succès de l'analyse :
une erreur ou une interruption laisse intacts les résultats déjà terminés. La
table nettoyée, elle, n'est publiée dans `data/processed/` qu'après vérification
de son en-tête et de son nombre de lignes. Le pipeline peut être relancé sans
nettoyage manuel.

### 2.6 Exécution script par script

```bash
# 1. Téléchargement (option -f pour forcer, -h pour l'aide)
bash scripts/01_download.sh

# 2. Extraction manuelle des trois fichiers utiles
mkdir -p data/raw/luad_tcga
tar -xzf data/raw/luad_tcga.tar.gz -C data/raw/luad_tcga --strip-components=1 \
    --wildcards '*data_mutations.txt' '*data_clinical_patient.txt' \
    '*data_clinical_sample.txt'
chmod a-w data/raw/luad_tcga/*.txt     # données brutes en lecture seule

# 3. Nettoyage
bash scripts/02_clean.sh -i data/raw/luad_tcga \
    -o data/processed/patients_kras_smoking.tsv

# 4. Analyse et figures
python scripts/analyze.py --input data/processed/patients_kras_smoking.tsv \
    --output results

# 5. Archive datée (dossiers au choix, par défaut results + data/processed)
bash scripts/03_archive.sh
```

`scripts/lib.sh` n'est pas exécutable seul : il se source
(`source scripts/lib.sh`) et fournit `log()`, `die()`, `require_tools()`, les
codes de retour communs et les fonctions de somme de contrôle.

---

## 3. Arborescence

```text
LUAD-KRAS-Analysis/
├── run.sh                     # point d'entrée : enchaîne les 5 étapes
├── README.md                  # ce fichier
├── SOURCES.md                 # provenance et description des données
├── NOTES.md                   # exploration, décisions et effectifs
├── environment.yml            # environnement conda (versions épinglées)
├── requirements.txt           # équivalent pip de secours
├── .gitignore
├── .github/
│   └── pull_request_template.md
├── scripts/
│   ├── lib.sh                 # log(), die(), codes de retour, checksums
│   ├── 01_download.sh         # téléchargement + vérification d'intégrité
│   ├── 02_clean.sh            # nettoyage et fusion → table par patient
│   ├── analyze.py             # statistiques, JSON/CSV, 3 figures
│   ├── 03_archive.sh          # archive tar.gz datée + SHA-256
│   └── cron_example.txt       # exemple de crontab commenté
├── tests/
│   ├── test_run.sh            # robustesse de run.sh (données factices)
│   └── test_analyze.py        # tests pytest de l'analyse
├── data/
│   ├── raw/                   # archive + fichiers bruts (non versionnés)
│   └── processed/             # patients_kras_smoking.tsv
├── results/
│   └── figures/               # 3 figures PNG (produites)
├── archives/                  # archives datées + sommes de contrôle
└── logs/                      # journaux horodatés (produits)
```

Les dossiers `data/raw/`, `data/processed/`, `results/` et `logs/` sont vidés
par `.gitignore`. La table `data/processed/patients_kras_smoking.tsv` est
exceptionnellement versionnée : c'est la table de référence produite par
l'étape de nettoyage.

---

## 4. Fichiers produits

| Fichier | Produit par | Contenu |
|---|---|---|
| `data/raw/luad_tcga.tar.gz` | `01_download.sh` | archive source (152 Mo), lecture seule |
| `data/raw/luad_tcga.tar.gz.sha256` | `01_download.sh` | somme de contrôle de référence (créée au 1er lancement) |
| `data/raw/luad_tcga/*.txt` | `run.sh` (extraction) | `data_mutations.txt`, `data_clinical_patient.txt`, `data_clinical_sample.txt`, lecture seule |
| `data/processed/patients_kras_smoking.tsv` | `02_clean.sh` | table finale : 230 patients + en-tête |
| `results/statistical_results.json` | `analyze.py` | effectifs, tableau 2×2, Fisher, Mann-Whitney |
| `results/contingency_table.csv` | `analyze.py` | tableau de contingence Fumeur/Jamais fumeur × MUT/WT |
| `results/figures/barplot_kras_smoking.png` | `analyze.py` | historique tabagique selon le statut KRAS |
| `results/figures/boxplot_pack_years.png` | `analyze.py` | paquets-années selon le statut KRAS |
| `results/figures/hist_pack_years.png` | `analyze.py` | distribution des paquets-années |
| `archives/luad_kras_AAAAMMJJ_HHMMSS.tar.gz` | `03_archive.sh` | `results/` + `data/processed/` |
| `archives/luad_kras_….tar.gz.sha256` | `03_archive.sh` | somme de contrôle de l'archive |
| `logs/run_AAAAMMJJ_HHMMSS.log` | `run.sh` | journal complet d'une exécution |

### Format de `patients_kras_smoking.tsv`

| Colonne | Valeurs | Remarque |
|---|---|---|
| `patient_id` | `TCGA-XX-XXXX` | identifiant patient TCGA |
| `sex` | `Male`, `Female`, `NA` | |
| `smoking_category` | `never`, `current`, `former`, `NA` | `former` = codes 3, 4 et 5 |
| `pack_years` | nombre ou `NA` | absent chez les jamais fumeurs |
| `age` | entier ou `NA` | âge au diagnostic |
| `kras_status` | `MUT`, `WT` | `MUT` = au moins une mutation KRAS |

Une ligne par patient **séquencé** : un patient non séquencé est inconnu, pas
« KRAS normal ». Les patients avec plusieurs échantillons ou plusieurs
mutations ne comptent qu'une fois. Les décisions détaillées (colonnes gardées,
définition de « KRAS muté », catégories de tabagisme) sont dans `NOTES.md`.

---

## 5. Résultats attendus

Sur les 230 patients séquencés, 221 ont un historique tabagique exploitable
(9 exclus pour tabagisme manquant).

| | KRAS muté (MUT) | KRAS normal (WT) |
|---|---:|---:|
| Fumeur (current + former) | 67 | 122 |
| Jamais fumeur (never) | 5 | 27 |

- Test exact de Fisher : **OR ≈ 2,97**, IC 95 % ≈ **1,09–8,06**, **p ≈ 0,026**.
- Chez les patients KRAS mutés, 93,1 % ont fumé (67/72) contre 81,9 % chez les
  patients KRAS non mutés (122/149).
- Paquets-années (patients renseignés) : médiane 38 (n = 57) chez les MUT contre
  40 (n = 101) chez les WT ; test de Mann-Whitney : **p ≈ 0,76** (aucune
  différence détectée sur les valeurs renseignées).

Ces chiffres décrivent **ce jeu de données**, pas une conclusion clinique. Ils
sont reproduits par `./run.sh` et servent de référence pour vérifier une
installation.

---

## 6. Tests et reproductibilité

### Tests automatiques

```bash
# Robustesse de run.sh : données factices, aucun accès internet nécessaire
bash tests/test_run.sh

# Analyse : Fisher sur tableau connu, valeurs manquantes, fichiers écrits, codes 3/1
python -m pytest -q tests/test_analyze.py

# Ou tout en une fois, dans le pipeline
./run.sh -s -t
```

`tests/test_run.sh` construit un petit jeu de données factice, le sert via une
URL `file://` et vérifie notamment : l'aide et les options, les codes 2/3/4/5,
la lecture seule des données brutes, le contenu de la table nettoyée, les
sorties JSON/CSV/PNG, l'archive et son checksum, le nettoyage du dossier
temporaire, la relance sans nettoyage manuel, un fichier manquant, une archive
altérée, l'absence d'internet et une interruption Ctrl-C.

### Vérification depuis un clone neuf

```bash
git clone https://github.com/aliBoucetta-tech/LUAD-KRAS-Analysis.git /tmp/verif-luad
cd /tmp/verif-luad
conda env create -f environment.yml
conda activate luad-kras
bash tests/test_run.sh
./run.sh
```

### Vérification dans un conteneur ou une machine propre

Dans une VM ou un conteneur neuf (par exemple `ubuntu:24.04`), installer
`git`, `curl`, `tar`, `gzip` et Miniconda, puis suivre **uniquement** les
sections 1 et 2 de ce README. Le pipeline doit aller au bout sans étape
manuelle. Toute erreur doit être renvoyée à la personne responsable de l'étape
concernée (voir la répartition ci-dessous).

---

## 7. Tâche planifiée (`cron`)

`scripts/cron_example.txt` contient un exemple prêt à adapter. Il explique
comment installer les tâches **sans écraser** celles déjà présentes :

```bash
# Remplacer /CHEMIN/ABSOLU/projet par le chemin réel du dépôt
(crontab -l 2>/dev/null; cat scripts/cron_example.txt) | crontab -
crontab -l        # vérifier
```

Tâches proposées :

| Fréquence | Commande | Rôle |
|---|---|---|
| chaque lundi à 03h00 | `./run.sh` | relancer tout le pipeline |
| chaque jour à 02h00 | `./scripts/01_download.sh` | vérifier les données brutes |
| chaque dimanche à 04h00 | `./scripts/03_archive.sh` | créer une archive datée |

La sortie des tâches est redirigée vers `logs/cron.log`. Comme `cron` n'hérite
pas de l'environnement interactif, le fichier d'exemple fixe `SHELL` et `PATH` ;
si conda est utilisé, remplacer `./run.sh` par la commande complète
(`conda run -n luad-kras ./run.sh`) ou activer l'environnement dans un petit
script wrapper.

---

## 8. Répartition du travail

Le projet a été mené en relais : chaque personne transmet un résultat qui
fonctionne, avec une branche et une pull request relue par la personne suivante.

| Étape | Personne | Rôle et livrables | Fichiers principaux |
|---|---|---|---|
| 1 | Personne 2 (`aliBoucetta-tech`) | dépôt, arborescence, `.gitignore`, protection de `main`, accès des 5 personnes | structure du dépôt |
| 2 | Personne 1 (`ineskh9`) | exploration manuelle, décisions, fusion et nettoyage en shell | `NOTES.md`, `02_clean.sh`, `patients_kras_smoking.tsv` |
| 3 | Personne 5 (`nourelhouda518`) | analyse Python : Fisher, Mann-Whitney, figures, tests | `analyze.py`, `tests/test_analyze.py` |
| 4 | Personne 4 (Mounia Seddiki) | téléchargement, intégrité, environnement, journalisation, cron, archive | `01_download.sh`, `lib.sh`, `environment.yml`, `03_archive.sh`, `cron_example.txt` |
| 5 | Personne 3 (`maria`) | `run.sh`, robustesse, tests de panne | `run.sh`, `tests/test_run.sh` |
| 6 | Personne 2 (`aliBoucetta-tech`) | documentation finale et test sur clone neuf / machine propre | `README.md`, `SOURCES.md` |

Les sections du rapport sont réparties de la même façon : introduction et
assemblage (Personne 2), données et méthode (Personne 1), résultats
(Personne 5), définition du motif et relecture (Personne 3), limites et
reproductibilité (Personne 4).

---

## 9. Tableau des 20 critères (auto-évaluation)

Grille de contrôle reprenant les exigences du projet. Elle est à recouper avec
la grille officielle distribuée en cours.

| # | Critère | Où c'est fait | Vérification |
|---:|---|---|---|
| 1 | Dépôt Git fonctionnel, `main` protégée, les 5 personnes peuvent cloner et pousser | GitHub | `git clone` puis pull request |
| 2 | Arborescence complète, `.gitignore`, fichiers `.gitkeep` | dépôt | `git ls-files` |
| 3 | README : installation, mode d'emploi, arborescence, fichiers produits, répartition, cron | `README.md` | ce fichier |
| 4 | SOURCES.md : lien, date, fichiers utilisés et ignorés | `SOURCES.md` | lecture |
| 5 | NOTES.md : exploration, décisions, effectifs, table finale | `NOTES.md` | lecture |
| 6 | `02_clean.sh` : `getopts` (`-i`, `-o`, `-h`), aide, code 2 | `scripts/02_clean.sh` | `bash scripts/02_clean.sh -h` |
| 7 | `02_clean.sh` : enchaînement de 3 commandes ou plus, valeurs manquantes → `NA`, une ligne par patient | `scripts/02_clean.sh` | lecture + `awk -F'\t' '{print NF}'` |
| 8 | `02_clean.sh` : lignes écartées journalisées, code 3 si entrée manquante | `scripts/02_clean.sh` | `bash scripts/02_clean.sh -i /inexistant -o /tmp/x.tsv` |
| 9 | `patients_kras_smoking.tsv` : 230 patients, 6 colonnes, en-tête attendu | `data/processed/` | `wc -l` = 231 |
| 10 | `analyze.py` : `argparse` (`--input`, `--output`), codes 3 et 1 | `scripts/analyze.py` | `python scripts/analyze.py -h` |
| 11 | Test exact de Fisher avec odds ratio et IC 95 % | `scripts/analyze.py` | `statistical_results.json` |
| 12 | Mann-Whitney sur les paquets-années + distribution des variants par tabagisme | `scripts/analyze.py` | JSON + figures |
| 13 | Trois figures et résultats JSON/CSV produits automatiquement | `results/` | `ls results/figures/*.png` |
| 14 | Tests `pytest` : Fisher connu, valeurs manquantes, fichiers écrits, codes 3/1 | `tests/test_analyze.py` | `pytest -q tests/test_analyze.py` |
| 15 | `01_download.sh` : checksum créée puis vérifiée, code 4, rejet des fichiers < 1 Mo (LFS) | `scripts/01_download.sh` | `bash scripts/01_download.sh -h` + test d'altération |
| 16 | `environment.yml` épinglé + `requirements.txt` de secours | racine | `conda env create -f environment.yml` |
| 17 | `lib.sh` : `log()` horodatée, données brutes en lecture seule, scripts exécutables | `scripts/lib.sh` | `stat -c %A data/raw/luad_tcga/*` |
| 18 | Archive `tar.gz` datée + SHA-256, exemple de `cron` expliqué | `scripts/03_archive.sh`, `scripts/cron_example.txt` | `(cd archives && sha256sum -c *.sha256)` |
| 19 | `run.sh` : `-h`, au moins 2 options `getopts`, `set -euo pipefail`, `die()`, `trap` sur `mktemp -d`, 3 fonctions réutilisées, relance sans nettoyage | `run.sh` | `./run.sh -h`, `./run.sh -n` |
| 20 | `run.sh` testé : fichier manquant, Ctrl-C, option inconnue, pas d'internet ; test sur clone neuf / VM propre | `tests/test_run.sh` | `bash tests/test_run.sh` |

Dernière vérification : **13 novembre 2026**, depuis un clone neuf sous Linux,
avec Python 3.11.18 et l'archive de données réelle :

- `pytest -q tests/test_analyze.py` : **5 tests réussis** ;
- `bash tests/test_run.sh` : **27 vérifications réussies, 0 échec** ;
- `./run.sh -s -t` sur les vraies données : **code 0**, archive et checksum
  valides, table produite identique à `data/processed/patients_kras_smoking.tsv`,
  résultats identiques à la section 5.

---

## 10. Limites

- Les **jamais fumeurs** sont peu nombreux (32 patients dans l'analyse) : les
  intervalles de confiance sont larges.
- Les **paquets-années** manquent chez de nombreux patients (72 `NA` sur 230,
  dont les jamais fumeurs) ; le test de Mann-Whitney ne porte que sur les
  patients renseignés.
- Les données sont **observationnelles et rétrospectives** : une association
  n'implique pas un lien causal.
- Une seule cohorte (TCGA-LUAD) et pas d'ajustement sur l'âge, le sexe ou le
  stade ; pas de correction pour tests multiples.
- Le **type exact de mutation KRAS** (codon, substitution) n'est pas étudié :
  le statut est binaire (au moins une mutation non silencieuse).
- La somme de contrôle des données brutes est **locale** (créée au premier
  lancement) : elle détecte une corruption ultérieure, pas une altération de la
  source.

---

## 11. Sources et citation

Les données, leur provenance et les références sont détaillées dans
[`SOURCES.md`](SOURCES.md). En résumé : TCGA-LUAD via cBioPortal
(`luad_tcga`), téléchargé le 2026-11-02. Citer le TCGA Research Network
(*Nature*, 2014) et cBioPortal (Cerami *et al.*, 2012 ; Gao *et al.*, 2013).

Les données TCGA sont publiques ; le dépôt ne contient que des identifiants
TCGA (code-barres), aucune donnée personnelle identifiante.

---

## 12. Dépannage

### 12.1 Erreurs fréquentes

| Message / symptôme | Cause probable | Solution |
|---|---|---|
| `Permission denied` en lançant `./run.sh` | script non exécutable | `chmod +x run.sh scripts/*.sh scripts/analyze.py` |
| `python: command not found` | Python absent | installer Python 3.11 ou Miniconda (section 1.5) |
| `python --version` affiche 3.13 ou 3.14 | mauvaise version de Python | créer l'environnement 3.11 et l'activer |
| code **6** : `Missing Python module(s)` | environnement non activé ou mauvais interpréteur | `conda activate luad-kras` ou `source .venv/bin/activate`, puis vérifier `which python` |
| code **5** : `Download failed` | pas d'internet, proxy ou URL indisponible | vérifier la connexion ; si `data/raw/luad_tcga.tar.gz` existe déjà, relancer avec `./run.sh -s` |
| code **4** : checksum / intégrité | archive corrompue ou modifiée | `./run.sh -f` pour la retélécharger |
| code **3** : `Missing file` | archive absente ou vide | `./run.sh` (télécharge) ou `./run.sh -f` |
| `--wildcards` non reconnu / `sha256sum: command not found` | macOS avec outils BSD | section 1.3, ou utiliser WSL2 / Linux |
| `bad interpreter: /usr/bin/env: bash` ou `\r` dans les messages | fins de ligne Windows (CRLF) | `sed -i 's/\r$//' run.sh scripts/*.sh scripts/*.py` puis relancer |
| `conda: command not found` | Miniconda non initialisé | rouvrir le terminal, ou `eval "$("$HOME/miniconda3/bin/conda" shell.bash hook)"` |
| `No space left on device` | disque plein | libérer environ 400 Mo |
| `fatal: could not read Username` ou 404 au `git clone` | dépôt privé / pas d'accès | demander à être ajouté comme collaborateur, ou utiliser l'archive ZIP |
| `tests/test_run.sh` affiche des `FAIL` | environnement incomplet ou macOS | vérifier Python 3.11 et les modules ; sous macOS, préférer WSL2/Linux |

### 12.2 Vérifications utiles

```bash
pwd                         # doit finir par LUAD-KRAS-Analysis
which python                # doit pointer vers .../luad-kras/... ou .../.venv/...
python --version            # doit afficher 3.11.x
bash --version              # doit afficher 4.x ou plus
ls data/raw/luad_tcga.tar.gz
ls results/figures/*.png
```

### 12.3 Repartir de zéro

Si l'environnement Python est cassé, supprimer **uniquement** le dossier
`.venv/`, puis recréer l'environnement (section 1.5).

Ne pas supprimer `data/processed/patients_kras_smoking.tsv` : c'est la table de
référence versionnée. Pour forcer un nouveau téléchargement des données brutes :

```bash
./run.sh -f
```

Enfin, pour vérifier que le dépôt est bien à jour avant de le transmettre :

```bash
git status
git log --oneline -3
```

---

## 13. Exécution rapide : deux cas

Deux cas seulement sont détaillés ici : **Windows 10/11** et **Linux Ubuntu**.
Dans les deux cas, la séquence va de l'installation au lancement du programme,
puis se termine par `./run.sh`. Les commandes se tapent toujours dans un
terminal **bash** (Ubuntu, ou terminal WSL2 sous Windows), jamais dans
PowerShell ou `cmd`.

---

### Cas 1 — Windows 10/11 (WSL2 + Ubuntu)

#### Étape 1. Installer WSL2 et Ubuntu (une seule fois)

Ouvrir **PowerShell en administrateur**, puis :

```powershell
wsl --install -d Ubuntu
```

Redémarrer l'ordinateur si demandé, lancer **Ubuntu** depuis le menu Démarrer,
et créer un nom d'utilisateur et un mot de passe Linux.

Ensuite, **dans le terminal Ubuntu** (pas PowerShell), installer les outils de
base :

```bash
sudo apt update
sudo apt install -y unzip curl tar gzip git
```

Installer Miniconda (si `conda` n'est pas déjà disponible) :

```bash
curl -fsSL -o /tmp/miniconda.sh \
  https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh
bash /tmp/miniconda.sh -b -p "$HOME/miniconda3"
eval "$("$HOME/miniconda3/bin/conda" shell.bash hook)"
conda init bash
```

Fermer puis rouvrir le terminal Ubuntu pour que `conda` soit reconnu.

> Important : travailler dans le dossier personnel Linux (`~`) et **non** dans
> `/mnt/c/...`. Le pipeline est beaucoup plus rapide et les permissions sont
> correctes.

#### Étape 2. Dézipper et lancer le programme

Placer l'archive ZIP dans le dossier personnel Linux, puis :

```bash
cd ~
unzip LUAD-KRAS-Analysis-main.zip
cd LUAD-KRAS-Analysis-main
chmod +x run.sh scripts/*.sh scripts/analyze.py
conda env create -f environment.yml
conda activate luad-kras
python --version          # doit afficher Python 3.11.x
./run.sh
```

Si le ZIP a été téléchargé dans Windows, le dézipper depuis Ubuntu avec le
chemin Windows, par exemple :

```bash
cd ~
unzip /mnt/c/Users/TON_NOM/Downloads/LUAD-KRAS-Analysis-main.zip
```

> Si `ls` montre un dossier portant le même nom à l'intérieur (archive ZIP
> imbriquée), entrer une seconde fois dedans : `cd LUAD-KRAS-Analysis-main`.
> Le bon dossier est celui qui contient `run.sh`.

#### Alternative : cloner le dépôt Git

```bash
cd ~
git clone https://github.com/aliBoucetta-tech/LUAD-KRAS-Analysis.git
cd LUAD-KRAS-Analysis
chmod +x run.sh scripts/*.sh scripts/analyze.py
conda env create -f environment.yml
conda activate luad-kras
./run.sh
```

> Le dépôt est privé : demander l'accès avant le `git clone`, ou utiliser le ZIP.

---

### Cas 2 — Linux Ubuntu (natif)

#### Étape 1. Installer les outils de base

```bash
sudo apt update
sudo apt install -y unzip curl tar gzip git
bash --version            # doit afficher 4.x ou plus
```

Installer Python 3.11 avec Miniconda (méthode recommandée) :

```bash
curl -fsSL -o /tmp/miniconda.sh \
  https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh
bash /tmp/miniconda.sh -b -p "$HOME/miniconda3"
eval "$("$HOME/miniconda3/bin/conda" shell.bash hook)"
conda init bash
```

Fermer puis rouvrir le terminal, et vérifier :

```bash
conda --version
```

#### Étape 2. Dézipper et lancer le programme

```bash
cd ~
unzip LUAD-KRAS-Analysis-main.zip
cd LUAD-KRAS-Analysis-main
chmod +x run.sh scripts/*.sh scripts/analyze.py
conda env create -f environment.yml
conda activate luad-kras
python --version          # doit afficher Python 3.11.x
./run.sh
```

> Si `ls` montre un dossier portant le même nom à l'intérieur (archive ZIP
> imbriquée), entrer une seconde fois dedans : `cd LUAD-KRAS-Analysis-main`.
> Le bon dossier est celui qui contient `run.sh`.

#### Alternative : cloner le dépôt Git

```bash
cd ~
git clone https://github.com/aliBoucetta-tech/LUAD-KRAS-Analysis.git
cd LUAD-KRAS-Analysis
chmod +x run.sh scripts/*.sh scripts/analyze.py
conda env create -f environment.yml
conda activate luad-kras
./run.sh
```

---

### Résultat attendu (les deux cas)

Le premier lancement télécharge l'archive de données (152 Mo, quelques
minutes), puis le pipeline s'exécute en une trentaine de secondes. Il doit se
terminer par :

```text
[INFO] [run.sh] Pipeline finished OK (log: logs/run_....log)
```

et le code de retour doit être **0**. Vérifier les fichiers produits :

```bash
ls results
# contingency_table.csv  figures  statistical_results.json
ls results/figures
# barplot_kras_smoking.png  boxplot_pack_years.png  hist_pack_years.png
wc -l data/processed/patients_kras_smoking.tsv
# 231  (1 en-tête + 230 patients)
```

> Si `conda env create -f environment.yml` répond que l'environnement
> `luad-kras` existe déjà, passer directement à
> `conda activate luad-kras` (ou lancer
> `conda env update -f environment.yml --prune`).

### Afficher les 3 figures du résultat

Une commande par figure (sous Linux) :

```bash
xdg-open results/figures/barplot_kras_smoking.png
xdg-open results/figures/boxplot_pack_years.png
xdg-open results/figures/hist_pack_years.png
```

Remarques :

- **macOS** : remplacer `xdg-open` par `open` ;
- **WSL** : si `xdg-open` n'est pas disponible, ouvrir le dossier dans Windows
  avec `explorer.exe "$(wslpath -w results/figures)"` ;
- si aucune fenêtre ne s'ouvre, vérifier que les fichiers existent avec :
  `ls -lh results/figures`.

### Supprimer les archives des exécutions

Une archive `luad_kras_AAAAMMJJ_HHMMSS.tar.gz` et son `.sha256` sont créées
dans `archives/` à chaque exécution réussie. Pour supprimer uniquement celles
générées par tes exécutions, sans toucher à l'archive de démonstration
versionnée :

```bash
ls -lh archives          # vérifier ce qui existe
git clean -n archives/   # aperçu (ne supprime rien)
git clean -f archives/   # suppression effective
```

Si le projet a été reçu en ZIP (sans dossier `.git`), ou pour supprimer
**toutes** les archives, y compris celle versionnée :

```bash
rm -f archives/luad_kras_*.tar.gz archives/luad_kras_*.tar.gz.sha256
```

> `rm -f` est définitif. Les résultats (`results/`) et la table nettoyée
> (`data/processed/`) ne sont pas touchés.
