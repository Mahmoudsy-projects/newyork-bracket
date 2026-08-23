//+------------------------------------------------------------------+
//|                                            NY_DataScript.mq5     |
//| اسکریپتِ فقط-خواندنیِ استخراجِ تاریخچه‌ی NY Box (XAUUSD) — فازِ ۱،       |
//| قدمِ ۱ (Spec_NY_Standalone_v1.md). هیچ اردری ارسال نمی‌شود؛ فقط        |
//| CopyRates + نوشتنِ یک CSV: MQL5/Files/NY_History_<window>.csv       |
//| («window» از InpWindowLabel، مثلِ 0830-0930).                        |
//|                                                                    |
//| پارامتریک روی پنجره‌ی باکس (InpBoxStartH/M..InpBoxEndH/M) طبقِ قیدِ    |
//| سند: «SessionAnchor پارامتریک» — سه بارِ اجرا با سه ورودیِ متفاوت،     |
//| ۸:۳۰-۹:۳۰ / ۹:۰۰-۱۰:۰۰ / ۹:۳۰-۱۰:۳۰، سه CSV جدا تولید می‌کند.          |
//|                                                                    |
//| نسخه‌ی ۱ — نکته‌ی مهم برایِ کاربر پیش از اعتمادِ کاملِ به قدمِ ۲:         |
//| ستونِ DayNet_R دقیقاً طبقِ متنِ فریزشده‌ی سند محاسبه شده (ورودِ لیمیت    |
//| روی لبه، پر نشدن ظرفِ ۶۰ دقیقه = بدونِ ترید = DayNet_R خالی). اما در   |
//| چند ردیفِ نمونه از NY_Box_Backtest_v2.xlsx، Reward_R حتی روی روزهایی  |
//| که ستونِ Retest=No بود هم مقداردار بود — یعنی ممکن است پاسِ چشمیِ       |
//| محمود مدلِ «ورود بلافاصله در کلوزِ شکست» را فرض کرده باشد، نه لیمیتِ    |
//| منتظرِ ریتست. برایِ حلِ این ابهام بدونِ حدسِ کورکورانه، ستونِ تشخیصیِ      |
//| DayNet_R_MarketEntry هم اضافه شده (همان فرضِ ورودِ بلافاصله) — قدمِ ۲    |
//| (compare_ground_truth.py) هر دو را با Reward_R می‌سنجد تا معلوم شود    |
//| کدام مدل با پاسِ چشمی هم‌خوان است. نگاه کن به                          |
//| docs/NY_FrozenDefinitions.md، بخشِ «سؤالِ باز».                        |
//+------------------------------------------------------------------+
#property copyright "newyork-bracket"
#property script_show_inputs
#property strict

#include <NY_BoxLayer.mqh>
#include <NY_BiasLayer.mqh>
#include <NY_DetectionLayer.mqh>
#include <NY_CsvWriter.mqh>

input string InpSymbol       = "XAUUSD";        // نماد (خالی = نمادِ چارتِ جاری)
input string InpWindowLabel  = "0830-0930";     // برچسبِ پنجره — فقط برایِ نامِ فایل/ستونِ Window

input int InpBoxStartH = 8,  InpBoxStartM = 30; // شروعِ باکس، به وقتِ نیویورک
input int InpBoxEndH   = 9,  InpBoxEndM   = 30; // پایانِ باکس، به وقتِ نیویورک

input int InpEODHourServer = 23, InpEODMinServer = 50; // EOD به وقتِ سرور (قیدِ سند: ۲۳:۵۰ سرور)

// اختیاری: فایلِ CSV تقویمِ اقتصادی (در MQL5/Files/) با فرمتِ هر خط "YYYY-MM-DD,EventName" —
// برایِ ستونِ NewsDay (log-only، بدونِ اثر روی هیچ منطقی). خالی = ستونِ NewsDay همیشه خالی می‌ماند.
input string InpNewsCalendarFile = "";

#define NY_MAX_NEWS_ROWS 2000

string g_newsDates[NY_MAX_NEWS_ROWS];
string g_newsEvents[NY_MAX_NEWS_ROWS];
int    g_newsCount = 0;

int g_digits;

//------------------------------------------------------------------
bool EnsureHistoryLoaded(string symbol)
{
   MqlRates rates[];
   for(int attempt = 0; attempt < 50; attempt++)
   {
      int copied = CopyRates(symbol, PERIOD_M5, 0, 10, rates);
      if(copied > 0) return(true);
      Sleep(200);
   }
   return(false);
}

