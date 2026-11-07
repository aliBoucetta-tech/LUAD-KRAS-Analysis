#!/usr/bin/env python3
"""Analyse TCGA-LUAD : les mutations de KRAS sont-elles associées
à l'historique tabagique des patients ?

Usage :
    python analyze.py --input data/processed/patients_kras_smoking.tsv --output results
"""
import argparse
import json
import math
import os
import sys

import matplotlib
matplotlib.use("Agg")  # pas d'écran nécessaire (serveur / run.sh)
import matplotlib.pyplot as plt
import pandas as pd
import seaborn as sns
from scipy.stats import fisher_exact, mannwhitneyu

REQUIRED_COLUMNS = ["patient_id", "kras_status", "smoking_category", "pack_years"]

# Codes de retour, cohérents avec scripts/lib.sh (EX_MISSING_INPUT = 3)
EXIT_MISSING_INPUT = 3   # fichier d'entrée absent
EXIT_BAD_INPUT = 1       # fichier présent mais inutilisable : erreur générale
                         # (le code 4 de lib.sh = intégrité/checksum, autre sens)


def fail(message, code):
    """Écrit le message sur stderr (pas sur stdout) et quitte avec le code donné."""
    print(message, file=sys.stderr)
    sys.exit(code)


# ---------------------------------------------------------------- chargement
def load_data(input_file):
    """Lit le TSV nettoyé. Arrête le programme si le fichier est absent
    ou s'il manque une colonne (jamais de fausses données en secours)."""
    if not os.path.exists(input_file):
        fail(f"Erreur : fichier introuvable : {input_file}", EXIT_MISSING_INPUT)
    df = pd.read_csv(input_file, sep="\t")
    missing = [c for c in REQUIRED_COLUMNS if c not in df.columns]
    if missing:
        fail(f"Erreur : colonnes manquantes dans {input_file} : {missing}", EXIT_BAD_INPUT)
    return df


def prepare_groups(df):
    """Retire les patients sans statut tabagique et crée le groupe binaire
    Fumeur (current + former) / Jamais fumeur (never)."""
    n_total = len(df)
    df = df.dropna(subset=["smoking_category", "kras_status"]).copy()
    df["smoking_group"] = df["smoking_category"].map(
        {"current": "Smoker", "former": "Smoker", "never": "Never smoker"}
    )
    df = df.dropna(subset=["smoking_group"])
    if df.empty:
        fail("Erreur : aucun patient exploitable après filtrage.", EXIT_BAD_INPUT)
    return df, n_total - len(df)


# --------------------------------------------------------------- statistiques
def build_2x2(df):
    """Tableau 2x2 dans un ordre fixe : [[a, b], [c, d]]
    lignes : Smoker / Never smoker ; colonnes : MUT / WT."""
    table = pd.crosstab(df["smoking_group"], df["kras_status"])
    table = table.reindex(index=["Smoker", "Never smoker"],
                          columns=["MUT", "WT"], fill_value=0)
    return table


def fisher_test(table):
    """Test exact de Fisher + odds ratio + IC 95 % (méthode de Woolf)."""
    (a, b), (c, d) = table.values.tolist()
    odds_ratio, p_value = fisher_exact([[a, b], [c, d]])
    if min(a, b, c, d) == 0:
        ci_low = ci_high = float("nan")  # IC non calculable avec une cellule à 0
    else:
        se = math.sqrt(1 / a + 1 / b + 1 / c + 1 / d)
        ci_low = math.exp(math.log(odds_ratio) - 1.96 * se)
        ci_high = math.exp(math.log(odds_ratio) + 1.96 * se)
    return {"odds_ratio": odds_ratio, "p_value": p_value,
            "ci_low": ci_low, "ci_high": ci_high}


def mann_whitney_test(df):
    """Compare les pack-years entre KRAS MUT et WT (valeurs vides ignorées).
    Remarque : les 'never' n'ont aucune valeur de pack-years dans ce jeu."""
    mut = df.loc[df["kras_status"] == "MUT", "pack_years"].dropna()
    wt = df.loc[df["kras_status"] == "WT", "pack_years"].dropna()
    stat, p_value = mannwhitneyu(mut, wt, alternative="two-sided")
    return {"u_statistic": float(stat), "p_value": float(p_value),
            "n_mut": int(len(mut)), "n_wt": int(len(wt)),
            "median_mut": float(mut.median()), "median_wt": float(wt.median())}


