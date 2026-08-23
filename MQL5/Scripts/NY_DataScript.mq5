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
//|                                                                    |
//| v1.6 (دستورِ مدیرِ پروژه، ۲۳ اوت — برایِ اجرایِ قدمِ ۳ی موقت): دو تغییرِ   |
//| ابزاری، بدونِ دست‌زدن به تعریف‌هایِ فریزشده‌یِ v1.5:                       |
//|  ۱) InpStopDepthPct: عمقِ استاپ حالا پارامتریک است (پیش‌فرض ۰.۷۵ =       |
//|     همان فریزشده) — برایِ جاروی سؤالِ ۲ (۰.۵/۰.۶/۰.۷۵) با سه اجرا.       |
//|  ۲) NewsDay پیش‌فرض از تقویمِ اقتصادیِ داخلیِ MT5 پر می‌شود (USD/HIGH)،   |
//|     نه فایلِ خارجی — InpNewsCalendarFile فقط پلن B (دستی) است.          |
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

// v1.6 (دستورِ مدیرِ پروژه، بندِ ۴): ستونِ NewsDay دیگر نیازمندِ فایلِ خارجی نیست — پیش‌فرض از
// تقویمِ اقتصادیِ داخلیِ MT5 (CalendarValueHistory، currency=USD، importance=HIGH) پر می‌شود.
// پلن B (اگر عمقِ تاریخیِ تقویمِ ترمینال کافی نبود): InpNewsCalendarFile را پر کن تا فایلِ دستیِ
// "YYYY-MM-DD,EventName" جایگزین/مکمل شود.
input bool   InpNewsFromMT5Calendar = true;  // true = NewsDay از تقویمِ داخلیِ MT5 پر شود
input string InpNewsCalendarFile    = "";    // پلن B: فایلِ CSV دستی (در MQL5/Files/)

input double InpStopDepthPct = 0.75; // v1.6 (جاروی سؤالِ ۲): عمقِ استاپ، پیش‌فرضِ فریزشده = ۰.۷۵

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
// کمکی: افزودن/ادغامِ یک رویدادِ خبری در آرایه‌ی سراسری (چند خبرِ هم‌تاریخ با ";" به هم می‌چسبند).
//------------------------------------------------------------------
void AddNewsEvent(string dateStr, string evt)
{
   if(g_newsCount >= NY_MAX_NEWS_ROWS) return;
   for(int i = 0; i < g_newsCount; i++)
   {
      if(g_newsDates[i] == dateStr)
      {
         // از تکرارِ همان رویداد (اگر هم پلن B هم تقویمِ MT5 فعال باشند) جلوگیری کن.
         if(StringFind(g_newsEvents[i], evt) < 0) g_newsEvents[i] += ";" + evt;
         return;
      }
   }
   g_newsDates[g_newsCount] = dateStr;
   g_newsEvents[g_newsCount] = evt;
   g_newsCount++;
}

//------------------------------------------------------------------
// تقویمِ اخبار — پلن B، دستی. فرمتِ ورودی: هر خط "YYYY-MM-DD,EventName" (بدونِ هدر). چند رویداد در
// یک روز را در فایلِ ورودی با چند خطِ هم‌تاریخ بدهید.
//------------------------------------------------------------------
void LoadNewsCalendarFromFile()
{
   if(InpNewsCalendarFile == "") return;

   int handle = FileOpen(InpNewsCalendarFile, FILE_READ | FILE_TXT | FILE_ANSI);
   if(handle == INVALID_HANDLE)
   {
      PrintFormat("NY_DataScript: فایلِ تقویمِ اخبار '%s' باز نشد (کدِ خطا %d) — این منبع نادیده گرفته می‌شود.",
                  InpNewsCalendarFile, GetLastError());
      return;
   }

   int loaded = 0;
   while(!FileIsEnding(handle) && g_newsCount < NY_MAX_NEWS_ROWS)
   {
      string line = FileReadString(handle);
      if(StringLen(line) < 10) continue;
      int comma = StringFind(line, ",");
      if(comma <= 0) continue;
      string dateStr = StringSubstr(line, 0, comma);
      string evt      = StringSubstr(line, comma + 1);
      AddNewsEvent(dateStr, evt);
      loaded++;
   }
   FileClose(handle);
   PrintFormat("NY_DataScript: %d ردیفِ خبری از فایلِ دستیِ '%s' بارگذاری شد.", loaded, InpNewsCalendarFile);
}

