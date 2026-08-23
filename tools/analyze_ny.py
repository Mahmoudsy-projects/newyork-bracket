#!/usr/bin/env python3
"""
قدمِ ۳ سند (Spec_NY_Standalone_v1.md): تحلیلِ آفلاینِ ۱۷ ماه (هم‌بازه با دیتاستِ توکیو،
۲۰۲۵-۰۳-۱۷ تا امروز)، پس از عبورِ قدمِ ۲ (صحت‌سنجیِ ground truth). این اسکریپت روی
NY_History_<window>.csv های واقعی (خروجیِ MT5) اجرا می‌شود — **هیچ عددی در این فایل fabricate
نشده**؛ تا وقتی دیتایِ ۱۷ماهه از MetaEditor برنگردد، این فقط یک اسکلتِ قابلِ‌اجراست.

استفاده (بعد از اینکه سه فایلِ NY_History_<window>.csv از MT5 برگشتند):
    python3 analyze_ny.py \
        --window0900 NY_History_0900-1000.csv \
        --window0930 NY_History_0930-1030.csv \
        --window0830 NY_History_0830-0930.csv \
        --tokyo /path/to/DayBias_History_XAUUSD.csv \
        --out NY_Standalone_Report.md

سؤال‌هایِ قدمِ ۳ (بندِ ۳ سند) و وضعیتِ هرکدام در این اسکریپت:
  ۱) دوئلِ پنجره‌یِ ۹-۱۰ در برابرِ ۹:۳۰-۱۰:۳۰      -> پیاده‌سازی‌شده (analyze_window_duel)
  ۲) جاروی استاپ {0.5, 0.6, 0.75}                  -> نیازمندِ اجرایِ مجددِ NY_DataScript.mq5 با
                                                       NY_STOP_DEPTH_PCT متفاوت (نگاه کن به یادداشتِ
                                                       پایینِ تابعِ analyze_stop_sweep) — فعلاً TODO
  ۳) موتورِ ریورسِ ۸:۳۰ (مستقیم+ریورس کامل)         -> پیاده‌سازی‌شده (analyze_reversal_engine)
  ۴) ناهنجاریِ خلاف‌EMA                              -> پیاده‌سازی‌شده (analyze_ema_alignment)
  ۵) تفکیکِ NewsDay                                  -> پیاده‌سازی‌شده (analyze_news_breakdown)
  ۶) جدولِ مقایسه‌ی نهایی با توکیو (هم‌بازه)          -> پیاده‌سازی‌شده اگر --tokyo داده شود
     (analyze_tokyo_comparison)
"""
import argparse
import os
import pandas as pd
import numpy as np


def _load(path, window_label=None):
    df = pd.read_csv(path)
    df["Date"] = pd.to_datetime(df["Date"])
    df = df.sort_values("Date").reset_index(drop=True)
    if window_label and "Window" not in df.columns:
        df["Window"] = window_label
    return df


def _equity_stats(r_series):
    """E, WR, Sum, MaxDD, TTNH (روز) از یک سریِ R (NaN=روزِ بی‌ترید، حذف می‌شود)."""
    r = r_series.dropna().astype(float)
    if len(r) == 0:
        return dict(n=0, E=np.nan, WR=np.nan, Sum=np.nan, MaxDD=np.nan, TTNH_days=np.nan)
    eq = r.cumsum()
    running_max = eq.cummax()
    dd = eq - running_max
    max_dd = dd.min()

    # TTNH: طولانی‌ترینِ فاصله (به تعدادِ روزِ معامله‌شده) بینِ دو High جدیدِ متوالیِ equity.
    is_new_high = (eq == running_max).values
    high_idx = np.where(is_new_high)[0]
    ttnh = int(np.max(np.diff(high_idx))) if len(high_idx) > 1 else 0

    return dict(
        n=len(r), E=r.mean(), WR=float((r > 0).mean()), Sum=r.sum(),
        MaxDD=max_dd, TTNH_days=ttnh,
    )


