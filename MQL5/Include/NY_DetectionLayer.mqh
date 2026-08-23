//+------------------------------------------------------------------+
//|                                          NY_DetectionLayer.mqh   |
//| لایه‌ی تشخیص — تعریف‌های فریزشده‌ی NY Box (سندِ دستورکارِ فازِ ۱،        |
//| Spec_NY_Standalone_v1.md). طبقِ آن سند: باکسِ NY، شکستِ معتبر (بدنه   |
//| ≥۵۰٪، فقط ظرفِ ۶۰ دقیقه پس از بسته‌شدنِ باکس)، ورودِ لیمیت روی لبه      |
//| (اعتبار ۶۰ دقیقه از کلوزِ شکست — پر نشد = روزِ بی‌ترید، تفاوتِ کلیدی با |
//| توکیو)، استاپ = عمقِ ۷۵٪ باکس، TP = ۲باکس، بدونِ BE، موتورِ ریورس        |
//| (اردر استاپ روی لبه‌ی مقابل، لغو در +۱باکسِ لگِ مستقیم).                |
//|                                                                    |
//| rates باید از اولین کندلِ بعد از بسته‌شدنِ باکس تا کندلِ EOD (۲۳:۵۰      |
//| سرور) باشد — ترتیبِ صعودی؛ همان قراردادِ dayRates پروژه‌ی توکیو.        |
//+------------------------------------------------------------------+
#ifndef NY_DETECTIONLAYER_MQH
#define NY_DETECTIONLAYER_MQH

#include "NY_BoxLayer.mqh"

#define NY_VALID_BREAK_WINDOW_SEC   3600   // ۶۰ دقیقه پس از بسته‌شدنِ باکس
#define NY_FILL_WINDOW_SEC          3600   // ۶۰ دقیقه از کلوزِ کندلِ شکست
#define NY_STOP_DEPTH_PCT           0.75   // استاپ = ۷۵٪ ارتفاعِ باکس
#define NY_TP_BOXES                 2.0    // TP = ۲ باکس

//------------------------------------------------------------------
// شکست — بخشِ «شکستِ معتبر» سند.
//------------------------------------------------------------------
struct SNYBreak
{
   bool     found;           // آیا اصلاً کندلی شرطِ بدنه/کلوز را (در هر زمانی از روز) پاس کرد؟
   int      dir;              // +1 Buy، -1 Sell، ۰ = هیچ شکستی کلاً پیدا نشد
   datetime time;             // زمانِ کلوزِ کندلِ شکست (رَوی وقتی که found)
   double   dist;             // فاصله‌ی $ کلوز از لبه (>=۰)
   bool     validWithin60;    // آیا این شکست ظرفِ ۶۰ دقیقه‌ی بعد از بسته‌شدنِ باکس رخ داد؟
};

void NY_ResetBreak(SNYBreak &b)
{
   b.found = false; b.dir = 0; b.time = 0; b.dist = 0; b.validWithin60 = false;
}

// اولین کندلی که شرطِ شکستِ معتبر را پاس می‌کند (در کلِ rates، بدونِ محدودیتِ زمانی) — طبقِ
// یادداشتِ سند: شکستِ دیرتر از ۶۰ دقیقه هم پیدا و ثبت می‌شود (برای تحلیل)، فقط validWithin60=false
// می‌شود و طبقِ تعریف، آن روز برایِ ترید معتبر نیست (BreakDir نهایی = None در CSV).
void NY_DetectBreak(const MqlRates &rates[], int count, double boxHigh, double boxLow,
                     datetime boxCloseInstant, SNYBreak &out)
{
   NY_ResetBreak(out);

   for(int i = 0; i < count; i++)
   {
      double range = rates[i].high - rates[i].low;
      double body  = MathAbs(rates[i].close - rates[i].open);
      bool bodyOk  = (range > 0) && (body >= 0.5 * range);

      if(rates[i].close > boxHigh && rates[i].close > rates[i].open && bodyOk)
      {
         out.found = true; out.dir = 1; out.time = rates[i].time; out.dist = rates[i].close - boxHigh;
         break;
      }
      if(rates[i].close < boxLow && rates[i].close < rates[i].open && bodyOk)
      {
         out.found = true; out.dir = -1; out.time = rates[i].time; out.dist = boxLow - rates[i].close;
         break;
      }
   }

   if(out.found)
      out.validWithin60 = (out.time <= boxCloseInstant + NY_VALID_BREAK_WINDOW_SEC);
}

int NY_FindBarIndex(const MqlRates &rates[], int count, datetime t)
{
   for(int i = 0; i < count; i++)
      if(rates[i].time == t) return(i);
   return(-1);
}

//------------------------------------------------------------------
// پرشدنِ ورودی — «لیمیت روی لبه‌ی شکسته، اعتبار ۶۰ دقیقه از کلوزِ شکست».
// اسکن از کندلِ *بعدِ* کندلِ شکست (breakIdx+1) — همان قراردادِ RetestTouch_Time پروژه‌ی توکیو.
//------------------------------------------------------------------
struct SNYFill
{
   bool     filled;
   datetime time;
};

