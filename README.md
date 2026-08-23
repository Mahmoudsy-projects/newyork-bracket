# NY Box — اسکریپتِ دیتا و اعتبارسنجیِ مکانیکی (MT5 / XAUUSD)

> ## 🏷️ وضعیتِ فعلی: **قدمِ ۲ رویِ آرینتا موفق (BreakDir ~۹۳-۹۵٪) — قدمِ ۳ قفل تا اعتبارسنجیِ هم‌فیدِ XChief**
> سه دورِ اجرایِ واقعی + چند فیکس (v1.1→v1.3، جزئیات پایین) نرخِ تطابقِ `BreakDir` را به ۹۳-۹۵٪
> رساند. مدیرِ پروژه بعدِ بررسیِ گزارش، تعریفِ جدیدِ شکست (v1.3) را تصویب کرد ولی قدمِ ۳ را قفل
> نگه داشت تا: (۱) یک اعتبارسنجیِ دیگر رویِ هم‌فیدِ **XChief** (همان بروکرِ بکتستِ چشمی) انجام شود،
> با هدفِ `DayNet_R≥۸۰٪`؛ (۲) بعدِ آن، آمارِ نهایی رویِ **آرینتا** گزارش شود؛ (۳) یک دیاگنوستیکِ
> ۱۵روزه برایِ موتورِ ریورس؛ (۴) تقویمِ اخبار را خودِ مدیرِ پروژه می‌فرستد؛ (۵) مدلِ هزینه (SpreadLog)
> قبل از هر حکمِ E اعمال شود — این ماژول هنوز در هیچ‌کدام از دو ریپو وجود ندارد. جزئیاتِ کامل:
> [`docs/NY_FrozenDefinitions.md`](docs/NY_FrozenDefinitions.md). **بلاک‌شده رویِ:** اکسپورتِ MT5
> از XChief + منبعِ مدلِ هزینه‌یِ SpreadLog.

استراتژیِ مستقلِ NY، روی همان خطِ تولیدِ پروژه‌یِ توکیو (`RiskManager-EA`). فازِ ۱ (این ریپو) فقط
اسکریپتِ دیتا + تحلیلِ آفلاین است — **هیچ EA ساخته نمی‌شود**. ترکیب/جانشینی با توکیو = فازِ ۲،
بعد از تأییدِ این فاز.

سندِ کاملِ تعریف‌های فریزشده: [`docs/NY_FrozenDefinitions.md`](docs/NY_FrozenDefinitions.md)

## ساختار

```
MQL5/
  Include/
    RM_SessionTime.mqh       کپیِ canonical از RiskManager-EA — زمان‌بندیِ سشن (NY calendar + DST + آفستِ پایدارِ سرور)
    NY_BoxLayer.mqh           پورتِ عینیِ DayBias_BoxLayer.mqh — OHLC یک پنجره‌ی سشن روی M5
    NY_BiasLayer.mqh          EMA20/H1 در اپنِ باکس (log-only، بدونِ اثر روی منطق)
    NY_DetectionLayer.mqh     شکست/ورودِ لیمیت/نتیجه‌ی ترید/موتورِ ریورس — طبقِ تعریف‌های فریزشده
    NY_CsvWriter.mqh          فرمتِ ستون‌ها و هدرِ CSV
  Scripts/
    NY_DataScript.mq5         اسکریپتِ اصلی (OnStart) — پارامتریک رویِ پنجره‌ی باکس
docs/
  NY_FrozenDefinitions.md     تعریف‌های فریزشده + تصمیم‌هایِ پیاده‌سازی + سؤالِ بازِ Retest/DayNet_R
  GroundTruth/
    Box_0830-0930.csv         بکتستِ چشمیِ محمود (۶۰ روز)، از NY_Box_Backtest_v2.xlsx
    Box_0900-1000.csv
    Box_0930-1030.csv
tools/
  compare_ground_truth.py     قدمِ ۲: تطبیقِ خروجیِ مکانیکی با Ground Truth
  analyze_ny.py                قدمِ ۳: تحلیلِ آفلاینِ ۶ سؤالِ سند
```

## نصب و اجرا