//------------------------------------------------------------------
// تقویمِ اخبار — اختیاری. فرمتِ ورودی: هر خط "YYYY-MM-DD,EventName" (بدونِ هدر). چند رویداد در
// یک روز را در فایلِ ورودی با چند خطِ هم‌تاریخ بدهید؛ اینجا با ";" به هم می‌چسبند.
//------------------------------------------------------------------
void LoadNewsCalendar()
{
   g_newsCount = 0;
   if(InpNewsCalendarFile == "") return;

   int handle = FileOpen(InpNewsCalendarFile, FILE_READ | FILE_TXT | FILE_ANSI);
   if(handle == INVALID_HANDLE)
   {
      PrintFormat("NY_DataScript: فایلِ تقویمِ اخبار '%s' باز نشد (کدِ خطا %d) — ستونِ NewsDay خالی می‌ماند.",
                  InpNewsCalendarFile, GetLastError());
      return;
   }

   while(!FileIsEnding(handle) && g_newsCount < NY_MAX_NEWS_ROWS)
   {
      string line = FileReadString(handle);
      if(StringLen(line) < 10) continue;
      int comma = StringFind(line, ",");
      if(comma <= 0) continue;
      string dateStr = StringSubstr(line, 0, comma);
      string evt      = StringSubstr(line, comma + 1);

      // اگر همین تاریخ قبلاً ثبت شده، رویداد را با ";" اضافه کن (چند خبرِ high-impact در یک روز).
      bool merged = false;
      for(int i = 0; i < g_newsCount; i++)
      {
         if(g_newsDates[i] == dateStr) { g_newsEvents[i] += ";" + evt; merged = true; break; }
      }
      if(!merged)
      {
         g_newsDates[g_newsCount] = dateStr;
         g_newsEvents[g_newsCount] = evt;
         g_newsCount++;
      }
   }
   FileClose(handle);
   PrintFormat("NY_DataScript: %d روزِ خبری از '%s' بارگذاری شد.", g_newsCount, InpNewsCalendarFile);
}

string LookupNewsDay(string dateStr)
{
   for(int i = 0; i < g_newsCount; i++)
      if(g_newsDates[i] == dateStr) return(g_newsEvents[i]);
   return("");
}