void NY_DetectFill(const MqlRates &rates[], int count, int breakIdx, double edge, int dir,
                    datetime breakTime, SNYFill &out)
{
   out.filled = false; out.time = 0;
   datetime deadline = breakTime + NY_FILL_WINDOW_SEC;

   for(int i = breakIdx + 1; i < count; i++)
   {
      if(rates[i].time >= deadline) break;
      bool touches = (dir > 0) ? (rates[i].low <= edge) : (rates[i].high >= edge);
      if(touches) { out.filled = true; out.time = rates[i].time; return; }
   }
}

//------------------------------------------------------------------
// نتیجه‌ی عمومیِ یک ترید (مستقیم یا ریورس) — ورودی entryIdx/edge/dir/boxSize مشترک، تا کدِ
// مستقیم/ریورس یکی باشد (طبقِ قیدِ سند: «کدِ موازی ممنوع»).
// استاپ = edge - dir*۰.۷۵*boxSize ($ عقب‌تر از لبه، داخلِ باکس). TP = edge + dir*۲*boxSize.
// هم‌زمانیِ استاپ/TP در یک کندل → محافظه‌کارانه استاپ برنده است (نمی‌توان ترتیبِ درون‌کندلی را از
// OHLC اثبات کرد — همان اصلِ پذیرفته‌شده‌ی LP_CheckLeg پروژه‌ی توکیو).
// MFE/MAE: بیشینه‌ی حرکتِ موافق/مخالف نسبت به لبه (واحدِ باکس)، از entryIdx تا *لحظه‌ی خروج*
// (استاپ/TP، هرکدام زودتر) — نه تا EOD. اگر تا EOD نه استاپ نه TP خورد، تا آخرِ روز ادامه می‌یابد.
// (v1.1: قبلاً بدونِ توجه به خروج تا EOD ادامه می‌یافت؛ طبقِ قدمِ ۲ با ground truth جور درنمی‌آمد —
// محمود در پاسِ چشمی بعدِ رسیدنِ روز به نتیجه دیگر آن روز را دنبال نمی‌کرده. نگاه کن به پایینِ حلقه.)
//------------------------------------------------------------------
struct SNYTradeOutcome
{
   bool     hasData;
   double   mfeBoxes;
   double   maeBoxes;
   bool     stopHit;
   bool     tpHit;
   datetime exitTime;      // ۰ اگر تا EOD نه استاپ نه TP خورد
   double   exitR;         // -1 اگر استاپ، TP_Boxes/۰.۷۵ اگر TP، وگرنه R تا کلوزِ EOD (می‌تواند منفی باشد)
   double   eodBoxesSigned; // فاصله‌ی کلوزِ EOD از لبه، واحدِ باکس، علامت‌دار (مثبت=جهتِ موافق)
};

void NY_ResetOutcome(SNYTradeOutcome &o)
{
   o.hasData = false;
   o.mfeBoxes = 0; o.maeBoxes = 0;
   o.stopHit = false; o.tpHit = false;
   o.exitTime = 0; o.exitR = 0; o.eodBoxesSigned = 0;
}

void NY_ComputeTradeOutcome(const MqlRates &rates[], int count, int entryIdx, double edge, int dir,
                             double boxSize, SNYTradeOutcome &out)
{
   NY_ResetOutcome(out);
   if(entryIdx < 0 || entryIdx >= count || boxSize <= 0) return;
   out.hasData = true;

   double stopLevel = edge - dir * NY_STOP_DEPTH_PCT * boxSize;
   double tpLevel   = edge + dir * NY_TP_BOXES * boxSize;
   bool exitDetermined = false;

   for(int i = entryIdx; i < count; i++)
   {
      double favExc = (dir > 0) ? (rates[i].high - edge) : (edge - rates[i].low);
      double advExc = (dir > 0) ? (edge - rates[i].low) : (rates[i].high - edge);
      if(favExc > 0 && favExc / boxSize > out.mfeBoxes) out.mfeBoxes = favExc / boxSize;
      if(advExc > 0 && advExc / boxSize > out.maeBoxes) out.maeBoxes = advExc / boxSize;

      if(!exitDetermined)
      {
         bool stopHere = (dir > 0) ? (rates[i].low  <= stopLevel) : (rates[i].high >= stopLevel);
         bool tpHere   = (dir > 0) ? (rates[i].high >= tpLevel)   : (rates[i].low  <= tpLevel);
         if(stopHere)
         {
            out.stopHit = true; out.exitTime = rates[i].time;
            out.exitR = -1.0;
            exitDetermined = true;
         }
         else if(tpHere)
         {
            out.tpHit = true; out.exitTime = rates[i].time;
            out.exitR = NY_TP_BOXES / NY_STOP_DEPTH_PCT;
            exitDetermined = true;
         }
         // v1.1 (ریشه‌یابیِ قدمِ ۲ — نگاه کن به NY_FrozenDefinitions.md، بخشِ «تصمیمِ پیاده‌سازیِ ۵»):
         // با break از حلقه، MFE/MAE دقیقاً همین‌جا (تا و شاملِ کندلِ خروج) freeze می‌شوند. قبلِ این
         // فیکس، حلقه تا EOD ادامه می‌یافت و حرکتِ قیمت *بعدِ* استاپ/TP را هم در MFE/MAE لحاظ می‌کرد —
         // که با ground truth جور درنمی‌آمد (مثلاً ۲۰۲۶-۰۸-۱۱: MFE_gt=۰.۵ در برابرِ MFE_mechanical=۲.۳۱
         // قبل از فیکس)، چون محمود در پاسِ چشمی بعدِ رسیدنِ روز به نتیجه (استاپ/TP) دیگر ادامه‌ی
         // چارت را برایِ آن روز نگاه نمی‌کرده.
         if(exitDetermined) break;
      }
   }

   double eodClose = rates[count - 1].close;
   double eodSigned = (dir > 0) ? (eodClose - edge) : (edge - eodClose);
   out.eodBoxesSigned = eodSigned / boxSize;

   if(!exitDetermined)
      out.exitR = eodSigned / (NY_STOP_DEPTH_PCT * boxSize);
}

