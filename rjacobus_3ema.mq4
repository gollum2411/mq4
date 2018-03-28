#include <stdlib.mqh>

#include "rjacobus.mqh"

#property copyright "Roberto Jacobus"
#property link      "github.com/gollum2411"
#property version   "1.00"

const int MAGIC = 0x7dc86;

enum direction {
    BUY,
    SELL
};

input int FastEma = 10;
input int MidEma = 20;
input int SlowEma = 50;

//Glacial-slow SMA
const int GlacialSma = 200;

input double    StopToCandleFactor = 1.0;
input double    TPFactor = 2;
input int       MaxSimultaneousOrders = 10;
input double    MinimumLots = 0.01;
input bool      CloseWhenFastMidCross = false;

struct EMAs {
    double fast;
    double mid;
    double slow;
};

EMAs newEMAs(double fast, double mid, double slow) {
    EMAs emas;
    emas.fast = fast;
    emas.mid = mid;
    emas.slow = slow;
    return emas;
}

void buy(double stop, string comment="") {
    double volume = NormalizeDouble(((AccountFreeMargin()/100) * 1) /1000.0,2);
    volume = (volume < MinimumLots ? MinimumLots : volume);
    double target = Bid + TPFactor * MathAbs(Bid - stop);
    if (!isBuyAllowed())
        return;
    buy(comment, MAGIC, stop, target, volume);
}

void sell(double stop, string comment="") {
    double volume = NormalizeDouble(((AccountFreeMargin()/100) * 1) /1000.0,2);
    volume = (volume < MinimumLots ? MinimumLots : volume);
    double target = Ask - TPFactor * (MathAbs(Ask - stop));
    if (!isSellAllowed())
        return;
    sell(comment, MAGIC, stop, target, volume);
}

EMAs getEMAs() {
    return getEMAsShift(0);
}

EMAs getEMAsShift(int shift) {
    double fast = iMA(NULL, 0, FastEma, 0, MODE_EMA, PRICE_CLOSE, shift);
    double mid = iMA(NULL, 0, MidEma, 0, MODE_EMA, PRICE_CLOSE, shift);
    double slow = iMA(NULL, 0, SlowEma, 0, MODE_EMA, PRICE_CLOSE, shift);
    return newEMAs(fast, mid, slow);
}

double getGlacialSma() {
    return iMA(NULL, 0, GlacialSma, 0, MODE_SMA, PRICE_CLOSE, 0);
}

void manageOrders() {
    if (!CloseWhenFastMidCross) {
        return;
    }

    for(int order = 0; order < OrdersTotal(); order++) {
        OrderSelect(order, SELECT_BY_POS);
        if (OrderSymbol() != Symbol() || OrderMagicNumber() != MAGIC) {
            continue;
        }

        EMAs emas = getEMAs();

        if (OrderType() == OP_BUY) {
            if (emas.fast < emas.mid) {
                OrderClose(OrderTicket(), OrderLots(), Bid, 3, Red);
            }
            continue;
        }

        if (emas.fast > emas.mid) {
            OrderClose(OrderTicket(), OrderLots(), Ask, 3, Red);
        }
    }
}

bool isBuyAllowed() {
    double glacial = getGlacialSma();
    EMAs emas = getEMAs();
    return Ask > glacial && emas.fast > glacial &&
           emas.mid > glacial && emas.slow > glacial;
}

bool isSellAllowed() {
    double glacial = getGlacialSma();
    EMAs emas = getEMAs();
    return Bid < glacial && emas.fast < glacial &&
           emas.mid < glacial && emas.slow < glacial;
}

void checkCrosses() {
    EMAs prev = getEMAsShift(1);
    EMAs curr = getEMAsShift(0);
    Candle candle = newCandle(1);
    double spread = Ask - Bid;
    double stop;
    bool fastMidCross, fastSlowCross, midSlowCross;

    //Bullish cases
    {
        stop = Bid - StopToCandleFactor * MathAbs(candle.high - candle.low) - spread;
        fastMidCross = curr.fast > curr.mid && prev.fast < prev.mid;
        fastSlowCross = curr.fast > curr.slow && prev.fast < prev.slow;
        midSlowCross = curr.mid > curr.slow && prev.mid < prev.slow;

        if (fastMidCross || fastSlowCross || midSlowCross) {
            buy(stop, "buy cross");
            return;
        }
    }

    {
        //Bearish cases
        stop = Ask + StopToCandleFactor * MathAbs(candle.high - candle.low) + spread;
        fastMidCross = curr.fast < curr.mid && prev.fast > prev.mid;
        fastSlowCross = curr.fast < curr.slow && prev.fast > prev.slow;
        midSlowCross = curr.mid < curr.slow && prev.mid > prev.slow;

        if (fastMidCross || fastSlowCross || midSlowCross) {
            sell(stop, "sell cross");
            return;
        }
    }
}

void checkPullbacks() {
    EMAs emas = getEMAs();
    Candle candle = newCandle(1);
    if (Volume[0] > 1) {
        return;
    }

    if (emas.fast > emas.mid && emas.mid > emas.slow) {
        if (candle.isBearish)
            return;
        double spread = Ask - Bid;
        double stop = Bid - StopToCandleFactor * MathAbs(candle.high - candle.low) - spread;

        bool supportedByFast = candle.close > emas.fast && candle.low < emas.fast;
        bool supportedByMid = candle.close > emas.mid && candle.low < emas.mid;
        bool supportBySlow = candle.close > emas.slow && candle.low < emas.slow;

        if (supportedByFast) {
            buy(stop, "Buy fast EMA support");
        } else if (supportedByMid) {
            buy(stop, "Buy mid EMA support");
        } else if (supportBySlow) {
            buy(stop, "Buy slow EMA support");
        }

        return;
    }

    if (emas.fast < emas.mid && emas.mid < emas.slow) {
        stop = Ask + StopToCandleFactor * MathAbs(candle.high - candle.low) + spread;

        if (candle.isBullish)
            return;

        bool resistedByFast = candle.close < emas.fast && candle.high > emas.fast;
        bool resistedByMid = candle.close < emas.mid && candle.high > emas.mid;
        bool resistedBySlow = candle.close < emas.slow && candle.high > emas.slow;

        if (resistedByFast) {
            sell(stop, "Sell fast EMA resistance");
        } else if (resistedByMid) {
            sell(stop, "Sell mid EMA resistance");
        } else if (resistedBySlow) {
            sell(stop, "Sell slow EMA resistance");
        }

        return;
    }

}

void OnTick() {
    Comment("rjacobus_3ema " + Symbol());
    //Invalid conditions
    if (FastEma >= MidEma || MidEma >= SlowEma) {
        return;
    }

    if (Volume[0] > 1) {
        return;
    }

    manageOrders();

    if (ordersForSymbol(Symbol()) >= MaxSimultaneousOrders) {
        return;
    }

    checkCrosses();
    checkPullbacks();
}