//------------------------------------------------------------------
// یک روزِ معاملاتی: باکسِ همان روز (طبقِ InpBoxStartH/M..InpBoxEndH/M) تا EOD (۲۳:۵۰ سرور، همان
// روزِ تقویمیِ سرور که باکس در آن شروع می‌شود). false = روز skip شد.
//------------------------------------------------------------------
bool ProcessOneDay(int handle, string symbol, int daysAgo,
                    int &cntBuy, int &cntSell, int &cntNone, int &cntLate,
                    int &cntFilled, int &cntNotFilled, int &cntRevTrig, int &cntRevCancel,
                    double &sumMFE, double &sumMAE, int &mfeSamples)
{
   SSessionRange box;
   if(!BL_ComputeSessionRange(symbol, daysAgo, InpBoxStartH, InpBoxStartM, InpBoxEndH, InpBoxEndM, true, box))
      return(false);

   datetime boxCloseInstant = box.end + PeriodSeconds(PERIOD_M5);

   // EOD = ۲۳:۵۰ سرور، همان روزِ تقویمیِ سرور که باکس در آن شروع می‌شود (قیدِ سند: EOD به وقتِ سرور،
   // نه NY — برخلافِ باکس/شکست/ورود که همه به وقتِ نیویورک تعریف شده‌اند).
   MqlDateTime boxStartStruct;
   TimeToStruct(box.start, boxStartStruct);
   datetime eodInstant = StringToTime(StringFormat("%04d.%02d.%02d %02d:%02d",
                          boxStartStruct.year, boxStartStruct.mon, boxStartStruct.day,
                          InpEODHourServer, InpEODMinServer));
   if(eodInstant <= boxCloseInstant) return(false); // گاردِ دفاعیِ محض (نباید با پنجره‌های صبحِ NY رخ دهد)

   if(!ST_IsClosedServerTime(eodInstant))
      return(false); // روزِ جاری/آینده — هنوز کامل نشده

   MqlRates dayRates[];
   int count = CopyRates(symbol, PERIOD_M5, boxCloseInstant, eodInstant - 1, dayRates);
   if(count <= 0) return(false);
   if(dayRates[0].time > dayRates[count - 1].time) ArrayReverse(dayRates);

   int y, m, d;
   ST_GetNYCalendarDate(daysAgo, y, m, d);
   string dateStr = StringFormat("%04d-%02d-%02d", y, m, d);

   double boxSize = box.high - box.low;

   SNYBreak brk;
   NY_DetectBreak(dayRates, count, box.high, box.low, eodInstant, brk);

   // --- بایاس (log-only، مستقلِ از نتیجه‌ی شکست) ---
   int biasDir = 0, slopeDir = 0;
   bool biasOk  = BIAS_GetH1CloseVsEMA20(symbol, box.start, biasDir);
   bool slopeOk = BIAS_GetEMA20Slope(symbol, box.start, slopeDir);
   string biasStr  = biasOk  ? BIAS_DirLabel(biasDir)  : "";
   string slopeStr = slopeOk ? BIAS_DirLabel(slopeDir) : "";
   string newsStr  = LookupNewsDay(dateStr);

   string boxStartSrv = CSV_TimeSec(box.start);
   string boxEndSrv    = CSV_TimeSec(box.end);

   // --- روزِ بدونِ شکستِ معتبر (کلاً یا فقط ظرفِ ساعتِ پایانیِ پیش از EOD — v1.3) ---
   bool tradable = brk.found && brk.valid;
   if(!tradable)
   {
      if(!brk.found) cntNone++; else cntLate++;

      string row = dateStr + "," + InpWindowLabel + "," +
         CSV_Num(box.high, g_digits) + "," + CSV_Num(box.low, g_digits) + "," + CSV_Num(boxSize, g_digits) + "," +
         "None" + "," + "" + "," + "" + "," +
         (brk.found ? CSV_Time(brk.time) : "") + "," +   // LateBreakTime فقط اگر شکست ظرفِ ساعتِ پایانیِ پیش از EOD بود
         "" + "," + "" + "," +
         "0.00" + "," + "" + "," + "" + "," + "" + "," + "" + "," + "" + "," +   // MFE=0 طبقِ قراردادِ برگه‌ی چشمی، بقیه خالی
         "" + "," + "" + "," + "" + "," + "NeverTriggered" + "," +
         biasStr + "," + slopeStr + "," + newsStr + "," + boxStartSrv + "," + boxEndSrv;

      FileWriteString(handle, row + "\r\n");
      return(true);
   }

   if(brk.dir > 0) cntBuy++; else cntSell++;

   int breakIdx = NY_FindBarIndex(dayRates, count, brk.time);
   if(breakIdx < 0) return(false); // گاردِ دفاعیِ محض

   double edge    = (brk.dir > 0) ? box.high : box.low;
   double oppEdge = (brk.dir > 0) ? box.low  : box.high;

   SNYFill fill;
   NY_DetectFill(dayRates, count, breakIdx, edge, brk.dir, brk.time, fill);
   if(fill.filled) cntFilled++; else cntNotFilled++;

   // MFE/MAE/EOD_Boxes: همیشه ساختاری از لحظه‌ی شکست (breakIdx) — مستقل از پرشدنِ ورودی، طبقِ
   // قراردادِ برگه‌ی چشمی (MFE حتی روی Retest=No هم پر است).
   SNYTradeOutcome outcomeMarket;
   NY_ComputeTradeOutcome(dayRates, count, breakIdx, edge, brk.dir, boxSize, outcomeMarket);

   double dayNetR = 0, dayNetRPotential = 0; bool haveDayNetR = false;
   if(fill.filled)
   {
      int fillIdx = NY_FindBarIndex(dayRates, count, fill.time);
      SNYTradeOutcome outcomeLimit;
      NY_ComputeTradeOutcome(dayRates, count, fillIdx, edge, brk.dir, boxSize, outcomeLimit);
      dayNetR = outcomeLimit.exitR;
      dayNetRPotential = outcomeLimit.potentialR;
      haveDayNetR = true;
   }

   SNYReversal rev;
   NY_ComputeReversal(dayRates, count, breakIdx, brk.dir, edge, oppEdge, boxSize, rev);
   if(rev.triggered) cntRevTrig++;
   if(rev.cancelled) cntRevCancel++;

   sumMFE += outcomeMarket.mfeBoxes; sumMAE += outcomeMarket.maeBoxes; mfeSamples++;

   string row = dateStr + "," + InpWindowLabel + "," +
      CSV_Num(box.high, g_digits) + "," + CSV_Num(box.low, g_digits) + "," + CSV_Num(boxSize, g_digits) + "," +
      CSV_Dir(brk.dir) + "," + CSV_Time(brk.time) + "," + CSV_Num(brk.dist, g_digits) + "," + "" + "," +
      CSV_Bool(fill.filled) + "," + (fill.filled ? CSV_Time(fill.time) : "") + "," +
      CSV_Num(outcomeMarket.mfeBoxes, 2) + "," + CSV_Num(outcomeMarket.maeBoxes, 2) + "," +
      CSV_Num(outcomeMarket.eodBoxesSigned, 2) + "," +
      (haveDayNetR ? CSV_Num(dayNetR, 3) : "") + "," +
      (haveDayNetR ? CSV_Num(dayNetRPotential, 3) : "") + "," + CSV_Num(outcomeMarket.exitR, 3) + "," +
      CSV_Bool(rev.triggered) + "," +
      (rev.triggered ? CSV_Num(rev.revMFEBoxes, 2) : "") + "," +
      (rev.triggered ? CSV_Num(rev.outcome.exitR, 3) : "") + "," + rev.outcomeLabel + "," +
      biasStr + "," + slopeStr + "," + newsStr + "," + boxStartSrv + "," + boxEndSrv;

   FileWriteString(handle, row + "\r\n");
   return(true);
}

