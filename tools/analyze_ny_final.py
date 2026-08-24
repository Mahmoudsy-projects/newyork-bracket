#!/usr/bin/env python3
"""
قدمِ ۳ — کارهایِ نسخه‌ی نهایی (دستورِ مدیرِ پروژه، ۲۴ اوت، `Manager_Decision_20260824.md`).
مکمّلِ `analyze_ny.py` (که قدمِ ۳ی موقت را ساخت) — این اسکریپت سه کارِ اولِ دستورِ نهایی را
پیاده می‌کند:

  ۱) آزمونِ پایداریِ استاپِ ۰.۵۰ — تقسیمِ ۱۷ماهه به دو نیمه + چهار فصل، جدولِ E/Sum/MaxDD برایِ
     هر سه استاپ در هر زیربازه + معیارِ پذیرشِ فریزشده (هم‌علامتی در هر دو نیمه).
  ۲) مدلِ هزینه‌یِ سه‌جزئی (اسپرد + کمیسیون + اسلیپیج) رویِ پیکربندیِ مرجع (0900-1000/stop 0.50).
     **کمیسیون و P75ِ اسلیپیج هنوز از مدیرِ پروژه/محمود نرسیده — این دو بخشِ جدول TODO می‌مانند
     (بدونِ fabricate کردنِ عدد)**؛ فرمول و اسپرد/میانه/میانگینِ اسلیپیج همین حالا اعمال شده.
  ۳) تفکیکِ NewsDay رویِ پیکربندیِ مرجع + تلاقی با سایزِ باکس (پارکینگ ⑥/⑥ب).

سؤالِ ۴ (ستونِ `BoxClose_Pos`) در MQL5 اضافه شده (`NY_BoxLayer.mqh`/`NY_CsvWriter.mqh`) و نیازمندِ
سه اکسپورتِ تازه است — بعدِ رسیدنشان، تحلیلش هم به همین اسکریپت اضافه می‌شود.

⚠️ **مغایرتِ شناخته‌شده (طبقِ خودِ دستورِ مدیرِ پروژه، بندِ «قیدها»: در صورتِ تناقض، توقف و اعلام):**
TTNH محاسبه‌شده‌یِ اینجا (به‌روزِ تقویمیِ واقعی بینِ دو High جدیدِ متوالیِ equity، رویِ کلِ توالیِ
تقویمی با روزهایِ بی‌ترید=۰) برایِ `0900-1000` تقریباً دقیقاً با اعدادِ مرجعِ لاینِ اصلی جور است
(sd50: ۱۵۳ در برابرِ ۱۵۶؛ sd75: ۲۹۵ در برابرِ ۲۹۶ — اختلافِ ناچیز، احتمالاً مرزبندیِ روزِ آخر).
اما برایِ `0930-1030` جور در نمی‌آید (اینجا: ۱۰۸/sd50، ۲۴۲/sd75-خام؛ لاینِ اصلی: ۳۰۹). دلیلش
پیدا نشد — چند روشِ محاسبه‌ی متفاوت امتحان شد، هیچ‌کدام ۳۰۹ نداد. **طبقِ دستورِ صریحِ مدیرِ پروژه،
این را انتخابِ یک‌طرفه نکردم — پایین با علامتِ ⚠️ گزارش شده، منتظرِ روش/اسکریپتِ دقیقِ لاینِ اصلی.**

استفاده:
    python3 analyze_ny_final.py \
        --sweep0900-sd50 .../NY_History_0900-1000_sd50.csv \
        --sweep0900-sd60 .../NY_History_0900-1000_sd60.csv \
        --sweep0900-sd75 .../NY_History_0900-1000.csv \
        --sweep0930-sd50 .../NY_History_0930-1030_sd50.csv \
        --sweep0930-sd60 .../NY_History_0930-1030_sd60.csv \
        --sweep0930-sd75 .../NY_History_0930-1030.csv \
        --commission-usd-roundtrip <عدد از محمود، اختیاری> \
        --slippage-p75-r <عدد از لاینِ اصلی، اختیاری> \
        --out NY_FinalTasks_1-3.md
"""
import argparse
import numpy as np
import pandas as pd

EXEC_COST_R = 0.06  # همان مقدارِ موقتِ v1.6 — فقط برایِ ردیفِ «مرجع» در جدولِ خلاصه استفاده می‌شود
SPREAD_USD = {"xchief": 0.17, "errante": 0.23}  # میانگینِ اسپرد، پنجره‌یِ باکس، طبقِ SpreadLog ۵روزه
SLIPPAGE_R = {"median": 0.029, "mean": 0.072}   # طبقِ توزیعِ executionaudit (لاینِ اصلی)


def _load(path):
    df = pd.read_csv(path)
    df["Date"] = pd.to_datetime(df["Date"])
    return df.sort_values("Date").reset_index(drop=True)