def analyze_window_duel(df_a, label_a, df_b, label_b):
    """سؤالِ ۱: مقایسه‌ی E/WR/Sum/MaxDD/TTNH دو پنجره رویِ DayNet_R."""
    sa = _equity_stats(df_a["DayNet_R"])
    sb = _equity_stats(df_b["DayNet_R"])
    lines = [f"### دوئلِ پنجره: {label_a} در برابرِ {label_b}\n",
             "| متریک | " + label_a + " | " + label_b + " |", "|---|---|---|"]
    for k in ["n", "E", "WR", "Sum", "MaxDD", "TTNH_days"]:
        lines.append(f"| {k} | {sa[k]:.3f} | {sb[k]:.3f} |" if not pd.isna(sa[k]) else f"| {k} | n/a | n/a |")
    return "\n".join(lines) + "\n"


def analyze_stop_sweep(*_args, **_kwargs):
    return (
        "### جاروی استاپ {0.5, 0.6, 0.75}\n\n"
        "**TODO** — این جارو با ستون‌هایِ فعلیِ CSV (که فقط برایِ استاپِ ثابتِ ۷۵٪ محاسبه شده‌اند) "
        "قابلِ بازسازیِ دقیق نیست، چون مسیرِ کاملِ کندل‌به‌کندل ثبت نشده (فقط MFE/MAE/exitR نهایی). "
        "برایِ اجرایِ این بخش: `NY_STOP_DEPTH_PCT` در `NY_DetectionLayer.mqh` را به یک ورودیِ "
        "پارامتریک (`InpStopDepthPct`) تبدیل کن، و برایِ دو پنجره‌ی برتر (نتیجه‌ی سؤالِ ۱) با هرکدام "
        "از سه مقدار دوباره اجرا بگیر (۶ اجرایِ اضافه). سنجه‌ی دوم طبقِ سند: کیفیتِ منحنی (نه فقط E).\n"
    )


def analyze_reversal_engine(df_0830):
    """سؤالِ ۳: E کاملِ مستقیم+ریورس (فقط پنجره‌ی ۸:۳۰) در برابرِ بهترینِ پنجره‌یِ ساده.

    ترکیب: روزی که لگِ مستقیم گرفته شد، R آن روز = DayNet_R. روزی که لگِ مستقیم رد شد (کنسل/بی‌ترید)
    ولی ریورس فعال و گرفته شد، R آن روز = Rev_ExitR. این دو حالت هرگز هم‌روزه نیستند (طبقِ تعریف:
    ریورس فقط وقتی فعال می‌شود که لگِ مستقیم به +۱باکس نرسیده باشد) پس جمعشان یک سریِ R پیوسته می‌سازد.
    """
    direct = _equity_stats(df_0830["DayNet_R"])

    triggered = df_0830[df_0830["Rev_Triggered"] == 1].copy()
    rev_stats = _equity_stats(triggered["Rev_ExitR"])
    rev_stop_rate = float((df_0830["Rev_Outcome"] == "Stop").sum() / max(1, len(triggered))) if len(triggered) else np.nan
    rev_tp_rate   = float((df_0830["Rev_Outcome"] == "TP").sum()   / max(1, len(triggered))) if len(triggered) else np.nan

    # سریِ ترکیبی: R لگِ مستقیم اگر ترید شد، وگرنه R ریورس اگر فعال شد، وگرنه NaN (روزِ کاملاً بی‌ترید).
    combined = df_0830["DayNet_R"].copy()
    combined = combined.fillna(df_0830["Rev_ExitR"])
    combined_stats = _equity_stats(combined)

    lines = ["### موتورِ ریورسِ ۸:۳۰\n",
             f"روزهایِ دارایِ ترید (فقط لگِ مستقیم): n={direct['n']}, E={direct['E']:.3f}\n",
             f"نرخِ فعال‌شدنِ ریورس (از کلِ روزهایِ دارایِ شکست): "
             f"{100.0 * len(triggered) / max(1, len(df_0830[df_0830['BreakDir'] != 'None'])):.1f}%\n",
             f"از روزهایِ فعال‌شده: TP={rev_tp_rate * 100:.1f}%  Stop={rev_stop_rate * 100:.1f}%  "
             f"(n={rev_stats['n']}, E ریورسِ تنها={rev_stats['E']:.3f})\n",
             "\n**E کاملِ مستقیم+ریورس (سؤالِ ۳):**\n\n"
             f"n={combined_stats['n']}, E={combined_stats['E']:.3f}, WR={combined_stats['WR']:.3f}, "
             f"Sum={combined_stats['Sum']:.3f}, MaxDD={combined_stats['MaxDD']:.3f}\n",
             "\n> سؤالِ سند: «پیچیدگیِ دولگی می‌ارزد؟» — این E را با E مستقیمِ تنها (بالا) و با بهترینِ "
             "پنجره‌ی سادهِ سؤالِ ۱ مقایسه کن.\n"]
    return "\n".join(lines)