//------------------------------------------------------------------
// تقویمِ اخبار — پیش‌فرضِ v1.6: تقویمِ اقتصادیِ داخلیِ MT5. رویدادهایِ USD/HIGH بینِ fromTime و
// toTime (وقتِ سرور) را می‌گیرد و بر اساسِ تاریخِ تقویمیِ سرورِ همان رویداد در g_newsDates ثبت
// می‌کند. توجه: زمانِ رویداد در MqlCalendarValue.time طبقِ مستنداتِ MQL5 وقتِ سرور/GMT-پایه است؛
// چون این ستون فقط تشخیصی/log-only است (بدونِ اثر روی هیچ منطقِ ترید)، خطایِ احتمالیِ کوچکِ
// مرزِ روز (اطرافِ نیمه‌شب) قابلِ‌قبول است — طبقِ دستورِ مدیرِ پروژه.
//------------------------------------------------------------------
void LoadNewsCalendarFromMT5(datetime fromTime, datetime toTime)
{
   MqlCalendarValue values[];
   int total = CalendarValueHistory(values, fromTime, toTime, NULL, "USD");
   if(total < 0)
   {
      PrintFormat("NY_DataScript: CalendarValueHistory شکست خورد (کدِ خطا %d) — تقویمِ MT5 نادیده گرفته می‌شود.",
                  GetLastError());
      return;
   }

   int highImpactCount = 0;
   for(int i = 0; i < total && g_newsCount < NY_MAX_NEWS_ROWS; i++)
   {
      MqlCalendarEvent ev;
      if(!CalendarEventById(values[i].event_id, ev)) continue;
      if(ev.importance != CALENDAR_IMPORTANCE_HIGH) continue;

      MqlDateTime dt;
      TimeToStruct(values[i].time, dt);
      string dateStr = StringFormat("%04d-%02d-%02d", dt.year, dt.mon, dt.day);
      AddNewsEvent(dateStr, ev.name);
      highImpactCount++;
   }
   PrintFormat("NY_DataScript: %d رویدادِ USD/HIGH از تقویمِ داخلیِ MT5 بینِ %s و %s بارگذاری شد.",
               highImpactCount, TimeToString(fromTime, TIME_DATE), TimeToString(toTime, TIME_DATE));
}

//------------------------------------------------------------------
// چکِ عمقِ تاریخیِ تقویم — دستورِ مدیرِ پروژه: باید تا ۲۰۲۵-۰۳-۱۷ برسد (شروعِ دیتاستِ ۱۷ماهه).
// اگر نرسید، این پیام به‌وضوح چاپ می‌شود تا محمود به مدیرِ پروژه اطلاع دهد (پلن B: تقویمِ دستی).
//------------------------------------------------------------------
void CheckCalendarDepth()
{
   datetime probeFrom = StringToTime("2025.03.17 00:00");
   datetime probeTo    = StringToTime("2025.03.24 00:00");
   MqlCalendarValue probe[];
   int n = CalendarValueHistory(probe, probeFrom, probeTo, NULL, "USD");
   if(n > 0)
      PrintFormat("NY_DataScript: چکِ عمقِ تقویم OK — %d رویدادِ USD در بازه‌ی ۲۰۲۵-۰۳-۱۷..۲۰۲۵-۰۳-۲۴ پیدا شد.", n);
   else
      Print("NY_DataScript: هشدار — تقویمِ داخلیِ MT5 تا ۲۰۲۵-۰۳-۱۷ عمقِ کافی ندارد (صفر رویداد در آن هفته). ",
            "طبقِ دستورِ مدیرِ پروژه: این را گزارش کن تا پلن B (تقویمِ دستی از منابعِ رسمی) ساخته شود.");
}

//------------------------------------------------------------------
void LoadNewsCalendar(datetime historyFrom, datetime historyTo)
{
   g_newsCount = 0;
   if(InpNewsFromMT5Calendar)
   {
      CheckCalendarDepth();
      LoadNewsCalendarFromMT5(historyFrom, historyTo);
   }
   LoadNewsCalendarFromFile(); // پلن B: مکمل/جایگزینِ دستی، اگر پر شده باشد
   PrintFormat("NY_DataScript: مجموعِ %d روزِ خبری در ستونِ NewsDay ثبت شد.", g_newsCount);
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

   NY_StopDepthPct = InpStopDepthPct; // v1.6: جاروی سؤالِ ۲ — پیش‌فرض ۰.۷۵ (فریزشده)

   datetime firstDate = (datetime)SeriesInfoInteger(symbol, PERIOD_M5, SERIES_FIRSTDATE);
   int maxDaysAgo = (int)((TimeTradeServer() - firstDate) / 86400) + 3;
   if(maxDaysAgo < 1) maxDaysAgo = 1;

   LoadNewsCalendar(firstDate, TimeTradeServer());

   // v1.6: اگر جاروی سؤالِ ۲ در حالِ اجراست (استاپِ غیرِپیش‌فرض)، نامِ فایل را جدا کن تا سه اجرا
   // رویِ هم نوشته نشوند — مثلاً NY_History_0900-1000_sd60.csv برایِ InpStopDepthPct=0.60.
   string outFile = (MathAbs(InpStopDepthPct - 0.75) < 0.0001)
                     ? StringFormat("NY_History_%s.csv", InpWindowLabel)
                     : StringFormat("NY_History_%s_sd%02d.csv", InpWindowLabel, (int)MathRound(InpStopDepthPct * 100));
   int handle = FileOpen(outFile, FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(handle == INVALID_HANDLE)
   {
      Print("NY_DataScript: خطا در بازکردنِ فایلِ خروجی، کد: ", GetLastError());
      return;
   }
   FileWriteString(handle, NY_CSV_HEADER + "\r\n");

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
   PrintFormat("Symbol: %s   Window: %s   StopDepthPct: %.2f   Output: %s", symbol, InpWindowLabel, NY_StopDepthPct, outFile);
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
