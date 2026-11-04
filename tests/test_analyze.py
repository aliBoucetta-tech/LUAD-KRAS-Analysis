import json
import os
import sys

import numpy as np
import pandas as pd
import pytest

# analyze.py est dans scripts/ (ce fichier est dans tests/)
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "scripts"))

from analyze import build_2x2, fisher_test, prepare_groups, run_analysis  # noqa: E402


def make_df():
    """Petit jeu de données connu : 67/122 fumeurs, 5/27 jamais fumeurs,
    + 2 patients sans statut tabagique."""
    rows = []
    rows += [("current", "MUT", 30.0)] * 30 + [("former", "MUT", 40.0)] * 37
    rows += [("current", "WT", 20.0)] * 40 + [("former", "WT", 35.0)] * 82
    rows += [("never", "MUT", np.nan)] * 5 + [("never", "WT", np.nan)] * 27
    rows += [(np.nan, "MUT", np.nan), (np.nan, "WT", np.nan)]
    df = pd.DataFrame(rows, columns=["smoking_category", "kras_status", "pack_years"])
    df.insert(0, "patient_id", [f"P{i}" for i in range(len(df))])
    return df


def test_fisher_known_table():
    """Test 1 : Fisher sur un tableau connu."""
    df, _ = prepare_groups(make_df())
    table = build_2x2(df)
    assert table.values.tolist() == [[67, 122], [5, 27]]
    res = fisher_test(table)
    assert res["odds_ratio"] == pytest.approx(2.9656, abs=1e-3)
    assert res["p_value"] == pytest.approx(0.0263, abs=1e-3)
    assert res["ci_low"] < res["odds_ratio"] < res["ci_high"]


def test_missing_values_excluded():
    """Test 2 : les patients sans tabagisme sont exclus et comptés."""
    df, n_excluded = prepare_groups(make_df())
    assert n_excluded == 2
    assert df["smoking_group"].notna().all()
    assert len(df) == 221


def test_output_files_written(tmp_path):
    """Test 3 : les fichiers de sortie sont bien écrits."""
    input_file = tmp_path / "patients.tsv"
    make_df().to_csv(input_file, sep="\t", index=False)
    out = tmp_path / "results"
    run_analysis(str(input_file), str(out))
    assert (out / "statistical_results.json").exists()
    assert (out / "contingency_table.csv").exists()
    for name in ["barplot_kras_smoking.png", "boxplot_pack_years.png",
                 "hist_pack_years.png"]:
        assert (out / "figures" / name).exists()
    data = json.loads((out / "statistical_results.json").read_text())
    assert data["n_patients_analyzed"] == 221