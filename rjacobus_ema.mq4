#include <stdlib.mqh>

#include "rjacobus.mqh"

#property copyright "Roberto Jacobus"
#property link      "github.com/gollum2411"
#property version   "1.00"

const int MAGIC = 0x15ac;

enum EmaPeriods {
    EMA_10 = 10,
    EMA_20 = 20,
    EMA_50 = 50,
    EMA_100 = 100,
    EMA_200 = 200
};

enum SmaPeriods {
    SMA_10 = 10,
    SMA_20 = 20,
    SMA_50 = 50,
    SMA_100 = 100,
    SMA_200 = 200
};

enum AdxPeriods {
    ADX_10 = 10,
    ADX_20 = 20,
    ADX_50 = 50,
    ADX_100 = 100
};

enum direction {
    BUY,
    SELL
};

input double    StopToCandleFactor = 1.0;
input double    TPFactor = 2;
input bool      UseTrailingStop = true;
input bool      ExitWhenCloseBeyondSma = false;
input int       MaxSimultaneousOrders = 10;
input double    MinimumLots = 0.01;

input EmaPeriods EmaPeriod = EMA_10;
input SmaPeriods SmaPeriod = SMA_20;
input AdxPeriods AdxPeriod = ADX_10;

double lastBid;
double lastAsk;
direction LAST_DIRECTION;

void buy(double stop, string comment="") {
    double volume = NormalizeDouble(((AccountFreeMargin()/100) * 1) /1000.0,2);
    volume = (volume < MinimumLots ? MinimumLots : volume);
    double target = Bid + TPFactor * MathAbs(Bid - stop);
    buy(comment, MAGIC, stop, target, volume);
}

void sell(double stop, string comment="") {
    double volume = NormalizeDouble(((AccountFreeMargin()/100) * 1) /1000.0,2);
    volume = (volume < MinimumLots ? MinimumLots : volume);
    double target = Ask - TPFactor * (MathAbs(Ask - stop));
    sell(comment, MAGIC, stop, target, volume);
}

double getEMA() {
    return iMA(NULL, 0, EmaPeriod, 0, MODE_EMA, PRICE_CLOSE, 0);
}

double getSMA() {
    return iMA(NULL, 0, SmaPeriod, 0, MODE_SMA, PRICE_CLOSE, 0);
}

double getADX() {
    return iADX(NULL, 0, AdxPeriod, PRICE_CLOSE, MODE_MAIN, 0);
}

void getDMI(double &plus, double &minus) {
    plus = iADX(NULL, 0, AdxPeriod, PRICE_CLOSE, MODE_PLUSDI, 0);
    minus = iADX(NULL, 0, AdxPeriod, PRICE_CLOSE, MODE_MINUSDI, 0);
    return;
}

void manageOrders() {
    if (!ExitWhenCloseBeyondSma) {
        return;
    }

    for(int order = 0; order < OrdersTotal(); order++) {
        OrderSelect(order, SELECT_BY_POS);
        if (OrderSymbol() != Symbol()) {
            continue;
        }
        if (OrderType() == OP_BUY) {
            if (Close[1] < getSMA()) {
                OrderClose(OrderTicket(), OrderLots(), Bid, 3, Red);
            }
            return;
        }

        if (Close[1] > getSMA()) {
            OrderClose(OrderTicket(), OrderLots(), Ask, 3, Red);
        }
    }
}

void trailStop() {
    if (!UseTrailingStop) {
        return;
    }

    double open = Open[1];
    double close = Close[1];
    double high = High[1];
    double low = Low[1];

    for(int order = 0; order < OrdersTotal(); order++) {
        OrderSelect(order, SELECT_BY_POS);
        if (OrderSymbol() != Symbol()) {
            continue;
        }
        if (OrderType() == OP_BUY) {
            if (close > open) { //if bullish
                OrderModify(OrderTicket(), OrderOpenPrice(), OrderStopLoss() + (close - open), OrderTakeProfit(), 0, Green);
                Print(ErrorDescription(GetLastError()));
            }
            return;
        }

        if (close < open) { //bearish candle
            OrderModify(OrderTicket(), OrderOpenPrice(), OrderStopLoss() - (open - close), OrderTakeProfit(), 0, Green);
            Print(ErrorDescription(GetLastError()));
        }
    }

}

direction getDirection() {
    return getEMA() > getSMA() ? BUY : SELL;
}

void OnTick() {
    Comment("rjacobus_ema " + Symbol());
    //Invalid conditions
    if(EmaPeriod >= int(SmaPeriod)){
        return;
    }

    if (Volume[0] > 1) {
        return;
    }

    trailStop();
    manageOrders();

    if (ordersForSymbol(Symbol()) >= MaxSimultaneousOrders) {
        return;
    }

    //Latest candle
    Candle candle = newCandle(1);

    double ema = getEMA();
    double sma = getSMA();

    direction dir = getDirection();

    double adx = getADX();
    if (adx < 30) {
        return;
    }

    double stop;
    double spread = Ask - Bid;
    if (dir == BUY) {
        stop = Bid - StopToCandleFactor * MathAbs(candle.high - candle.low) - spread;

        if (candle.isBullish) {
            if (candle.close > ema &&
               (candle.low < ema || candle.open < ema)) {
                buy(stop, "Buy bullish candle");
            }
        }

        if (candle.isBearish) {
            if (candle.low < ema && candle.close > ema) {
                stop = candle.close + StopToCandleFactor * (candle.high - candle.low);
                buy(stop, "Buy bearish candle");
            }
        }
    }

    if (dir == SELL) {
        stop = Ask + StopToCandleFactor * MathAbs(candle.high - candle.low) + spread;
        if (candle.isBullish) {
            if (candle.high > ema && candle.close < ema) {
                sell(stop, "Sell bullish candle");
            }
        }

        if (candle.isBearish) {
            if (candle.close < ema &&
               (candle.high > ema || candle.open > ema)) {

               sell(stop, "Sell bearish candle");
            }
        }
    }
}
