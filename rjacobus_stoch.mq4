#include <stdlib.mqh>

#include "rjacobus.mqh"

#property copyright "Roberto Jacobus"
#property link      "github.com/gollum2411"
#property version   "1.00"

const int MAGIC = 0x38f9;

enum direction {
    BUY,
    SELL
};

//Glacial-slow SMA
input const int GlacialSma = 200;

input double    StopToCandleFactor = 1.0;
input double    TPFactor = 2;
input int       MaxSimultaneousOrders = 10;
input double    MinimumLots = 0.01;

void buy(double stop, string comment="") {
    double volume = NormalizeDouble(((AccountFreeMargin()/100) * 1) /1000.0,2);
    volume = (volume < MinimumLots ? MinimumLots : volume);
    double target = Bid + TPFactor * MathAbs(Bid - stop);
    if (!isBuyAllowed()) {
        Print("Buy not allowed");
        return;
    }
    volume = _getVolume(Ask, stop);
    buy(comment, MAGIC, stop, target, volume);
}

void sell(double stop, string comment="") {
    double volume = NormalizeDouble(((AccountFreeMargin()/100) * 1) /1000.0,2);
    volume = (volume < MinimumLots ? MinimumLots : volume);
    double target = Ask - TPFactor * (MathAbs(Ask - stop));
    if (!isSellAllowed()) {
        Print("Sell not allowed");
        return;
    }
    volume = _getVolume(Bid, stop);
    sell(comment, MAGIC, stop, target, volume);
}

double normalizeDigits() {
    if (Digits <= 3) {
        return 0.01;
    }

    if (Digits >= 4) {
        return 0.0001;
    }

    return 0;
}

double _getVolume(double price, double stop) {
    double size = 0;
    double tickValue = MarketInfo(Symbol(), MODE_TICKVALUE);

    if (Digits == 3 || Digits == 5) {
        tickValue = tickValue * 10;
    }

    double stopInPips = MathAbs(price - stop) / normalizeDigits();
    PrintFormat("stopInPips = %f", stopInPips);
    size = AccountBalance() * 0.01 / stopInPips*tickValue * 0.01;
    size = NormalizeDouble(size, 2);
    return size;
}

double getGlacialSma() {
    return iMA(NULL, PERIOD_D1, GlacialSma, 0, MODE_SMA, PRICE_CLOSE, 0);
}

void manageOrders() {
    double k0, d0, k1, d1;

    getStochShift(k0, d0, 0);
    getStochShift(k1, d1, 1);

    for(int order = 0; order < OrdersTotal(); order++) {
        OrderSelect(order, SELECT_BY_POS);
        if (OrderSymbol() != Symbol() || OrderMagicNumber() != MAGIC) {
            continue;
        }

        if (OrderType() == OP_BUY) {
            if (k1 >= 70 && k1 > d1 && k0 < d0) {
                Print("Closing longs, stoch crossunder");
                OrderClose(OrderTicket(), OrderLots(), Bid, 3, Red);
                continue;
            }
            continue;
        }

        if (OrderType() == OP_SELL) {
            if (k1 <= 30 && k1 < d1 && k0 > d1) {
                Print("Closing shorts, stoch crossover");
                OrderClose(OrderTicket(), OrderLots(), Ask, 3, Red);
                continue;
            }
            continue;
        }
    }
}

void getStochShift(double &k, double &d, int shift) {
    k = iStochastic(Symbol(), Period(), 5, 3, 3, MODE_SMA, 0, MODE_MAIN, shift);
    d = iStochastic(Symbol(), Period(), 5, 3, 3, MODE_SMA, 0, MODE_SIGNAL, shift);
}

bool isBuyAllowed() {
    double glacial = getGlacialSma();
    return Ask > glacial;
}

bool isSellAllowed() {
    double glacial = getGlacialSma();
    return Bid < glacial;
}

void checkCrosses() {
    Candle candle = newCandle(1);
    double spread = Ask - Bid;
    double stop;

    double currK, currD, prevK, prevD;
    getStochShift(currK, currD, 0);
    getStochShift(prevK, prevD, 1);

    //bullish
    if (prevK <= 30 && prevD <= 30 && prevK < prevD && currK > currD)
    {
        Print("bullish cross: %k = ", currK, " %%d = ", currD);
        stop = Bid - StopToCandleFactor * MathAbs(candle.high - candle.low) - spread;
        buy(stop, "buy stoch cross");
        return;
    }

    if (prevK >= 70 && prevD >= 70 && prevK > prevD && currK < currD)
    {
        Print("bearish cross: %k = ", currK, " %%d = ", currD);
        stop = Ask + StopToCandleFactor * MathAbs(candle.high - candle.low) + spread;
        sell(stop, "sell stoch cross");
        return;
    }
}

void OnTick() {
    Comment("rjacobus_stoch " + Symbol());
    //Invalid conditions

    if (Volume[0] > 1) {
        return;
    }

    manageOrders();

    if (ordersForSymbol(Symbol()) >= MaxSimultaneousOrders) {
        return;
    }

    checkCrosses();
}

