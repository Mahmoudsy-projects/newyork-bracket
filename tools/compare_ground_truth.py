#!/usr/bin/env python3
"""
قدم ۲ سند (Spec_NY_Standalone_v1.md): صحت‌سنجیِ خروجیِ NY_DataScript.mq5 در برابرِ ground truthِ
بکتستِ چشمیِ محمود (docs/GroundTruth/Box_<window>.csv، از NY_Box_Backtest_v2.xlsx).

استفاده:
    python3 compare_ground_truth.py <window> <path/to/NY_History_<window>.csv>

    window یکی از: 0830-0930 | 0900-1000 | 0930-1030

خروجی: NY_GroundTruth_Match_Report_<window>.md در همان پوشه‌ی CSVِ ورودی.

نکته: این اسکریپت هر دو فرضیه‌ی DayNet_R (لیمیتِ گیت‌شده طبقِ متنِ سند) و DayNet_R_MarketEntry
(ورودِ بلافاصله) را با ستونِ Reward_R برگه‌ی چشمی می‌سنجد — نگاه کن به
docs/NY_FrozenDefinitions.md، بخشِ «سؤالِ باز» — تا معلوم شود پاسِ چشمیِ محمود کدام مدلِ ورودی را
فرض کرده بوده، بدونِ حدسِ کورکورانه.
"""
import sys
import os
import pandas as pd

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GROUND_TRUTH_DIR = os.path.join(REPO_ROOT, "docs", "GroundTruth")

# تلورانسِ چشمی طبقِ سند: MFE/MAE ±۰.۱-۰.۱۵ باکس. برایِ R از همان مرتبه (۰.۱۵) استفاده می‌شود چون
# سند مقدارِ جداگانه‌ای برایِ R نداده.
TOL_BOXES = 0.15
TOL_R = 0.15


# مهم: هم ground truth (ستونِ Break_Dir) و هم CSVِ تولیدشده (ستونِ BreakDir) از رشته‌ی تحت‌اللفظیِ
# "None" به‌عنوانِ یک مقدارِ معتبر (نه missing) استفاده می‌کنند — اما لیستِ NA پیش‌فرضِ pandas دقیقاً
# شاملِ رشته‌ی "None" است (هم‌راه با "NA"/"NaN"/"null"...)، پس بدونِ keep_default_na=False هر روزِ
# None به NaN تبدیل می‌شد و همه‌ی مقایسه‌ها با BreakDir=None را کاذباً «نامنطبق» نشان می‌داد. فقط
# رشته‌ی خالی "" را NA حساب می‌کنیم (فیلدهایِ واقعاً خالیِ CSV، مثلِ MFE_Boxes روزهایِ None).
def _read_csv_safe(path):
    return pd.read_csv(path, keep_default_na=False, na_values=[""])


def load_ground_truth(window):
    path = os.path.join(GROUND_TRUTH_DIR, f"Box_{window}.csv")
    if not os.path.exists(path):
        raise SystemExit(f"ground truth یافت نشد: {path}")
    gt = _read_csv_safe(path)
    gt["Date"] = pd.to_datetime(gt["Date"]).dt.strftime("%Y-%m-%d")
    return gt


def load_generated(path):
    if not os.path.exists(path):
        raise SystemExit(f"CSVِ تولیدشده یافت نشد: {path}")
    df = _read_csv_safe(path)
    df["Date"] = pd.to_datetime(df["Date"]).dt.strftime("%Y-%m-%d")
    return df


def dir_from_gt(v):
    if pd.isna(v) or str(v).strip() in ("", "None", "-"):
        return "None"
    return str(v).strip()


