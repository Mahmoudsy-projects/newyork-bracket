#!/usr/bin/env python3
"""
قدمِ ۳ سند (Spec_NY_Standalone_v1.md): تحلیلِ آفلاینِ ۱۷ ماه (هم‌بازه با دیتاستِ توکیو،
۲۰۲۵-۰۳-۱۷ تا امروز)، پس از عبورِ قدمِ ۲ (صحت‌سنجیِ ground truth). این اسکریپت روی
NY_History_<window>.csv های واقعی (خروجیِ MT5) اجرا می‌شود — **هیچ عددی در این فایل fabricate
نشده**؛ تا وقتی دیتایِ ۱۷ماهه از MetaEditor برنگردد، این فقط یک اسکلتِ قابلِ‌اجراست.

v1.6 (دستورِ مدیرِ پروژه، ۲۳ اوت — `Manager_Decision_20260823.md`، خروجیِ این مرحله باید
`NY_Standalone_Report_PRELIM.md` با برچسبِ صریحِ «موقت» باشد):
  - مدلِ هزینه‌یِ موقت: ۰.۰۶R ثابت به‌ازایِ هر لگِ اجراشده (direct یا reversal)، اعمال‌شده در
    خودِ تحلیل (نه در CSVها) — هر جدولِ کلیدی حالا هم خام هم با-هزینه را کنارِ هم نشان می‌دهد.
  - جاروی استاپ {0.5, 0.6, 0.75} پیاده‌سازی شد — با فایل‌هایِ `NY_History_<window>_sd50.csv` و
    `_sd60.csv` (خروجیِ `InpStopDepthPct` در NY_DataScript.mq5)، کنارِ فایلِ پیش‌فرض (=sd75).
  - موتورِ ریورس: توزیعِ Rev_ExitR روی همه‌ی فعال‌سازی‌ها اضافه شد — برایِ سنجشِ فرضیه‌یِ «سوگیریِ
    ثبتِ انتخابی در برگه‌ی چشمی» (بندِ ۴ دستورِ مدیرِ پروژه، docs/Reversal_15Day_Diagnostic.md).

استفاده:
    python3 analyze_ny.py \
        --window0900 NY_History_0900-1000.csv \
        --window0930 NY_History_0930-1030.csv \
        --window0830 NY_History_0830-0930.csv \
        --sweep0900-sd50 NY_History_0900-1000_sd50.csv --sweep0900-sd60 NY_History_0900-1000_sd60.csv \
        --sweep0930-sd50 NY_History_0930-1030_sd50.csv --sweep0930-sd60 NY_History_0930-1030_sd60.csv \
        --tokyo /path/to/DayBias_History_XAUUSD.csv \
        --out NY_Standalone_Report_PRELIM.md

سؤال‌هایِ قدمِ ۳ (بندِ ۳ سند) و وضعیتِ هرکدام در این اسکریپت:
  ۱) دوئلِ پنجره‌یِ ۹-۱۰ در برابرِ ۹:۳۰-۱۰:۳۰      -> پیاده‌سازی‌شده (analyze_window_duel)
  ۲) جاروی استاپ {0.5, 0.6, 0.75}                  -> پیاده‌سازی‌شده (analyze_stop_sweep)، نیازمندِ
                                                       فایل‌هایِ sd50/sd60 (اختیاری؛ اگر داده نشوند TODO می‌ماند)
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

EXEC_COST_R = 0.06  # v1.6، بندِ ۲ دستورِ مدیرِ پروژه: هزینه‌یِ ثابتِ موقت، به‌ازایِ هر لگِ اجراشده


def _load(path, window_label=None):
    df = pd.read_csv(path)
    df["Date"] = pd.to_datetime(df["Date"])
    df = df.sort_values("Date").reset_index(drop=True)
    if window_label and "Window" not in df.columns:
        df["Window"] = window_label
    return df


def _equity_stats(r_series, cost_r=0.0):
    """E, WR, Sum, MaxDD, TTNH (روز) از یک سریِ R (NaN=روزِ بی‌ترید، حذف می‌شود).

    cost_r>0: از هر لگِ اجراشده (هر مقدارِ غیرِNaN) این مقدار کم می‌شود — مدلِ هزینه‌یِ موقتِ v1.6.
    """
    r = r_series.dropna().astype(float)
    if cost_r:
        r = r - cost_r
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


def _fmt_row(label, sa, sb=None):
    def fmt(s):
        return f"{s['n']} / {s['E']:.3f} / {s['WR']:.3f} / {s['Sum']:.3f} / {s['MaxDD']:.3f}" if s["n"] else "n/a"
    if sb is None:
        return f"| {label} | {fmt(sa)} |"
    return f"| {label} | {fmt(sa)} | {fmt(sb)} |"


def _costed_table_lines(label_a, series_a, label_b=None, series_b=None):
    """جدولِ خام + با-هزینه (۰.۰۶R/لگ) کنارِ هم — قراردادِ مشترکِ همه‌یِ جدول‌هایِ کلیدی."""
    header_cols = "n / E / WR / Sum / MaxDD"
    lines = [f"| حالت | {label_a} ({header_cols}) |" + (f" {label_b} ({header_cols}) |" if label_b else ""),
             "|---|---|" + ("---|" if label_b else "")]
    raw_a = _equity_stats(series_a, cost_r=0.0)
    cost_a = _equity_stats(series_a, cost_r=EXEC_COST_R)
    if label_b:
        raw_b = _equity_stats(series_b, cost_r=0.0)
        cost_b = _equity_stats(series_b, cost_r=EXEC_COST_R)
        lines.append(_fmt_row("خام (بدونِ هزینه)", raw_a, raw_b))
        lines.append(_fmt_row(f"با هزینه ({EXEC_COST_R}R/لگ)", cost_a, cost_b))
    else:
        lines.append(_fmt_row("خام (بدونِ هزینه)", raw_a))
        lines.append(_fmt_row(f"با هزینه ({EXEC_COST_R}R/لگ)", cost_a))
    return lines


def analyze_window_duel(df_a, label_a, df_b, label_b):
    """سؤالِ ۱: مقایسه‌ی E/WR/Sum/MaxDD/TTNH دو پنجره رویِ DayNet_R، خام و با-هزینه."""
    lines = [f"### دوئلِ پنجره: {label_a} در برابرِ {label_b}\n"]
    lines += _costed_table_lines(label_a, df_a["DayNet_R"], label_b, df_b["DayNet_R"])
    return "\n".join(lines) + "\n"


def analyze_stop_sweep(sweep_data):
    """سؤالِ ۲: جاروی استاپ {0.5, 0.6, 0.75} رویِ ۲ پنجره‌یِ برتر.

    sweep_data: dict مثلِ {"0900-1000": {50: df, 60: df, 75: df}, "0930-1030": {...}}
    مقدارِ ۷۵ همان DayNet_R موجود در دیتافریمِ اصلیِ آن پنجره است (فایلِ پیش‌فرض، بدونِ پسوند).
    """
    if not sweep_data:
        return (
            "### جاروی استاپ {0.5, 0.6, 0.75}\n\n"
            "**TODO** — فایل‌هایِ `NY_History_<window>_sd50.csv` / `_sd60.csv` داده نشدند. "
            "این‌ها با `InpStopDepthPct=0.50` و `0.60` در NY_DataScript.mq5 (v1.6) تولید می‌شوند؛ "
            "پیش‌فرضِ ۰.۷۵ همان فایلِ اصلیِ پنجره است.\n"
        )
    lines = ["### جاروی استاپ {0.5, 0.6, 0.75}\n",
             "| پنجره | استاپ | n | E خام | E با هزینه | WR | Sum خام | MaxDD |",
             "|---|---|---|---|---|---|---|---|"]
    for window_label, by_sd in sweep_data.items():
        for sd in sorted(by_sd.keys()):
            df = by_sd[sd]
            raw = _equity_stats(df["DayNet_R"])
            cost = _equity_stats(df["DayNet_R"], cost_r=EXEC_COST_R)
            if raw["n"] == 0:
                lines.append(f"| {window_label} | {sd/100:.2f} | 0 | n/a | n/a | n/a | n/a | n/a |")
                continue
            lines.append(f"| {window_label} | {sd/100:.2f} | {raw['n']} | {raw['E']:.3f} | "
                          f"{cost['E']:.3f} | {raw['WR']:.3f} | {raw['Sum']:.3f} | {raw['MaxDD']:.3f} |")
    lines.append("\n> سنجه‌ی دوم طبقِ سند: کیفیتِ منحنی (MaxDD/TTNH)، نه فقط E — قبل از انتخابِ "
                  "استاپِ نهایی هر دو را با هم ببین.\n")
    return "\n".join(lines)


def analyze_reversal_engine(df_0830):
    """سؤالِ ۳: E کاملِ مستقیم+ریورس (فقط پنجره‌ی ۸:۳۰) در برابرِ بهترینِ پنجره‌یِ ساده.

    v1.6: توزیعِ Rev_ExitR روی همه‌ی فعال‌سازی‌ها هم گزارش می‌شود — برایِ سنجشِ فرضیه‌یِ سوگیریِ
    ثبتِ انتخابی (بندِ ۴ دستورِ مدیرِ پروژه؛ نگاه کن به docs/Reversal_15Day_Diagnostic.md).
    """
    direct = _equity_stats(df_0830["DayNet_R"])

    triggered = df_0830[df_0830["Rev_Triggered"] == 1].copy()
    rev_stats_raw  = _equity_stats(triggered["Rev_ExitR"])
    rev_stats_cost = _equity_stats(triggered["Rev_ExitR"], cost_r=EXEC_COST_R)
    rev_stop_rate = float((df_0830["Rev_Outcome"] == "Stop").sum() / max(1, len(triggered))) if len(triggered) else np.nan
    rev_tp_rate   = float((df_0830["Rev_Outcome"] == "TP").sum()   / max(1, len(triggered))) if len(triggered) else np.nan

    # سریِ ترکیبی: R لگِ مستقیم اگر ترید شد، وگرنه R ریورس اگر فعال شد، وگرنه NaN (روزِ کاملاً بی‌ترید).
    combined = df_0830["DayNet_R"].copy()
    combined = combined.fillna(df_0830["Rev_ExitR"])

    # توزیعِ Rev_ExitR رویِ همه‌یِ فعال‌سازی‌ها (نه نمونه‌ی ۱۵روزه‌یِ چشمی) — سطل‌هایِ ساده.
    rex = triggered["Rev_ExitR"].dropna().astype(float)
    buckets = [("<= -0.9 (استاپ)", (rex <= -0.9)), ("(-0.9, 0]", (rex > -0.9) & (rex <= 0)),
               ("(0, 1]", (rex > 0) & (rex <= 1)), ("(1, 2]", (rex > 1) & (rex <= 2)),
               ("> 2 (TP/رانر)", (rex > 2))]
    dist_lines = ["\n**توزیعِ `Rev_ExitR` رویِ همه‌ی فعال‌سازی‌ها (n=" + str(len(rex)) + "):**\n",
                  "| سطل | n | سهم |", "|---|---|---|"]
    for name, mask in buckets:
        n = int(mask.sum())
        pct = 100.0 * n / max(1, len(rex))
        dist_lines.append(f"| {name} | {n} | {pct:.1f}% |")

    lines = ["### موتورِ ریورسِ ۸:۳۰\n",
             f"روزهایِ دارایِ ترید (فقط لگِ مستقیم): n={direct['n']}, E خام={direct['E']:.3f}\n",
             f"نرخِ فعال‌شدنِ ریورس (از کلِ روزهایِ دارایِ شکست): "
             f"{100.0 * len(triggered) / max(1, len(df_0830[df_0830['BreakDir'] != 'None'])):.1f}%\n",
             f"از روزهایِ فعال‌شده: TP={rev_tp_rate * 100:.1f}%  Stop={rev_stop_rate * 100:.1f}%  "
             f"(n={rev_stats_raw['n']}, E ریورسِ تنها — خام={rev_stats_raw['E']:.3f}, "
             f"با هزینه={rev_stats_cost['E']:.3f})\n",
             "\n**E کاملِ مستقیم+ریورس (سؤالِ ۳)، خام و با-هزینه:**\n",
             ]
    lines += _costed_table_lines("مستقیم+ریورس", combined)
    lines.append("")
    lines += dist_lines
    lines.append(
        "\n> **سنجشِ فرضیه‌یِ سوگیریِ ثبتِ انتخابی (بندِ ۴ دستورِ مدیرِ پروژه):** میانگینِ `Rev_ExitR` "
        f"رویِ **همه‌یِ {rev_stats_raw['n']} فعال‌سازیِ** ۱۷ماهه = **{rev_stats_raw['E']:.3f}R**، در "
        "برابرِ **+۰.۷۵R** رویِ نمونه‌ی ۱۵تاییِ چشمیِ محمود (`docs/Reversal_15Day_Diagnostic.md`). "
        "اگر این دو عدد به همین ترتیب فاصله دارند، فرضیه‌یِ پیش‌فرضِ مدیرِ پروژه (چشمی فقط "
        "ریورس‌هایِ چشمگیر را لاگ کرده) تأیید می‌شود — یعنی فرضیه‌یِ ④ (اختلافِ منطقی/باگ) رسماً "
        "ابطال می‌شود؛ سومین ابطالِ تمیزِ پروژه، نتیجه‌ی معتبر است نه شکست.\n"
        "\n> سؤالِ سند: «پیچیدگیِ دولگی می‌ارزد؟» — E ترکیبی را با E مستقیمِ تنها (بالا) و با "
        "بهترینِ پنجره‌ی سادهِ سؤالِ ۱ مقایسه کن.\n")
    return "\n".join(lines)


def analyze_ema_alignment(df, window_label):
    """سؤالِ ۴: E شرطیِ Aligned/خلاف در این پنجره — تأیید یا ردِ وارونگیِ نسبت به توکیو."""
    d = df[df["BreakDir"].isin(["Buy", "Sell"])].copy()
    d = d[d["Bias_Daily"].isin(["Buy", "Sell"])]
    d["Aligned"] = (d["BreakDir"] == d["Bias_Daily"])
    lines = [f"### ناهنجاریِ خلاف‌EMA — {window_label}\n"]
    lines += _costed_table_lines("هم‌جهتِ EMA20/H1", d.loc[d["Aligned"], "DayNet_R"],
                                  "خلافِ EMA20/H1", d.loc[~d["Aligned"], "DayNet_R"])
    lines.append("\nیافته‌ی چشمی: خلاف‌EMA در NY بهتر بود (وارونه‌ی توکیو) — این جدول همان فرضیه را روی "
                 "دیتایِ مکانیکی می‌سنجد.\n")
    return "\n".join(lines)


def analyze_news_breakdown(df, window_label):
    """سؤالِ ۵: سهمِ E از روزهایِ خبری."""
    d = df[df["BreakDir"].isin(["Buy", "Sell"])].copy()
    d["IsNews"] = d["NewsDay"].fillna("").astype(str).str.len() > 0
    news_n = int(d["IsNews"].sum())
    lines = [f"### تفکیکِ NewsDay — {window_label}\n"]
    lines += _costed_table_lines("روزِ خبری (high-impact USD)", d.loc[d["IsNews"], "DayNet_R"],
                                  "غیرِخبری", d.loc[~d["IsNews"], "DayNet_R"])
    if news_n == 0:
        lines.append("\n⚠️ `NewsDay` رویِ این دیتاست همیشه خالی است — یا `InpNewsFromMT5Calendar=false` "
                     "و پلن B هم پر نبوده، یا تقویمِ MT5 عمقِ کافی نداشت (لاگِ اکسپورت را چک کن). "
                     "این جدول تا وقتی NewsDay واقعی پر نشود بی‌معناست.\n")
    else:
        lines.append(f"\nپوشش: {news_n} روزِ خبری از {len(d)} روزِ ترید (`InpNewsFromMT5Calendar`، "
                     "USD/HIGH طبقِ بندِ ۴ دستورِ مدیرِ پروژه).\n")
    return "\n".join(lines)


def analyze_tokyo_comparison(ny_best_series, ny_best_label, tokyo_csv_path):
    """سؤالِ ۶: جدولِ مقایسه‌ی نهایی، هم‌بازه با توکیو — بهترین پیکربندیِ NY در برابرِ توکیو-پایه."""
    if not tokyo_csv_path or not os.path.exists(tokyo_csv_path):
        return ("### مقایسه‌ی نهایی با توکیو\n\n**TODO** — مسیرِ CSVِ توکیو داده نشد یا پیدا نشد "
                "(`--tokyo`). این جدول را با `DayBias_History_XAUUSD.csv`ِ ریپوی RiskManager-EA اجرا کن.\n")
    tokyo = _load(tokyo_csv_path)
    tokyo_r = tokyo["R_Day"].replace("", np.nan)
    lines = ["### مقایسه‌ی نهایی با توکیو (هم‌بازه)\n"]
    lines += _costed_table_lines(f"NY بهترین ({ny_best_label})", ny_best_series, "توکیو-پایه", tokyo_r)
    lines.append("\n> حکمِ پیشنهادی («پیکربندیِ برنده‌ی NY» برایِ ورودِ فازِ ۲) را بعد از این جدول "
                 "و بعد از رسیدنِ دیتایِ کاملِ SpreadLog/NewsDay بنویس — نه زودتر (این نسخه موقت است).\n")
    return "\n".join(lines)


def _load_sweep(args, window0900_path, window0930_path):
    sweep = {}
    specs = [
        ("0900-1000", window0900_path, args.sweep0900_sd50, args.sweep0900_sd60),
        ("0930-1030", window0930_path, args.sweep0930_sd50, args.sweep0930_sd60),
    ]
    for label, sd75_path, sd50_path, sd60_path in specs:
        by_sd = {}
        if sd75_path:
            by_sd[75] = _load(sd75_path, label)
        if sd50_path:
            by_sd[50] = _load(sd50_path, label)
        if sd60_path:
            by_sd[60] = _load(sd60_path, label)
        if len(by_sd) >= 2:  # حداقل دو نقطه برای جارو معنادار است
            sweep[label] = by_sd
    return sweep


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--window0900", help="NY_History_0900-1000.csv (sd75، پیش‌فرض)")
    ap.add_argument("--window0930", help="NY_History_0930-1030.csv (sd75، پیش‌فرض)")
    ap.add_argument("--window0830", help="NY_History_0830-0930.csv")
    ap.add_argument("--sweep0900-sd50", dest="sweep0900_sd50", help="NY_History_0900-1000_sd50.csv")
    ap.add_argument("--sweep0900-sd60", dest="sweep0900_sd60", help="NY_History_0900-1000_sd60.csv")
    ap.add_argument("--sweep0930-sd50", dest="sweep0930_sd50", help="NY_History_0930-1030_sd50.csv")
    ap.add_argument("--sweep0930-sd60", dest="sweep0930_sd60", help="NY_History_0930-1030_sd60.csv")
    ap.add_argument("--tokyo", help="DayBias_History_XAUUSD.csv (برایِ سؤالِ ۶)")
    ap.add_argument("--out", default="NY_Standalone_Report_PRELIM.md")
    args = ap.parse_args()

    if not (args.window0900 and args.window0930):
        raise SystemExit("حداقل --window0900 و --window0930 لازم است (دوئلِ سؤالِ ۱).")

    df0900 = _load(args.window0900, "0900-1000")
    df0930 = _load(args.window0930, "0930-1030")
    df0830 = _load(args.window0830, "0830-0930") if args.window0830 else None

    report = ["# NY_Standalone_Report_PRELIM — فازِ ۱، قدمِ ۳ (موقت)\n",
              "> ⚠️ **موقت — پیش از مدلِ هزینه‌یِ نهایی (اسپرد+کمیسیون+اسلیپیجِ واقعی) و پیش از "
              "NewsDayِ کامل.** هیچ عددی از این نسخه وارد حکمِ نهایی نمی‌شود — طبقِ "
              "`Manager_Decision_20260823.md`. هزینه‌یِ اعمال‌شده: ثابتِ "
              f"{EXEC_COST_R}R به‌ازایِ هر لگِ اجراشده (direct/reversal)؛ اسلیپیجِ واقعی هنوز اعمال "
              "نشده (برآوردِ ممیزیِ ریل: میانه ۰.۰۲۹R / میانگین ۰.۰۷۲R، پنجره‌ی ۸:۳۰-۱۰:۰۰NY "
              "گران‌ترین ساعت — فقط زمینه، نه اعمال‌شده در جدول‌هایِ زیر).\n",
              "> تولیدشده توسطِ tools/analyze_ny.py — طبقِ ترتیبِ سؤال‌هایِ بندِ ۳ سند.\n"]

    report.append(analyze_window_duel(df0900, "0900-1000", df0930, "0930-1030"))
    sweep = _load_sweep(args, args.window0900, args.window0930)
    report.append(analyze_stop_sweep(sweep))
    if df0830 is not None:
        report.append(analyze_reversal_engine(df0830))
        report.append(analyze_ema_alignment(df0830, "0830-0930"))
        report.append(analyze_news_breakdown(df0830, "0830-0930"))
    for df, label in [(df0900, "0900-1000"), (df0930, "0930-1030")]:
        report.append(analyze_ema_alignment(df, label))
        report.append(analyze_news_breakdown(df, label))

    best_series, best_label = df0900["DayNet_R"], "0900-1000"
    alt_stats = _equity_stats(df0930["DayNet_R"])
    best_stats = _equity_stats(df0900["DayNet_R"])
    if not pd.isna(alt_stats["E"]) and (pd.isna(best_stats["E"]) or alt_stats["E"] > best_stats["E"]):
        best_series, best_label = df0930["DayNet_R"], "0930-1030"
    report.append(analyze_tokyo_comparison(best_series, best_label, args.tokyo))

    report.append(
        "\n## فهرستِ تصمیم/ابهامِ بازِ باقی‌مانده برایِ نسخه‌ی نهایی\n\n"
        "1. مدلِ هزینه: جایگزینیِ ۰.۰۶R ثابت با سه‌جزئیِ واقعی (اسپرد از SpreadLog کامل + کمیسیونِ "
        "قراردادِ بروکر + اسلیپیجِ برآوردشده از ممیزیِ ریل، به‌تفکیکِ ساعت/P75/P95).\n"
        "2. NewsDay: تأییدِ عمقِ تاریخیِ تقویمِ MT5 در ترمینالِ Errante (چکِ اسکریپت رویِ "
        "۲۰۲۵-۰۳-۱۷) — اگر ناکافی بود، پلن B (تقویمِ دستی از منابعِ رسمی).\n"
        "3. فرضیه‌یِ سوگیریِ ثبتِ انتخابیِ ریورس: تأییدِ نهایی بعدِ دیدنِ E رویِ همه‌یِ فعال‌سازی‌ها "
        "(بالا) — اگر تأیید شد، فرضیه‌یِ ④ رسماً بسته می‌شود.\n"
        "4. جاروی استاپ: انتخابِ نهایی باید کیفیتِ منحنی (MaxDD/TTNH) را هم لحاظ کند، نه فقط E.\n")

    with open(args.out, "w", encoding="utf-8") as f:
        f.write("\n".join(report))
    print(f"گزارش نوشته شد: {args.out}")


if __name__ == "__main__":
    main()