//------------------------------------------------------------------
void OnStart()
{
   string symbol = (InpSymbol == "") ? _Symbol : InpSymbol;
   g_digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);

   if(!EnsureHistoryLoaded(symbol))
   {
      Print("NY_DataScript: تاریخچه‌ی M5 برای ", symbol, " در دسترس نیست.");
      return;
   }

   LoadNewsCalendar();

   string outFile = StringFormat("NY_History_%s.csv", InpWindowLabel);
   int handle = FileOpen(outFile, FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(handle == INVALID_HANDLE)
   {
      Print("NY_DataScript: خطا در بازکردنِ فایلِ خروجی، کد: ", GetLastError());
      return;
   }
   FileWriteString(handle, NY_CSV_HEADER + "\r\n");

   datetime firstDate = (datetime)SeriesInfoInteger(symbol, PERIOD_M5, SERIES_FIRSTDATE);
   int maxDaysAgo = (int)((TimeTradeServer() - firstDate) / 86400) + 3;
   if(maxDaysAgo < 1) maxDaysAgo = 1;

   int processed = 0, skipped = 0;
   int cntBuy = 0, cntSell = 0, cntNone = 0, cntLate = 0;
   int cntFilled = 0, cntNotFilled = 0, cntRevTrig = 0, cntRevCancel = 0;
   double sumMFE = 0, sumMAE = 0;
   int mfeSamples = 0;

   for(int daysAgo = maxDaysAgo; daysAgo >= 1; daysAgo--)
   {
      if(ProcessOneDay(handle, symbol, daysAgo, cntBuy, cntSell, cntNone, cntLate,
                        cntFilled, cntNotFilled, cntRevTrig, cntRevCancel, sumMFE, sumMAE, mfeSamples))
         processed++;
      else
         skipped++;
   }

   FileClose(handle);

   Print("=== NY Box History Export Complete ===");
   PrintFormat("Symbol: %s   Window: %s   Output: %s", symbol, InpWindowLabel, outFile);
   Print("Processed days: ", processed, "   Skipped days: ", skipped);
   PrintFormat("BreakDir -> Buy: %d  Sell: %d  None(no break): %d  None(late break): %d", cntBuy, cntSell, cntNone, cntLate);
   int tradableDays = cntBuy + cntSell;
   if(tradableDays > 0)
      PrintFormat("Fill rate (limit @ edge, 60min): %.1f%% (%d/%d filled)", 100.0 * cntFilled / tradableDays, cntFilled, tradableDays);
   if(mfeSamples > 0)
      PrintFormat("Avg MFE_Boxes: %.2f   Avg MAE_Boxes: %.2f  (n=%d, structural from break)", sumMFE / mfeSamples, sumMAE / mfeSamples, mfeSamples);
   if(tradableDays > 0)
      PrintFormat("Reversal engine -> Triggered: %d (%.1f%%)  Cancelled(+1box first): %d (%.1f%%)",
                  cntRevTrig, 100.0 * cntRevTrig / tradableDays, cntRevCancel, 100.0 * cntRevCancel / tradableDays);
}
