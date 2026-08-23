//+------------------------------------------------------------------+
//|                                                NY_BiasLayer.mqh   |
//| لایه‌ی Bias — طبقِ دستورکار NY (بخشِ «بدون فیلتر جهت»): محاسبه‌ی        |
//| Bias_Daily/EMA_Slope فقط log-only است، هیچ اثری روی تصمیمِ ورود/خروج |
//| ندارد — صرفاً برای تحلیلِ آفلاینِ قدمِ ۳ (بندِ ۴: ناهنجاریِ خلاف‌EMA).   |
//|                                                                    |
//| تعریف (از یادداشتِ برگه‌ی بکتستِ چشمی): «کندلِ بسته‌یِ H1 در برابرِ      |
//| EMA20 در لحظه‌ی اپنِ همین باکس» — یعنی آخرین کندلِ H1ی که تا لحظه‌ی      |
//| بازشدنِ باکس کاملاً بسته شده، کلوزش را با EMA20ِ همان کندل مقایسه      |
//| می‌کنیم: کلوز > EMA20 → Buy (بایاسِ صعودی)، کلوز < EMA20 → Sell.       |
//|                                                                    |
//| EMA_Slope: شیبِ خودِ EMA20 (نه قیمت) بینِ همان کندلِ H1 و N کندلِ قبل‌تر  |
//| — برای تشخیصِ اینکه EMA در حالِ صعود/نزول است یا تخت (مستقل از رابطه‌ی |
//| قیمت-EMA بالا).                                                     |
//|                                                                    |
//| مستقل از DetectionLayer/CsvWriter (مثلِ BoxLayer)؛ قابلِ استفاده در    |
//| پروژه‌های دیگر.                                                      |
//+------------------------------------------------------------------+
#ifndef NY_BIASLAYER_MQH
#define NY_BIASLAYER_MQH

#define BIAS_EMA_PERIOD       20
#define BIAS_SLOPE_LOOKBACK   3     // چند کندلِ H1 قبل‌تر برایِ سنجشِ شیبِ EMA (~۳ ساعت)
#define BIAS_FLAT_EPS         0.0   // آستانه‌ی تخت‌بودنِ شیب (واحدِ قیمت)؛ ۰ = هر تغییرِ غیرصفر جهت‌دار است

// شاخصِ (shift) آخرین کندلِ H1ی که تا لحظه‌ی atTime کاملاً بسته شده — طبقِ قاعده‌یِ استانداردِ
// MQL5: iBarShift(atTime) کندلی را می‌دهد که atTime *داخلِ* آن است (چه کاملاً بسته چه هنوز جاری
// نسبت به atTime)؛ یک واحد جلوتر می‌رویم تا مطمئن شویم کندلِ برگشتی حتماً پیش از atTime بسته شده.
int BIAS_LastClosedH1Shift(string symbol, datetime atTime)
{
   int s = iBarShift(symbol, PERIOD_H1, atTime, false);
   if(s < 0) return(-1);
   return(s + 1);
}

// خروجی: +1=Buy (کلوز>EMA20)، -1=Sell (کلوز<EMA20)، 0=برابر/دیتای ناکافی (نادر).
// ok=false یعنی دیتای H1/EMA کافی نبود (روزهایِ خیلی نزدیکِ ابتدایِ تاریخچه) — ستونِ CSV خالی می‌ماند.
bool BIAS_GetH1CloseVsEMA20(string symbol, datetime atTime, int &dir)
{
   dir = 0;
   int shift = BIAS_LastClosedH1Shift(symbol, atTime);
   if(shift < 0) return(false);

   int handle = iMA(symbol, PERIOD_H1, BIAS_EMA_PERIOD, 0, MODE_EMA, PRICE_CLOSE);
   if(handle == INVALID_HANDLE) return(false);

   double emaBuf[];
   ArraySetAsSeries(emaBuf, true);
   if(CopyBuffer(handle, 0, shift, 1, emaBuf) != 1) return(false);

   double closeVal = iClose(symbol, PERIOD_H1, shift);
   if(closeVal == 0) return(false);

   if(closeVal > emaBuf[0]) dir = 1;
   else if(closeVal < emaBuf[0]) dir = -1;
   else dir = 0;
   return(true);
}

// شیبِ EMA20 بینِ کندلِ بسته‌یِ مرجع و BIAS_SLOPE_LOOKBACK کندلِ قبل‌تر.
// خروجی: +1=صعودی، -1=نزولی، 0=تخت/دیتای ناکافی.
bool BIAS_GetEMA20Slope(string symbol, datetime atTime, int &slopeDir)
{
   slopeDir = 0;
   int shiftNow = BIAS_LastClosedH1Shift(symbol, atTime);
   if(shiftNow < 0) return(false);
   int shiftPrev = shiftNow + BIAS_SLOPE_LOOKBACK;

   int handle = iMA(symbol, PERIOD_H1, BIAS_EMA_PERIOD, 0, MODE_EMA, PRICE_CLOSE);
   if(handle == INVALID_HANDLE) return(false);

   double emaBuf[];
   ArraySetAsSeries(emaBuf, true);
   if(CopyBuffer(handle, 0, shiftNow, shiftPrev - shiftNow + 1, emaBuf) != (shiftPrev - shiftNow + 1))
      return(false);

   double emaNow  = emaBuf[0];
   double emaPrev = emaBuf[shiftPrev - shiftNow];
   double diff = emaNow - emaPrev;

   if(diff > BIAS_FLAT_EPS) slopeDir = 1;
   else if(diff < -BIAS_FLAT_EPS) slopeDir = -1;
   else slopeDir = 0;
   return(true);
}

string BIAS_DirLabel(int dir)
{
   if(dir > 0) return("Buy");
   if(dir < 0) return("Sell");
   return("Flat");
}

#endif // NY_BIASLAYER_MQH
