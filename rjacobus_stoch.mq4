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
input const int FastSma = 20;

input double    StopToCandleFactor = 2.0;
input double    EmaToSwingStopFactor = 2.0;
input double    TPFactor = 2;
input int       MaxSimultaneousOrders = 10;
input double    MinimumLots = 0.01;

void buy(double stop, string comment="") {
    if (!isBuyAllowed()) {
        Print("Buy not allowed");
        return;
    }

    double spread = Ask - Bid;
    double stopInPips = (Ask - stop) / normalizeDigits();
    if (stopInPips < 10) {
        Print("Aborting buy, stop too narrow");
        return;
        stop = Ask - 10*normalizeDigits() - spread;
        Print("buy");
        Print("modified stop: ", stop);
        Print("modified stop in pips: ", (Ask - stop) / normalizeDigits());
    }

    double target = Bid + TPFactor * MathAbs(Bid - stop);
    double volume = _getVolume(Ask, stop);
    Print("abs(entry - stop) = ", MathAbs(Ask - stop) / normalizeDigits());
    buy(comment, MAGIC, stop, target, volume);
}

void sell(double stop, string comment="") {
    if (!isSellAllowed()) {
        Print("Sell not allowed");
        return;
    }

    double spread = Ask - Bid;
    double stopInPips = (stop - Bid) / normalizeDigits();
    if (stopInPips < 10) {
        Print("Aborting sell, stop too narrow");
        return;
        stop = Bid + 10*normalizeDigits() + spread;
        Print("sell");
        Print("modified stop: ", stop);
        Print("modified stop in pips: ", (stop - Bid) / normalizeDigits());
    }

    double target = Ask - TPFactor * (MathAbs(Ask - stop));
    double volume = _getVolume(Bid, stop);
    Print("abs(entry - stop) = ", MathAbs(stop - Bid) / normalizeDigits());
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

double getFastSma() {
    return iMA(NULL, Period(), FastSma, 0, MODE_SMA, PRICE_CLOSE, 0);
}

double getSlowSma() {
    return iMA(NULL, Period(), 50, 0, MODE_SMA, PRICE_CLOSE, 0);
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

void placeBuyOrder(string comment) {
    if (!isBuyAllowed()) {
        Print("Buy not allowed");
        return;
    }
    double spread = Ask - Bid;
    double fast = NormalizeDouble(getFastSma(), Digits);
    double low = getLow();
    double stop = fast - EmaToSwingStopFactor * (fast - low) - spread;
    double stopInPips = (fast - low) / normalizeDigits();
    Print("stop = ", stop);
    Print("stop in pips = ", stopInPips);
    if (stopInPips < 10) {
        Print("aborting order, stop too narrow");
        return;
        stop = fast - 10*normalizeDigits() - spread;
        Print("placeBuyOrder");
        Print("modified stop: ", stop);
        Print("modified stop in pips: ", (fast - stop) / normalizeDigits());
    }

    double target = fast + TPFactor * (fast - low);
    double volume = _getVolume(fast, stop);
    Print("abs(entry - stop) = ", MathAbs(fast - stop) / normalizeDigits());
    int ret = OrderSend(Symbol(), OP_BUYSTOP, volume,
                        fast, 3, stop, target,
                        "", MAGIC);
    if (ret == -1) {
        SendNotification("Placing buy stop order failed: " + GetLastError());
    }
}

void placeSellOrder(string comment) {
    if (!isSellAllowed()) {
        Print("Sell not allowed");
        return;
    }
    double spread = Ask - Bid;
    double fast = NormalizeDouble(getFastSma(), Digits);
    double high = getHigh();
    double stop = fast + EmaToSwingStopFactor * (high - fast) + spread;
    double stopInPips = (high - fast) / normalizeDigits();
    Print("stop = ", stop);
    Print("stop in pips = ", stopInPips);
    if (stopInPips < 10) {
        Print("aborting order, stop too narrow");
        return;
        stop = high + 10*normalizeDigits() + spread;
        Print("placeSellOrder");
        Print("modified stop: ", stop);
        Print("modified stop in pips: ", (stop - fast) / normalizeDigits());
    }

    double target = fast - TPFactor * (high - fast);
    double volume = _getVolume(fast, stop);
    Print("abs(entry - stop) = ", MathAbs(fast - stop) / normalizeDigits());
    int ret = OrderSend(Symbol(), OP_SELLSTOP, volume,
                        fast, 3, stop, target,
                        "", MAGIC);
    if (ret == -1) {
        SendNotification("Placing sell stop order failed: " + GetLastError());
    }
}

double getHigh() {
    return High[iHighest(Symbol(), Period(), MODE_HIGH, 5, 0)];
}

double getLow() {
    return Low[iLowest(Symbol(), Period(), MODE_LOW, 5, 0)];
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
        if (Ask > getFastSma()) {
            stop = Bid - StopToCandleFactor * MathAbs(candle.high - candle.low) - spread;
            buy(stop, "buy stoch cross");
            return;
        }
        Print("bullish cross: %k = ", currK, " %%d = ", currD);
        placeBuyOrder("Place buy order: stoch cross");
        return;
    }

    if (prevK >= 70 && prevD >= 70 && prevK > prevD && currK < currD)
    {
        if (Bid < getFastSma()) {
            stop = Ask + StopToCandleFactor * MathAbs(candle.high - candle.low) + spread;
            sell(stop, "sell stoch cross");
        }
        Print("bearish cross: %k = ", currK, " %%d = ", currD);
        placeSellOrder("Place sell order: stoch cross");
        return;
    }
}

void checkPendingOrdersForClose() {
    Candle candle = newCandle(1);
    double glacial = getGlacialSma();

    for (int order = OrdersTotal() - 1; order >= 0; order--) {
        OrderSelect(order, SELECT_BY_POS);
        if (OrderSymbol() != Symbol()) {
            continue;
        }

        if (OrderType() == OP_BUYSTOP && candle.close < glacial) {
            Print("Cancelling ticket ", OrderTicket());
            OrderDelete(OrderTicket());
            continue;
        }

        if (OrderType() == OP_SELLSTOP && candle.close > glacial) {
            Print("Cancelling ticket ", OrderTicket());
            OrderDelete(OrderTicket());
            continue;
        }
    }
}

void closePendingOrders() {
    for (int order = OrdersTotal() - 1; order >= 0; order--) {
        OrderSelect(order, SELECT_BY_POS);
        int type = OrderType();
        if (OrderSymbol() != Symbol() ) {
            continue;
        }

        if (type != OP_BUYSTOP && type != OP_SELLSTOP) {
            continue;
        }

        OrderDelete(OrderTicket());
    }
}

void trailOrders() {
    for (int order = OrdersTotal() - 1; order >= 0; order--) {
        OrderSelect(order, SELECT_BY_POS);
        if (OrderSymbol() != Symbol()) {
            continue;
        }
        double R = NormalizeDouble(AccountBalance() * 0.01, 2);
        int timesR = MathFloor(OrderProfit() / R);
        PrintFormat("R = %f, Open profit = %f", R, OrderProfit());
        PrintFormat("Ticket %d is at %dR", OrderTicket(), timesR);
        if (timesR <= 1) {
            continue;
        }

        Print("Moving stop...");
        double stop = getSlowSma();
        if ((OrderType() == OP_BUY && stop > OrderStopLoss()) ||
            (OrderType() == OP_SELL && stop < OrderStopLoss())) {
            OrderModify(OrderTicket(), OrderOpenPrice(), stop, OrderTakeProfit(), 0, Blue);
            continue;
        }
    }
}

void OnTick() {
    Comment("rjacobus_stoch " + Symbol());
    //Invalid conditions

    if (Volume[0] > 1) {
        return;
    }

    Print("rjacobus_stoch: ", Symbol(), " alive...");
    trailOrders();

    checkPendingOrdersForClose();

    if (ordersForSymbol(Symbol()) >= MaxSimultaneousOrders) {
        Print("Max simutaneous orders reached, closing pending orders.");
        closePendingOrders();
        return;
    }

    checkCrosses();
}

