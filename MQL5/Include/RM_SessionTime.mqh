//+------------------------------------------------------------------+
//|                                              RM_SessionTime.mqh   |
//|  ماژولِ زمانِ سشن — تک‌منبعِ مشترک بینِ RiskManager EA و Executive   |
//|  Hub. (فایلِ canonical: نسخه‌ی byte-identical در هر دو پوشه قرار     |
//|  می‌گیرد. فقط این نسخه ویرایش می‌شود و به پوشه‌ی دیگر کپی می‌شود.)    |
//|                                                                    |
//|  چرا وجود دارد: قبلاً سه پیاده‌سازیِ تقریباً یکسانِ NY->UTC->server   |
//|  (Session Windows، Session Level، Hub/SOB/NY Edge) داشتیم که هم     |
//|  تکراری بودند هم هر کدام یک باگِ مشترک داشتند. اینجا یک‌بار، درست.   |
//|                                                                    |
//|  دو تضمینِ اصلی:                                                    |
//|   ۱) DSTِ *همان روزِ* هدف (نه امروز) — بازه‌ی تاریخی از مرزِ مارس/     |
//|      نوامبر رد می‌شود، پس هر روز با DSTِ خودش محاسبه می‌شود.          |
//|   ۲) آفستِ سرور->UTC *پایدار*: فقط از تیکِ تازه کالیبره، در یک       |
//|      GlobalVariable ذخیره (تا ری‌لودِ اندیکاتور/سوییچِ تایم‌فریم و     |
//|      سکوتِ تیک/آخرِ هفته آن را خراب نکند). نتیجه: بازمحاسبه‌ی روزِ     |
//|      بسته همیشه همان باکس را می‌دهد → immutable، بدونِ تکیه به حافظه. |
//|                                                                    |
//|  بروکر-مستقل: آفست زنده از همین بروکر خوانده می‌شود، هیچ عددِ ثابتی   |
//|  hardcode نشده.                                                    |
//+------------------------------------------------------------------+
#ifndef RM_SESSIONTIME_MQH
#define RM_SESSIONTIME_MQH

// ورودیِ اختیاریِ override برای آفستِ سرور->UTC (دقیقه). 99999 = خودکار (پیش‌فرض).
// فقط برای حالتِ نادری که کالیبراسیونِ خودکار در دسترس نیست (مثلاً بعضی تسترها که
// TimeGMT()==TimeCurrent() برمی‌گردانند و GlobalVariable هم به تستر منتقل نشده).
// در حالتِ عادی هیچ‌وقت لازم به تنظیم نیست.
input int InpServerUtcOffsetMin = 99999;   // Server->UTC offset (min); 99999 = auto

// نامِ GlobalVariable برای پایدارسازیِ آفست + زمانِ تیکی که باهاش کالیبره شد.
#define ST_GV_OFFSET_KEY "RM_SrvUtcOffsetSec"
#define ST_GV_TICK_KEY   "RM_SrvUtcOffsetTick"

//+------------------------------------------------------------------+
//| پورتِ MT5: TimeYear/TimeMonth/TimeDay/TimeDayOfWeek فقط در MQL4     |
//| وجود دارند؛ در MQL5 معادلِ آن‌ها از طریقِ MqlDateTime ساخته می‌شود.   |
//| الگوریتمِ فراخوانی‌کننده‌ها دست‌نخورده می‌ماند.                        |
//+------------------------------------------------------------------+
int ST_TimeYear(datetime t)      { MqlDateTime s; TimeToStruct(t, s); return(s.year); }
int ST_TimeMonth(datetime t)     { MqlDateTime s; TimeToStruct(t, s); return(s.mon); }
int ST_TimeDay(datetime t)       { MqlDateTime s; TimeToStruct(t, s); return(s.day); }
int ST_TimeDayOfWeek(datetime t) { MqlDateTime s; TimeToStruct(t, s); return((int)s.day_of_week); }

