#ifndef RJACOBUS_FADE_RANGE_MQH_
#define RJACOBUS_FADE_RANGE_MQH_

#include "rjacobus.mqh"

int fadeTopOfRange() {
    double priceToSMAdistance = MathAbs(Ask - getFastSma());
    double stop = Bid + 3 * priceToSMAdistance;
    return sellNoChecks(stop, "Sell top of range");
}

int fadeBottomOfRange() {
    double priceToSMAdistance = MathAbs(Bid - getFastSma());
    double stop = Ask - 3 * priceToSMAdistance;
    return buyNoChecks(stop, "Buy bottom of range");
}

void checkRangeFade() {
    static int candlesGoneBy = 0;
    static bool executedFadeShort = false;
    static bool executedFadeLong = false;

    //every 96 15m candles (1 day), allow new breakout trades
    candlesGoneBy = ++candlesGoneBy % 96;

    if (candlesGoneBy == 0) {
        //overflow, reset
        executedFadeShort = false;
        executedFadeLong = false;
        string msg = "Re-allowing range fade trades";
        SendNotification(msg);
        Print(msg);
    }

    Candle candle = newCandle(1); //last candle

    //Sell top of range
    if (!executedFadeShort && candle.low < BuyAbove && candle.close > BuyAbove) {
        int ticket = fadeTopOfRange();
        if (ticket == -1) {
            PrintFormat("fadeTopOfRange failed");
            return;
        }
        executedFadeShort = true;
        string msg = StringFormat("fade top of range: ticket %d", ticket);
        SendNotification(msg);
        Print(msg);
        return;
    }

    //Buy bottom of range
    if (!executedFadeLong && candle.close < SellBelow && candle.high > SellBelow) {
        int ticket = fadeBottomOfRange();
        if (ticket == -1) {
            PrintFormat("fadeBottomOfRange failed");
            return;
        }
        executedFadeLong = true;
        string msg = StringFormat("fade bottom of range: ticket %d", ticket);
        SendNotification(msg);
        Print(msg);
        return;
    }
}

#endif //RJACOBUS_FADE_RANGE_MQH_