def _stats_calendar(df, col, cost_r=0.0):
    """E/Sum/MaxDD/TTNH(روزِ تقویمیِ واقعی) رویِ کلِ توالیِ ردیف‌هایِ df (روزِ بی‌ترید=۰)."""
    r = df[col].copy().astype(float)
    traded = r.notna()
    if traded.sum() == 0:
        return dict(n=0, E=np.nan, Sum=np.nan, MaxDD=np.nan, TTNH=np.nan)
    r = r.where(~traded, r - cost_r).fillna(0.0)
    eq = r.cumsum()
    rm = eq.cummax()
    is_high = (eq == rm).values
    idx = np.where(is_high)[0]
    if len(idx) > 1:
        dates = df["Date"].values[idx]
        diffs = np.diff(dates).astype("timedelta64[D]").astype(int)
        ttnh = int(diffs.max())
    else:
        ttnh = 0
    dd = eq - rm
    return dict(n=int(traded.sum()), E=r[traded].mean(), Sum=r.sum(), MaxDD=float(dd.min()), TTNH=ttnh)


# ============================================================ کارِ ۱: آزمونِ پایداریِ استاپ
def analyze_stop_stability(sweep):
    """sweep: {"0900-1000": {50: df, 60: df, 75: df}, "0930-1030": {...}}"""
    lines = ["## کارِ ۱ — آزمونِ پایداریِ استاپِ ۰.۵۰ (پادزهرِ in-sample)\n"]

    verdicts = {}
    for window, by_sd in sweep.items():
        df75 = by_sd[75]
        start, end = df75["Date"].min(), df75["Date"].max()
        mid = pd.Timestamp("2025-12-01")
        periods = [
            ("کلِ بازه", start, end),
            ("نیمه‌ی اول (تا ۲۰۲۵-۱۱-۳۰)", start, pd.Timestamp("2025-11-30")),
            ("نیمه‌ی دوم (از ۲۰۲۵-۱۲-۰۱)", mid, end),
        ]
        span_days = (end - start).days
        q = span_days / 4.0
        for i in range(4):
            qstart = start + pd.Timedelta(days=int(i * q))
            qend = start + pd.Timedelta(days=int((i + 1) * q)) if i < 3 else end
            periods.append((f"فصلِ {i+1} ({qstart.date()}..{qend.date()})", qstart, qend))

        lines.append(f"\n### {window}\n")
        lines.append("| زیربازه | استاپ | n | E خام | Sum خام | MaxDD |")
        lines.append("|---|---|---|---|---|---|")
        e50_by_period, e75_by_period = {}, {}
        for label, p_start, p_end in periods:
            for sd in (50, 60, 75):
                df = by_sd[sd]
                mask = (df["Date"] >= p_start) & (df["Date"] <= p_end)
                sub = df.loc[mask]
                s = _stats_calendar(sub.reset_index(drop=True), "DayNet_R", cost_r=0.0)
                e_str = f"{s['E']:.3f}" if s["n"] else "n/a"
                sum_str = f"{s['Sum']:.2f}" if s["n"] else "n/a"
                dd_str = f"{s['MaxDD']:.2f}" if s["n"] else "n/a"
                lines.append(f"| {label} | {sd/100:.2f} | {s['n']} | {e_str} | {sum_str} | {dd_str} |")
                if sd == 50 and "نیمه" in label:
                    e50_by_period[label] = s["E"]
                if sd == 75 and "نیمه" in label:
                    e75_by_period[label] = s["E"]

        diffs = []
        for label in e50_by_period:
            if not (pd.isna(e50_by_period[label]) or pd.isna(e75_by_period.get(label, np.nan))):
                diffs.append(e50_by_period[label] - e75_by_period[label])
        same_sign = len(diffs) == 2 and (diffs[0] > 0) == (diffs[1] > 0) and diffs[0] != 0
        verdicts[window] = same_sign
        lines.append(f"\n**اختلافِ E(۰.۵۰)-E(۰.۷۵) در دو نیمه:** "
                     f"{', '.join(f'{d:+.3f}' for d in diffs)} — "
                     f"{'هم‌علامت ✅' if same_sign else 'هم‌علامت نیست ❌'}\n")

    all_same_sign = all(verdicts.values())
    lines.append(
        "\n### حکمِ آزمونِ پایداری (معیارِ فریزشده‌ی مدیرِ پروژه)\n\n"
        f"برتریِ استاپِ ۰.۵۰ بر ۰.۷۵ {'در هر دو نیمه‌یِ هر دو پنجره هم‌علامت است ✅' if all_same_sign else 'در هر دو نیمه هم‌علامت نیست ❌'}. "
        f"**نتیجه طبقِ معیارِ فریزشده: استاپِ نهایی = {'۰.۵۰' if all_same_sign else '۰.۷۵ (محافظه‌کار)، و ۰.۵۰ به‌عنوانِ کاندیدِ فوروارد ثبت می‌شود'}.**\n")
    return "\n".join(lines)