//------------------------------------------------------------------
// موتورِ ریورس (فقط برایِ مطالعه‌ی ۸:۳۰، طبقِ سند — اما مکانیزم مستقل از پنجره است و برایِ هر سه
// قابلِ محاسبه می‌ماند تا کدِ موازی نداشته باشیم؛ تحلیلِ قدمِ ۳ فقط برایِ ۸:۳۰ گزارشش می‌کند).
// اردرِ استاپ رویِ لبه‌ی مقابل؛ لغو در +۱باکسِ لگِ مستقیم (اگر لگِ مستقیم زودتر از لمسِ لبه‌ی مقابل
// به +۱باکس برسد). هم‌زمانی در یک کندل → لغو برنده است (لگِ مستقیمِ رسیده به هدف، محافظه‌کارانه
// اولویت دارد بر بازشدنِ اردرِ ریورس).
//------------------------------------------------------------------
struct SNYReversal
{
   bool            triggered;
   bool            cancelled;         // +۱باکسِ لگِ مستقیم زودتر رسید
   datetime        triggerTime;
   SNYTradeOutcome outcome;           // فقط اگر triggered
   double          revMFEBoxes;       // ستونِ Rev_MFE_Boxes: اگر لگِ ریورس هم استاپ خورد، منفیِ MAE آن (طبقِ یادداشتِ برگه‌ی چشمی)
   string          outcomeLabel;      // TP / Stop / EOD / Cancelled / NeverTriggered
};

void NY_ResetReversal(SNYReversal &r)
{
   r.triggered = false; r.cancelled = false; r.triggerTime = 0;
   NY_ResetOutcome(r.outcome);
   r.revMFEBoxes = 0; r.outcomeLabel = "NeverTriggered";
}

void NY_ComputeReversal(const MqlRates &rates[], int count, int breakIdx, int dir,
                         double edge, double oppEdge, double boxSize, SNYReversal &out)
{
   NY_ResetReversal(out);
   if(boxSize <= 0) return;

   double target1 = edge + dir * 1.0 * boxSize; // +۱باکسِ لگِ مستقیم = لغوِ ریورس
   int triggerIdx = -1;

   for(int i = breakIdx + 1; i < count; i++)
   {
      bool cancelHere  = (dir > 0) ? (rates[i].high >= target1) : (rates[i].low  <= target1);
      bool triggerHere = (dir > 0) ? (rates[i].low  <= oppEdge) : (rates[i].high >= oppEdge);

      if(cancelHere) { out.cancelled = true; out.outcomeLabel = "Cancelled"; return; }
      if(triggerHere) { out.triggered = true; out.triggerTime = rates[i].time; triggerIdx = i; break; }
   }

   if(!out.triggered) { out.outcomeLabel = "NeverTriggered"; return; }

   int dir2 = -dir;
   NY_ComputeTradeOutcome(rates, count, triggerIdx, oppEdge, dir2, boxSize, out.outcome);

   if(out.outcome.stopHit)
   {
      out.revMFEBoxes = -out.outcome.maeBoxes;   // منفی = لگِ ریورس هم استاپ خورد
      out.outcomeLabel = "Stop";
   }
   else if(out.outcome.tpHit)
   {
      out.revMFEBoxes = out.outcome.mfeBoxes;
      out.outcomeLabel = "TP";
   }
   else
   {
      out.revMFEBoxes = out.outcome.mfeBoxes;
      out.outcomeLabel = "EOD";
   }
}

#endif // NY_DETECTIONLAYER_MQH