def analyze_ema_alignment(df, window_label):
    """سؤالِ ۴: E شرطیِ Aligned/خلاف در این پنجره — تأیید یا ردِ وارونگیِ نسبت به توکیو."""
    d = df[df["BreakDir"].isin(["Buy", "Sell"])].copy()
    d = d[d["Bias_Daily"].isin(["Buy", "Sell"])]
    d["Aligned"] = (d["BreakDir"] == d["Bias_Daily"])
    aligned_stats = _equity_stats(d.loc[d["Aligned"], "DayNet_R"])
    counter_stats = _equity_stats(d.loc[~d["Aligned"], "DayNet_R"])
    lines = [f"### ناهنجاریِ خلاف‌EMA — {window_label}\n",
             "| گروه | n | E | WR |", "|---|---|---|---|",
             f"| هم‌جهتِ EMA20/H1 | {aligned_stats['n']} | {aligned_stats['E']:.3f} | {aligned_stats['WR']:.3f} |",
             f"| خلافِ EMA20/H1 | {counter_stats['n']} | {counter_stats['E']:.3f} | {counter_stats['WR']:.3f} |",
             "\nیافته‌ی چشمی: خلاف‌EMA در NY بهتر بود (وارونه‌ی توکیو) — این جدول همان فرضیه را روی "
             "دیتایِ مکانیکی می‌سنجد.\n"]
    return "\n".join(lines)


def analyze_news_breakdown(df, window_label):
    """سؤالِ ۵: سهمِ E از روزهایِ خبری."""
    d = df[df["BreakDir"].isin(["Buy", "Sell"])].copy()
    d["IsNews"] = d["NewsDay"].fillna("").astype(str).str.len() > 0
    news_stats = _equity_stats(d.loc[d["IsNews"], "DayNet_R"])
    non_news_stats = _equity_stats(d.loc[~d["IsNews"], "DayNet_R"])
    lines = [f"### تفکیکِ NewsDay — {window_label}\n",
             "| گروه | n | E | WR | Sum |", "|---|---|---|---|---|",
             f"| روزِ خبری (high-impact USD) | {news_stats['n']} | {news_stats['E']:.3f} | "
             f"{news_stats['WR']:.3f} | {news_stats['Sum']:.3f} |",
             f"| غیرِخبری | {non_news_stats['n']} | {non_news_stats['E']:.3f} | "
             f"{non_news_stats['WR']:.3f} | {non_news_stats['Sum']:.3f} |",
             "\n⚠️ این جدول فقط درست است اگر `--news-calendar` هنگامِ اجرایِ MT5 پر شده باشد "
             "(`InpNewsCalendarFile` در NY_DataScript.mq5)؛ وگرنه NewsDay همیشه خالی است.\n"]
    return "\n".join(lines)