1. پوشه‌ی `MQL5/Include/*.mqh` را در `<Data Folder>/MQL5/Include/` کپی کنید.
2. `MQL5/Scripts/NY_DataScript.mq5` را در `<Data Folder>/MQL5/Scripts/` کپی کنید.
3. در MetaEditor کامپایل کنید.
4. یک چارتِ XAUUSD باز کنید، تاریخچه‌ی M5 را تا حدِ ممکن به عقب اسکرول کنید.
5. اسکریپت را **سه بار** روی همان چارت درگ کنید — هر بار با یکی از سه پنجره‌ی کاندید:

   | اجرا | `InpBoxStartH/M` | `InpBoxEndH/M` | `InpWindowLabel` |
   |---|---|---|---|
   | ۱ | 8, 30 | 9, 30 | `0830-0930` |
   | ۲ | 9, 0 | 10, 0 | `0900-1000` |
   | ۳ | 9, 30 | 10, 30 | `0930-1030` |

   (اینپوت‌هایِ دیگر — نماد، EOD، تقویمِ اخبار — دیفالت‌هایشان طبقِ سند است؛ `InpWindowLabel` را
   دقیقاً مطابقِ جدول تنظیم کنید چون در نامِ فایلِ خروجی و ستونِ `Window` استفاده می‌شود.)

6. خروجی: `<Data Folder>/MQL5/Files/NY_History_<window>.csv` — یکی برایِ هر پنجره.

## قدمِ ۲ — صحت‌سنجی با Ground Truth

```bash
python3 tools/compare_ground_truth.py 0830-0930 /path/to/NY_History_0830-0930.csv
python3 tools/compare_ground_truth.py 0900-1000 /path/to/NY_History_0900-1000.csv
python3 tools/compare_ground_truth.py 0930-1030 /path/to/NY_History_0930-1030.csv
```

هر اجرا یک `NY_GroundTruth_Match_Report_<window>.md` کنارِ CSVِ ورودی می‌نویسد: نرخِ تطابقِ
`BreakDir` (انتظار ~۱۰۰٪)، `MFE_Boxes`/`MAE_Boxes` (تلورانسِ ±۰.۱۵ باکس)، و مهم‌تر از همه —
مقایسه‌ی `DayNet_R` (لیمیتِ گیت‌شده) و `DayNet_R_MarketEntry` (ورودِ بلافاصله) با `Reward_R`
برگه‌ی چشمی، برایِ حلِ سؤالِ بازِ توضیح‌داده‌شده در `docs/NY_FrozenDefinitions.md`.

**هر اختلافِ سیستماتیک = توقف و ریشه‌یابی**، قبل از رفتن به قدمِ ۳.

## قدمِ ۳ — تحلیلِ آفلاین (بعد از عبورِ قدمِ ۲، رویِ دیتاستِ کاملِ ۱۷ماهه)

```bash
python3 tools/analyze_ny.py \
    --window0900 NY_History_0900-1000.csv \
    --window0930 NY_History_0930-1030.csv \
    --window0830 NY_History_0830-0930.csv \
    --tokyo /path/to/RiskManager-EA/DayBias_History_XAUUSD.csv \
    --out NY_Standalone_Report.md
```

پنج از شش سؤالِ سند به‌طورِ کامل پیاده‌سازی شده‌اند (دوئلِ پنجره، موتورِ ریورس، ناهنجاریِ خلاف‌EMA،
تفکیکِ NewsDay، مقایسه‌ی نهایی با توکیو). سؤالِ ۲ (جاروی استاپ {۰.۵, ۰.۶, ۰.۷۵}) نیازمندِ اجرایِ
مجددِ اسکریپت با `NY_STOP_DEPTH_PCT` پارامتریک‌شده است — نگاه کن به TODOیِ داخلِ خودِ اسکریپت.

## نکاتِ مهم قبل از استفاده از خروجی

- **این ریپو محیطِ MT5 ندارد**؛ کدِ MQL5 کامپایل/تست نشده و باید در MetaEditor بررسی شود
  (همان محدودیتِ ریپوی توکیو).
- ستون‌هایِ `MFE_Boxes`/`MAE_Boxes`/`EOD_Boxes` **ساختاری‌اند** (از لحظه‌ی شکست، مستقلِ از پرشدنِ
  ورودی) — `DayNet_R` **گیت‌شده با پرشدنِ لیمیت** است (خالی = روزِ بی‌ترید). تفاوتِ این دو عمدی است؛
  جزئیات در `docs/NY_FrozenDefinitions.md`.
- موتورِ ریورس برایِ هر سه پنجره محاسبه می‌شود (کدِ مشترک)، اما طبقِ سند فقط تحلیلِ پنجره‌ی ۸:۳۰
  باید گزارشش کند.
- ستونِ `NewsDay` فقط اگر `InpNewsCalendarFile` پر شده باشد معنادار است؛ فرمتِ فایل: هر خط
  `YYYY-MM-DD,EventName`.