//+------------------------------------------------------------------+
//| قاعده‌ی رسمیِ US DST — یکسان در هر سه پیاده‌سازیِ قبلی (تأیید‌شده).    |
//| شروع: دومین یکشنبه‌ی مارس 07:00 UTC | پایان: اولین یکشنبه‌ی نوامبر    |
//| 06:00 UTC. utcTime باید دور از خودِ لبه‌ی نیمه‌شب باشد (ورودی معمولاً |
//| «ظهرِ همان روز» است) تا اعوجاجِ لبه اثر نگذارد.                      |
//+------------------------------------------------------------------+
bool ST_IsUSDST(datetime utcTime)
{
   int y = ST_TimeYear(utcTime);
   datetime marchFirst = StringToTime(IntegerToString(y) + ".03.01 00:00");
   int dowM = ST_TimeDayOfWeek(marchFirst);           // 0=Sunday..6=Saturday
   int firstSunM  = (dowM == 0) ? 1 : (8 - dowM);     // اولین یکشنبه‌ی مارس
   int secondSunM = firstSunM + 7;                    // دومین یکشنبه‌ی مارس
   datetime dstStart = StringToTime(IntegerToString(y) + ".03." + IntegerToString(secondSunM) + " 07:00");

   datetime novFirst = StringToTime(IntegerToString(y) + ".11.01 00:00");
   int dowN = ST_TimeDayOfWeek(novFirst);
   int firstSunN  = (dowN == 0) ? 1 : (8 - dowN);     // اولین یکشنبه‌ی نوامبر
   datetime dstEnd = StringToTime(IntegerToString(y) + ".11." + IntegerToString(firstSunN) + " 06:00");

   return(utcTime >= dstStart && utcTime < dstEnd);
}

//+------------------------------------------------------------------+
//| تاریخِ تقویمیِ نیویورک برای daysAgo روز قبل از امروز.                |
//| daysAgo منفی = آینده (امروز/فردا) — عمداً پشتیبانی می‌شود چون بعضی   |
//| ابزارها باکسِ «هنوز شروع‌نشده» را هم از قبل می‌سازند.                 |
//| DST برای «الان» فقط جهتِ یافتنِ روزِ تقویمیِ درستِ نیویورک استفاده     |
//| می‌شود؛ محاسبه‌ی خودِ بازه پایین‌تر با DSTِ همان روز انجام می‌شود.     |
//+------------------------------------------------------------------+
void ST_GetNYCalendarDate(int daysAgo, int &y, int &m, int &d)
{
   datetime nowUTC = TimeGMT();
   bool nowDst = ST_IsUSDST(nowUTC);
   int  nowNyOffSec = nowDst ? (-4 * 3600) : (-5 * 3600);
   datetime nowNY   = nowUTC + nowNyOffSec;
   datetime targetNY = nowNY - ((datetime)daysAgo) * 86400;
   y = ST_TimeYear(targetNY);
   m = ST_TimeMonth(targetNY);
   d = ST_TimeDay(targetNY);
}

//+------------------------------------------------------------------+
//| آفستِ سرور->UTC (ثانیه)، پایدار و بروکر-مستقل.                       |
//|  - فقط از تیکِ تازه (TimeCurrent جلو رفته) کالیبره می‌شود؛ سکوتِ تیک |
//|    (آخرِ هفته/قطعی) هیچ‌وقت خرابش نمی‌کند.                            |
//|  - مقدارِ معتبر در GlobalVariable ذخیره می‌شود تا ری‌لودِ اندیکاتور   |
//|    (سوییچِ تایم‌فریم) و سکوتِ تیک آن را از دست ندهند.                 |
//|  - راوِ ۰ نادیده گرفته می‌شود: یا بروکر واقعاً UTC است (آن‌وقت پیش‌   |
//|    فرضِ ۰ درست است)، یا محیطی است که TimeGMT==TimeCurrent می‌دهد     |
//|    (مثلِ بعضی تسترها) که باید به مقدارِ ذخیره‌شده/ورودی تکیه کنیم.    |
//+------------------------------------------------------------------+
datetime g_stLastTick   = 0;
int      g_stOffsetSec  = 0;
bool     g_stHaveOffset = false;
bool     g_stLoadedGV   = false;