# -------------------------------------------------------------------- figures
def make_figures(df, output_dir):
    """Crée 3 figures dans <output_dir>/figures/ et renvoie leurs chemins."""
    fig_dir = os.path.join(output_dir, "figures")
    os.makedirs(fig_dir, exist_ok=True)
    sns.set_theme(style="whitegrid")
    paths = []

    # 1. Barres : catégories de tabagisme selon le statut KRAS
    plt.figure(figsize=(8, 6))
    sns.countplot(data=df, x="kras_status", order=["MUT", "WT"],
                  hue="smoking_category",
                  hue_order=["never", "former", "current"], palette="Set2")
    plt.title("Historique tabagique selon le statut KRAS")
    plt.xlabel("Statut KRAS (MUT = muté, WT = non muté)")
    plt.ylabel("Nombre de patients")
    plt.tight_layout()
    paths.append(os.path.join(fig_dir, "barplot_kras_smoking.png"))
    plt.savefig(paths[-1], dpi=300)
    plt.close()

    # 2. Boîte à moustaches : pack-years par statut KRAS
    plt.figure(figsize=(8, 6))
    sns.boxplot(data=df, x="kras_status", y="pack_years", order=["MUT", "WT"],
                hue="kras_status", hue_order=["MUT", "WT"],
                palette="Pastel1", legend=False)
    plt.title("Paquets-années selon le statut KRAS")
    plt.xlabel("Statut KRAS")
    plt.ylabel("Paquets-années")
    plt.tight_layout()
    paths.append(os.path.join(fig_dir, "boxplot_pack_years.png"))
    plt.savefig(paths[-1], dpi=300)
    plt.close()

    # 3. Histogramme : distribution des pack-years
    plt.figure(figsize=(8, 6))
    sns.histplot(df["pack_years"].dropna(), kde=True, color="purple", bins=15)
    plt.title("Distribution des paquets-années (patients renseignés)")
    plt.xlabel("Paquets-années")
    plt.ylabel("Nombre de patients")
    plt.tight_layout()
    paths.append(os.path.join(fig_dir, "hist_pack_years.png"))
    plt.savefig(paths[-1], dpi=300)
    plt.close()
    return paths


# ------------------------------------------------------------------- sorties
def save_results(output_dir, table, fisher, mwu, n_analyzed, n_excluded):
    """Écrit le tableau 2x2 (CSV) et tous les résultats chiffrés (JSON)."""
    os.makedirs(output_dir, exist_ok=True)
    table.to_csv(os.path.join(output_dir, "contingency_table.csv"))
    results = {
        "n_patients_analyzed": n_analyzed,
        "n_excluded_missing_smoking": n_excluded,
        "contingency_table": table.to_dict(),
        "fisher": fisher,
        "mann_whitney": mwu,
    }
    with open(os.path.join(output_dir, "statistical_results.json"), "w",
              encoding="utf-8") as f:
        json.dump(results, f, indent=4)


def run_analysis(input_file, output_dir):
    df = load_data(input_file)
    df, n_excluded = prepare_groups(df)
    table = build_2x2(df)
    print("Tableau de contingence (Fumeur / Jamais fumeur x MUT / WT) :")
    print(table)
    print(f"Patients analysés : {len(df)} (exclus, tabagisme manquant : {n_excluded})")

    fisher = fisher_test(table)
    print(f"Fisher : OR = {fisher['odds_ratio']:.2f} "
          f"[IC95 % {fisher['ci_low']:.2f} - {fisher['ci_high']:.2f}], "
          f"p = {fisher['p_value']:.4f}")
    mwu = mann_whitney_test(df)
    print(f"Mann-Whitney (pack-years) : p = {mwu['p_value']:.4f}")

    save_results(output_dir, table, fisher, mwu, len(df), n_excluded)
    make_figures(df, output_dir)
    print(f"Résultats écrits dans : {output_dir}")


def main():
    parser = argparse.ArgumentParser(
        description="Analyse TCGA-LUAD : mutation KRAS vs historique tabagique")
    parser.add_argument("--input", required=True,
                        help="Chemin du fichier TSV nettoyé")
    parser.add_argument("--output", required=True,
                        help="Dossier où enregistrer les résultats")
    args = parser.parse_args()
    run_analysis(args.input, args.output)


if __name__ == "__main__":
    main() 