def compare(window, generated_path):
    gt = load_ground_truth(window)
    gen = load_generated(generated_path)
    gen_w = gen[gen["Window"] == window].copy()
    if gen_w.empty:
        # برای مواردی که فایل فقط یک پنجره دارد و ستونِ Window ست نشده/فرق دارد
        gen_w = gen.copy()

    merged = gt.merge(gen_w, on="Date", how="inner", suffixes=("_gt", "_gen"))
    lines = []
    lines.append(f"# گزارشِ تطبیقِ Ground Truth — پنجره‌ی {window}\n")
    lines.append(f"ردیف‌هایِ مشترک (join بر Date): {len(merged)} از {len(gt)} روزِ ground truth\n")

    if len(merged) == 0:
        lines.append("\n**هیچ ردیفِ مشترکی پیدا نشد** — تاریخ‌ها را چک کن (فرمت/محدوده‌ی هم‌بازه).\n")
        _write(window, generated_path, lines)
        return

    missing = set(gt["Date"]) - set(gen_w["Date"])
    if missing:
        lines.append(f"\n⚠️ {len(missing)} روزِ ground truth در خروجیِ مکانیکی نبود (skip شده؟): "
                      f"{', '.join(sorted(missing)[:15])}{' ...' if len(missing) > 15 else ''}\n")

    # --- ۱) BreakDir ---
    merged["gt_dir"] = merged["Break_Dir"].apply(dir_from_gt)
    dir_match = (merged["gt_dir"] == merged["BreakDir"])
    lines.append(f"\n## ۱. BreakDir\n\nتطابق: {dir_match.sum()}/{len(merged)} "
                 f"({100.0 * dir_match.mean():.1f}%) — سند انتظارِ ~۱۰۰٪ دارد.\n")
    if not dir_match.all():
        mism = merged.loc[~dir_match, ["Date", "gt_dir", "BreakDir", "Notes"]]
        lines.append("\nموارد نامنطبق:\n\n```\n" + mism.to_string(index=False) + "\n```\n")

    # --- ۲) MFE / MAE (فقط روزهای دارای شکست) ---
    tradable = merged[merged["gt_dir"] != "None"].copy()
    for col_name, label in [("MFE_Boxes", "MFE_Boxes"), ("MAE_Boxes", "MAE_Boxes")]:
        # ستون‌های هم‌نام gt/gen (هر دو فایل «MFE_Boxes» دارند) با suffix از هم جدا شده‌اند
        gtc = col_name + "_gt" if col_name + "_gt" in tradable.columns else col_name
        genc = col_name + "_gen" if col_name + "_gen" in tradable.columns else col_name
        sub = tradable.dropna(subset=[gtc])
        if sub.empty:
            continue
        diff = (sub[genc].astype(float) - sub[gtc].astype(float)).abs()
        within = (diff <= TOL_BOXES)
        lines.append(f"\n## {label}\n\nدرونِ تلورانسِ ±{TOL_BOXES} باکس: {within.sum()}/{len(sub)} "
                     f"({100.0 * within.mean():.1f}%)، میانگینِ قدرمطلقِ اختلاف: {diff.mean():.3f}\n")
        if not within.all():
            mism = sub.loc[~within, ["Date", gtc, genc]]
            lines.append("\nموارد نامنطبق:\n\n```\n" + mism.to_string(index=False) + "\n```\n")

    # --- ۳) DayNet_R vs Reward_R — دو فرضیه (نگاه کن به «سؤالِ باز» در NY_FrozenDefinitions.md) ---
    lines.append("\n## DayNet_R در برابرِ Reward_R — کدام مدلِ ورودی با پاسِ چشمی هم‌خوان است؟\n")
    for col, title in [("DayNet_R", "لیمیتِ گیت‌شده (طبقِ متنِ سند)"),
                        ("DayNet_R_MarketEntry", "ورودِ بلافاصله در کلوزِ شکست (فرضیه‌ی جایگزین)")]:
        sub = tradable.dropna(subset=["Reward_R", col])
        if sub.empty:
            lines.append(f"\n**{title}** ({col}): هیچ ردیفِ قابلِ مقایسه‌ای نبود.\n")
            continue
        diff = (sub[col].astype(float) - sub["Reward_R"].astype(float)).abs()
        within = (diff <= TOL_R)
        lines.append(f"\n**{title}** (`{col}`): درونِ تلورانسِ ±{TOL_R}R: {within.sum()}/{len(sub)} "
                     f"({100.0 * within.mean():.1f}%)، میانگینِ قدرمطلقِ اختلاف: {diff.mean():.3f}R\n")

    lines.append("\n> اگر یکی از این دو نرخِ تطابق به‌وضوح بالاتر بود (مثلاً >۸۰٪ در برابرِ <۵۰٪)، "
                 "همان مدلِ ورودی است که محمود در پاسِ چشمی استفاده کرده — نتیجه را به او گزارش بده "
                 "تا تعریفِ نهاییِ `DayNet_R` تثبیت شود.\n")

    _write(window, generated_path, lines)


def _write(window, generated_path, lines):
    out_dir = os.path.dirname(os.path.abspath(generated_path)) or "."
    out_path = os.path.join(out_dir, f"NY_GroundTruth_Match_Report_{window}.md")
    with open(out_path, "w", encoding="utf-8") as f:
        f.write("".join(lines))
    print(f"گزارش نوشته شد: {out_path}")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print(__doc__)
        sys.exit(1)
    compare(sys.argv[1], sys.argv[2])