int ST_ServerOffsetSec()
{
   // (۰) override دستی (نادر) بالاترین اولویت
   if(InpServerUtcOffsetMin != 99999)
      return(InpServerUtcOffsetMin * 60);

   // (۱) یک‌بار در هر اجرا، مقدارِ ذخیره‌شده (آفست + زمانِ تیکِ کالیبراسیون) را از GV بخوان.
   //     زمانِ تیک هم پایدار می‌شود تا بعد از ری‌لودِ اندیکاتور بدانیم آخرین کالیبراسیون
   //     روی کدام تیک بوده - وگرنه اولین فراخوانیِ بعد از ری‌لود، تیکِ فریزشده را «تازه»
   //     فرض می‌کرد و drift را می‌پذیرفت.
   if(!g_stLoadedGV)
   {
      g_stLoadedGV = true;
      if(GlobalVariableCheck(ST_GV_OFFSET_KEY))
      {
         // گِرد به نزدیک‌ترین دقیقه - اگر GV از نسخه‌ی قبل مقدارِ گِردنشده (مثلِ 10799) داشت.
         g_stOffsetSec  = (int)(MathRound(GlobalVariableGet(ST_GV_OFFSET_KEY) / 60.0) * 60.0);
         g_stHaveOffset = true;
      }
      if(GlobalVariableCheck(ST_GV_TICK_KEY))
         g_stLastTick = (datetime)GlobalVariableGet(ST_GV_TICK_KEY);
   }

   // (۲) فقط وقتی ساعتِ سرور واقعاً *جلو* رفته دوباره کالیبره کن.
   //     v3 (ClaudeCode_FixList_DayBias_v3.md، بندِ ۳-الف): منبعِ کالیبراسیون از TimeCurrent()
   //     به TimeTradeServer() تغییر کرد. TimeCurrent() آخرین زمانِ تیکِ *دریافت‌شده* را می‌دهد -
   //     برایِ یک اسکریپتِ یک‌باره (نه EA/اندیکاتورِ زنده)، اگر آخرین تیکِ ترمینال قدیمی باشد
   //     (مثلاً اسکریپت آخرِ هفته یا مدتی بعدِ آخرین حرکتِ قیمت اجرا شود)، TimeCurrent() یک
   //     زمانِ گذشته برمی‌گرداند درحالی‌که TimeGMT() زمانِ واقعیِ الان است - تفاضل‌شان دیگر
   //     آفستِ سرور نیست، بلکه آفست‌بعلاوه‌یِ فاصله‌ی رکودِ تیک است، که باکس را چند دقیقه/ساعت
   //     جابجا می‌کند (دقیقاً همان علامتِ گزارش‌شده: باکسِ ۲۰۲۶-۰۸-۱۱ چند دلار خطا). TimeTradeServer()
   //     ساعتِ زنده‌ی سرور است (heartbeat، نه وابسته به رسیدنِ تیکِ قیمت)، پس این مشکل را ندارد.
   //     تابعِ TimeTradeServer فقط در MQL5 هست؛ این فایل در این ریپو همان نسخه‌ی پورت‌شده‌ی MT5 است.
   datetime tc = TimeTradeServer();
   if(tc > g_stLastTick)
   {
      int raw = (int)(tc - TimeGMT());
      if(raw != 0 && MathAbs(raw) <= 14 * 3600)   // آفستِ منطقیِ تایم‌زون (۰ = تسترِ TimeGMT==TimeCurrent)
      {
         // v78.1 (فیکس ریشه‌ای - مشاهده‌ی Mahmoud روی حسابِ واقعی): جیترِ ۱ ثانیه‌ای (raw گاهی
         // 10799 گاهی 10800، بسته به زمانِ زیرثانیه‌ی تیک) باعث می‌شد boxStart روی 02:59:59
         // بیفتد - داخلِ کندلِ M5ِ *قبلی* - و iBarShift یک کندل زودتر بگیرد → لبه‌ی ۵ دقیقه‌ایِ
         // جابه‌جا و فلیپِ High/Low (22<->25). آفستِ هر بروکری مضربِ دقیقه است، پس به نزدیک‌ترین
         // دقیقه گِرد می‌کنیم تا boxStart همیشه دقیقاً روی مرزِ کندل بنشیند.
         raw = (int)(MathRound((double)raw / 60.0) * 60.0);
         g_stOffsetSec  = raw;
         g_stHaveOffset = true;
         g_stLastTick   = tc;
         GlobalVariableSet(ST_GV_OFFSET_KEY, (double)raw);
         GlobalVariableSet(ST_GV_TICK_KEY,   (double)tc);
      }
   }

   // (۳) آخرین چاره: ۰ (بروکرِ UTC یا هنوز-کالیبره‌نشده)
   return(g_stHaveOffset ? g_stOffsetSec : 0);
}