# ============================================================ کارِ ۲: مدلِ هزینه‌ی سه‌جزئی
def analyze_cost_scenarios(df_ref, window_label, stop_label, commission_usd_roundtrip, slippage_p75_r):
    """پیکربندیِ مرجع فقط: 0900-1000 / stop 0.50. هزینه به‌ازایِ هر لگ، از رویِ BoxSizeِ همان روز."""
    lines = ["## کارِ ۲ — مدلِ هزینه‌یِ سه‌جزئی رویِ پیکربندیِ مرجع "
             f"({window_label} / stop {stop_label})\n",
             "فرمول: `cost_R(روز) = (spread$ + commission$ + slippage$) / (StopDepthPct × BoxSize$)`؛ "
             "برایِ اسلیپیج از مقدارِ Rِ داده‌شده مستقیم استفاده می‌شود (قبلاً به R تبدیل شده، طبقِ "
             "ممیزیِ ریل).\n"]

    traded = df_ref[df_ref["DayNet_R"].notna()].copy()
    n = len(traded)
    if n == 0:
        lines.append("**داده‌ای برایِ پیکربندیِ مرجع پیدا نشد.**\n")
        return "\n".join(lines)

    broker = "errante"  # پیکربندیِ مرجع رویِ همین دیتاستِ Errante محاسبه شده
    spread_usd = SPREAD_USD[broker]
    stop_pct = 0.50
    spread_r_per_row = spread_usd / (stop_pct * traded["BoxSize"].astype(float))
    commission_r_per_row = (
        (commission_usd_roundtrip / (stop_pct * traded["BoxSize"].astype(float)))
        if commission_usd_roundtrip is not None else None
    )

    lines.append(f"n لگِ اجراشده (فقط لگِ مستقیم؛ ریورس در جدولِ جدا): {n}\n")
    lines.append(f"اسپردِ ثابت (Errante، طبقِ SpreadLog ۵روزه): ${spread_usd} → "
                 f"میانگینِ cost_R اسپرد در این نمونه = {spread_r_per_row.mean():.4f}R\n")

    if commission_usd_roundtrip is None:
        lines.append("**کمیسیون: TODO — هنوز از محمود نرسیده** (بندِ «اطلاعاتِ موردنیاز» دستورِ "
                     "مدیرِ پروژه). جدولِ زیر فقط اسپرد+اسلیپیج را نشان می‌دهد؛ کمیسیون بعداً اضافه می‌شود.\n")
    else:
        lines.append(f"کمیسیون (ورودیِ محمود): ${commission_usd_roundtrip}/ترید → "
                     f"میانگینِ cost_R کمیسیون = {commission_r_per_row.mean():.4f}R\n")

    scenarios = [("میانه‌یِ اسلیپیج (۰.۰۲۹R)", SLIPPAGE_R["median"]),
                 ("میانگینِ اسلیپیج (۰.۰۷۲R)", SLIPPAGE_R["mean"])]
    if slippage_p75_r is not None:
        scenarios.append((f"P75ِ اسلیپیج ({slippage_p75_r}R)", slippage_p75_r))
    else:
        lines.append("**سناریویِ P75ِ اسلیپیج: TODO — عددش هنوز از لاینِ اصلی نرسیده** "
                     "(فقط میانه/میانگین دادند، نه P75؛ اختراع نکردم).\n")

    lines.append("\n| سناریو | cost_R میانگین (اسپرد+اسلیپیج"
                 + ("+کمیسیون" if commission_usd_roundtrip is not None else "") + ") | E پس از هزینه | Sum پس از هزینه |")
    lines.append("|---|---|---|---|")
    raw_e = traded["DayNet_R"].astype(float).mean()
    raw_sum = traded["DayNet_R"].astype(float).sum()
    for name, slip_r in scenarios:
        total_cost_per_row = spread_r_per_row + slip_r
        if commission_r_per_row is not None:
            total_cost_per_row = total_cost_per_row + commission_r_per_row
        adj = traded["DayNet_R"].astype(float) - total_cost_per_row
        lines.append(f"| {name} | {total_cost_per_row.mean():.4f}R | {adj.mean():.4f} | {adj.sum():.2f} |")

    lines.append(f"\nخام (بدونِ هیچ هزینه‌ای، برایِ مرجع): E={raw_e:.4f}  Sum={raw_sum:.2f}\n")

    lines.append(
        "\n**آستانه‌ی مرگ (هزینه‌ای که E را صفر می‌کند):** "
        f"cost_R بحرانی ≈ {raw_e:.4f}R به‌ازایِ هر لگ (میانگینِ فعلی). با اسپردِ Errante به‌تنهایی "
        f"(~{spread_r_per_row.mean():.3f}R) هنوز فاصله هست؛ با افزودنِ میانگینِ اسلیپیج "
        f"({SLIPPAGE_R['mean']}R) مجموع ≈ {spread_r_per_row.mean()+SLIPPAGE_R['mean']:.3f}R — "
        f"{'زیرِ آستانه (E هنوز مثبت)' if spread_r_per_row.mean()+SLIPPAGE_R['mean'] < raw_e else 'بالایِ آستانه (E منفی می‌شود)'}؛ "
        "کمیسیون هنوز اضافه نشده — با آمدنش این حکم باید بازبینی شود.\n")
    return "\n".join(lines)


