//+------------------------------------------------------------------+
//|                                             NY_CsvWriter.mqh     |
//| فرمتِ ستون‌ها و هدرِ CSV برایِ NY_History_<window>.csv (قدمِ ۱ سند).    |
//| عمداً بدونِ FILE_CSV/FileWrite ساخته شده — همان دلیلِ پروژه‌ی توکیو:    |
//| اعشار همیشه «.» بماند، مستقل از لوکیلِ ترمینال.                       |
//+------------------------------------------------------------------+
#ifndef NY_CSVWRITER_MQH
#define NY_CSVWRITER_MQH

string CSV_Num(double v, int digits) { return(DoubleToString(v, digits)); }

string CSV_Time(datetime t)
{
   if(t == 0) return("");
   MqlDateTime s;
   TimeToStruct(t, s);
   return(StringFormat("%04d-%02d-%02d %02d:%02d", s.year, s.mon, s.day, s.hour, s.min));
}

string CSV_TimeSec(datetime t)
{
   if(t == 0) return("");
   MqlDateTime s;
   TimeToStruct(t, s);
   return(StringFormat("%04d-%02d-%02d %02d:%02d:%02d", s.year, s.mon, s.day, s.hour, s.min, s.sec));
}

string CSV_Dir(int dir)
{
   if(dir > 0) return("Buy");
   if(dir < 0) return("Sell");
   return("None");
}

string CSV_Bool(bool b) { return(b ? "1" : "0"); }

// ستون‌هایِ اصلیِ قدمِ ۱ (طبقِ سند: «قرینه‌ی برگه‌ی چشمی») + چند ستونِ تشخیصیِ اضافه (BoxStart/
// EndServer، LateBreakTime، DayNet_R_MarketEntry) — طبقِ همان قراردادِ پروژه‌ی توکیو (v3) که ستون‌های
// تشخیصیِ راستی‌آزماییِ مستقیم را بدونِ اثر روی ستون‌های اصلی اضافه می‌کرد.
// DayNet_R_MarketEntry: فرضیه‌ی جایگزین (ورود بلافاصله در کلوزِ شکست، نه لیمیتِ منتظرِ ریتست) —
// برایِ قدمِ ۲ (تطبیق با Reward_R برگه‌ی چشمی)، چون معلوم نیست مدلِ دقیقِ ورودی که محمود در پاسِ
// چشمی استفاده کرده کدام‌یک از این دو بوده (نگاه کن به docs/NY_FrozenDefinitions.md، بخشِ «سؤالِ باز»).
// DayNet_R_Potential (v1.5): سقفِ MFE-based روزِ ترید — «تا کجا می‌شد رسید» (mfeBoxes/۰.۷۵ برایِ
// روزهایِ نه‌استاپ-نه‌TP)، برایِ سنجش با ستونِ Reward_R برگه‌ی چشمی. DayNet_R خودش (ستونِ رسمی)
// نتیجه‌ی واقعیِ کلوزِ EOD را می‌سنجد؛ این دو مفهومِ مجزا هستند — نگاه کن به NY_FrozenDefinitions.md.
const string NY_CSV_HEADER =
   "Date,Window,BoxHigh,BoxLow,BoxSize,BreakDir,BreakTime,BreakDist,LateBreakTime,"
   "RetestWithin60,FillTime,MFE_Boxes,MAE_Boxes,EOD_Boxes,DayNet_R,DayNet_R_Potential,DayNet_R_MarketEntry,"
   "Rev_Triggered,Rev_MFE,Rev_ExitR,Rev_Outcome,Bias_Daily,EMA_Slope,NewsDay,BoxStart_Server,BoxEnd_Server";

#endif // NY_CSVWRITER_MQH