//+------------------------------------------------------------------+
//| یک روزِ تقویمیِ مشخصِ نیویورک (y/m/d) + ساعت:دقیقه‌ی شروع/پایان (به   |
//| وقتِ نیویورک) -> بازه‌ی معادل به وقتِ سرور. کاملاً قطعی برای یک       |
//| ورودیِ ثابت (DSTِ همان روز + آفستِ پایدار) → مبنای immutable.        |
//| اگر end<=start یعنی سشن از نیمه‌شبِ نیویورک رد می‌شود (مثلِ توکیو)،   |
//| یک روز به پایان اضافه می‌شود.                                       |
//+------------------------------------------------------------------+
void ST_ComputeSessionServerTime(int y, int m, int d,
                                 int nyStartH, int nyStartM, int nyEndH, int nyEndM,
                                 datetime &outStart, datetime &outEnd)
{
   datetime nyMidnightRaw = StringToTime(StringFormat("%04d.%02d.%02d 00:00", y, m, d));
   bool dst = ST_IsUSDST(nyMidnightRaw + 12 * 3600);   // چک در «ظهرِ» همان روز - دور از لبه‌ی نیمه‌شب
   int nyOffsetSec = dst ? (-4 * 3600) : (-5 * 3600);  // EDT=-4, EST=-5

   datetime nyStartRaw = nyMidnightRaw + nyStartH * 3600 + nyStartM * 60;
   datetime nyEndRaw   = nyMidnightRaw + nyEndH   * 3600 + nyEndM   * 60;
   if(nyEndRaw <= nyStartRaw) nyEndRaw += 86400;       // عبور از نیمه‌شبِ نیویورک

   // UTC = NY - nyOffsetSec (nyOffsetSec منفی است، پس عملاً +۴/+۵ ساعت)
   datetime utcStartRaw = nyStartRaw - nyOffsetSec;
   datetime utcEndRaw   = nyEndRaw   - nyOffsetSec;

   int off = ST_ServerOffsetSec();
   outStart = utcStartRaw + off;
   outEnd   = utcEndRaw   + off;
}

//+------------------------------------------------------------------+
//| میان‌بر: مستقیماً با daysAgo (ترکیبِ دو تابعِ بالا) - امضایی هم‌شکلِ   |
//| ComputeSessionWindowServerTime/ComputeServerTimeِ قبلی تا جایگزینیِ  |
//| محلِ فراخوانی حداقلی باشد.                                          |
//+------------------------------------------------------------------+
void ST_ComputeSessionByDaysAgo(int daysAgo,
                                int nyStartH, int nyStartM, int nyEndH, int nyEndM,
                                datetime &outStart, datetime &outEnd)
{
   int y, m, d;
   ST_GetNYCalendarDate(daysAgo, y, m, d);
   ST_ComputeSessionServerTime(y, m, d, nyStartH, nyStartM, nyEndH, nyEndM, outStart, outEnd);
}

//+------------------------------------------------------------------+
//| آیا این بازه کاملاً در گذشته (بسته) است؟ برای تصمیمِ «قفل/immutable».|
//| از بیشترین بینِ TimeCurrent و زمانِ آخرین کندلِ چارت استفاده می‌شود   |
//| تا در سکوتِ تیک هم درست بماند.                                       |
//+------------------------------------------------------------------+
bool ST_IsClosedServerTime(datetime serverEnd)
{
   // v3: TimeCurrent() به TimeTradeServer() تغییر کرد - همان دلیلِ ST_ServerOffsetSec()
   // (تیکِ رکودی نباید یک روزِ واقعاً بسته‌شده را «هنوز باز» نشان دهد).
   datetime nowSrv = TimeTradeServer();
   datetime lastBar = iTime(Symbol(), Period(), 0);
   if(lastBar > nowSrv) nowSrv = lastBar;
   return(serverEnd <= nowSrv);
}

#endif // RM_SESSIONTIME_MQH