# ============================================================ کارِ ۳: NewsDay × سایزِ باکس
def analyze_newsday_boxsize(df_ref, window_label, stop_label):
    lines = [f"## کارِ ۳ — تفکیکِ NewsDay رویِ پیکربندیِ مرجع ({window_label} / stop {stop_label})\n"]
    d = df_ref[df_ref["BreakDir"].isin(["Buy", "Sell"])].copy()
    d["IsNews"] = d["NewsDay"].fillna("").astype(str).str.len() > 0

    def stats(sub):
        r = sub["DayNet_R"].dropna().astype(float)
        if len(r) == 0:
            return "n=0"
        return f"n={len(r)}  E={r.mean():.3f}  WR={float((r>0).mean()):.3f}  Sum={r.sum():.2f}"

    lines.append(f"روزِ خبری (USD/HIGH): {stats(d[d['IsNews']])}\n")
    lines.append(f"غیرِخبری: {stats(d[~d['IsNews']])}\n")

    lines.append("\n**تلاقی با سایزِ باکس (پارکینگ ⑥/⑥ب — آیا باکس‌هایِ بزرگ همان روزهایِ خبری‌اند؟):**\n")
    med = d["BoxSize"].median()
    d["BigBox"] = d["BoxSize"] > med
    lines.append(f"سایزِ میانه‌یِ باکس در این پنجره: {med:.2f}$\n")
    lines.append("| گروه | سهمِ روزهایِ خبری | n |")
    lines.append("|---|---|---|")
    for label, mask in [("باکسِ بزرگ (> میانه)", d["BigBox"]), ("باکسِ کوچک (≤ میانه)", ~d["BigBox"])]:
        sub = d[mask]
        news_share = float(sub["IsNews"].mean()) if len(sub) else float("nan")
        lines.append(f"| {label} | {news_share*100:.1f}% | {len(sub)} |")

    corr = d["BoxSize"].astype(float).corr(d["IsNews"].astype(int))
    lines.append(f"\nهمبستگیِ نقطه‌ای‌دوجزئیِ BoxSize و IsNews: {corr:.3f} "
                 f"({'همبستگیِ محسوس' if abs(corr) > 0.2 else 'همبستگیِ ضعیف/ناچیز'} — گزارشی، بدونِ فیلتر.)\n")
    return "\n".join(lines)


def main():
    ap = argparse.ArgumentParser()
    for w in ("0900", "0930"):
        for sd in ("50", "60", "75"):
            ap.add_argument(f"--sweep{w}-sd{sd}", dest=f"sweep{w}_sd{sd}", required=True)
    ap.add_argument("--commission-usd-roundtrip", type=float, default=None)
    ap.add_argument("--slippage-p75-r", type=float, default=None)
    ap.add_argument("--out", default="NY_FinalTasks_1-3.md")
    args = ap.parse_args()

    sweep = {
        "0900-1000": {50: _load(args.sweep0900_sd50), 60: _load(args.sweep0900_sd60), 75: _load(args.sweep0900_sd75)},
        "0930-1030": {50: _load(args.sweep0930_sd50), 60: _load(args.sweep0930_sd60), 75: _load(args.sweep0930_sd75)},
    }

    report = ["# NY_FinalTasks_1-3 — آزمونِ پایداریِ استاپ + مدلِ هزینه + NewsDay×BoxSize\n",
              "> کارهایِ ۱-۳ از `Manager_Decision_20260824.md`. کارِ ۴ (`BoxClose_Pos`) نیازمندِ "
              "اکسپورتِ تازه است — هنوز اینجا نیست.\n"]

    report.append(analyze_stop_stability(sweep))

    ref_df = sweep["0900-1000"][50]
    report.append(analyze_cost_scenarios(ref_df, "0900-1000", "0.50",
                                          args.commission_usd_roundtrip, args.slippage_p75_r))
    report.append(analyze_newsday_boxsize(ref_df, "0900-1000", "0.50"))

    with open(args.out, "w", encoding="utf-8") as f:
        f.write("\n".join(report))
    print(f"گزارش نوشته شد: {args.out}")


if __name__ == "__main__":
    main()