def analyze_tokyo_comparison(ny_best_stats, ny_best_label, tokyo_csv_path):
    """سؤالِ ۶: جدولِ مقایسه‌ی نهایی، هم‌بازه با توکیو — بهترین پیکربندیِ NY در برابرِ توکیو-پایه."""
    if not tokyo_csv_path or not os.path.exists(tokyo_csv_path):
        return ("### مقایسه‌ی نهایی با توکیو\n\n**TODO** — مسیرِ CSVِ توکیو داده نشد یا پیدا نشد "
                "(`--tokyo`). این جدول را با `DayBias_History_XAUUSD.csv`ِ ریپوی RiskManager-EA اجرا کن.\n")
    tokyo = _load(tokyo_csv_path)
    tokyo_stats = _equity_stats(tokyo["R_Day"].replace("", np.nan))
    lines = ["### مقایسه‌ی نهایی با توکیو (هم‌بازه)\n",
             "| متریک | NY بهترین (" + ny_best_label + ") | توکیو-پایه |", "|---|---|---|"]
    for k in ["n", "E", "WR", "Sum", "MaxDD", "TTNH_days"]:
        v1 = ny_best_stats.get(k, np.nan)
        v2 = tokyo_stats.get(k, np.nan)
        lines.append(f"| {k} | {v1:.3f} | {v2:.3f} |" if not (pd.isna(v1) or pd.isna(v2)) else f"| {k} | n/a | n/a |")
    lines.append("\n> حکمِ پیشنهادی («پیکربندیِ برنده‌ی NY» برایِ ورودِ فازِ ۲) را بعد از این جدول "
                 "و بعد از عبورِ قدمِ ۲ (ground truth) بنویس — نه زودتر.\n")
    return "\n".join(lines)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--window0900", help="NY_History_0900-1000.csv")
    ap.add_argument("--window0930", help="NY_History_0930-1030.csv")
    ap.add_argument("--window0830", help="NY_History_0830-0930.csv")
    ap.add_argument("--tokyo", help="DayBias_History_XAUUSD.csv (برایِ سؤالِ ۶)")
    ap.add_argument("--out", default="NY_Standalone_Report.md")
    args = ap.parse_args()

    if not (args.window0900 and args.window0930):
        raise SystemExit("حداقل --window0900 و --window0930 لازم است (دوئلِ سؤالِ ۱).")

    df0900 = _load(args.window0900, "0900-1000")
    df0930 = _load(args.window0930, "0930-1030")
    df0830 = _load(args.window0830, "0830-0930") if args.window0830 else None

    report = ["# NY_Standalone_Report — فازِ ۱، قدمِ ۳\n",
              "> تولیدشده توسطِ tools/analyze_ny.py — طبقِ ترتیبِ سؤال‌هایِ بندِ ۳ سند.\n"]

    report.append(analyze_window_duel(df0900, "0900-1000", df0930, "0930-1030"))
    report.append(analyze_stop_sweep())
    if df0830 is not None:
        report.append(analyze_reversal_engine(df0830))
        report.append(analyze_ema_alignment(df0830, "0830-0930"))
        report.append(analyze_news_breakdown(df0830, "0830-0930"))
    for df, label in [(df0900, "0900-1000"), (df0930, "0930-1030")]:
        report.append(analyze_ema_alignment(df, label))
        report.append(analyze_news_breakdown(df, label))

    best_stats = _equity_stats(df0900["DayNet_R"])
    best_label = "0900-1000"
    alt_stats = _equity_stats(df0930["DayNet_R"])
    if not pd.isna(alt_stats["E"]) and (pd.isna(best_stats["E"]) or alt_stats["E"] > best_stats["E"]):
        best_stats, best_label = alt_stats, "0930-1030"
    report.append(analyze_tokyo_comparison(best_stats, best_label, args.tokyo))

    with open(args.out, "w", encoding="utf-8") as f:
        f.write("\n".join(report))
    print(f"گزارش نوشته شد: {args.out}")


if __name__ == "__main__":
    main()
