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
input const int StopSma = 50;

input double    StopToCandleFactor = 2.0;
input double    EmaToSwingStopFactor = 2.0;
input double    TPFactor = 2;
input int       MaxSimultaneousOrders = 10;

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

double getExchangeRate() {
    string symbol = Symbol();
    if (StringLen(symbol) != 6)
        return 1;

    string accCurrency    = AccountCurrency();
    string baseCurrency   = StringSubstr(symbol, 0, 3);
    string quotedCurrency = StringSubstr(symbol, 3, 3);

    if (StringCompare(accCurrency, quotedCurrency) == 0) {
        return 1;
    }

    if (StringCompare(accCurrency, baseCurrency) == 0) {
        return 1 / MarketInfo(symbol, MODE_BID);
    }

    string pair = StringConcatenate(accCurrency, quotedCurrency);
    double rate = iClose(pair, Period(), 1);
    int lastError = GetLastError();

    if (lastError == 0) {
        return 1 / rate;
    }

    pair = StringConcatenate(quotedCurrency, accCurrency);
    rate = iClose(pair, Period(), 1);
    lastError = GetLastError();

    if (lastError == 0) {
        return rate;
    }

    if (lastError != 0) {
        Print("getExchangeRate(): iClose error: ", lastError);
    }

    return 0;
}

double _getVolume(double price, double stop) {

    double stopInPips = MathAbs(price - stop) / normalizeDigits();
    // 1% of account
    double r = NormalizeDouble(AccountBalance() * 0.01, 2);
    double lotSize = MarketInfo(Symbol(), MODE_LOTSIZE);
    double pipValue = 0.01 * lotSize * normalizeDigits() * getExchangeRate();
    double lots = r / (stopInPips * pipValue) * 0.01; //for micro lots
    return lots;
}

double getGlacialSma() {
    return iMA(NULL, PERIOD_D1, GlacialSma, 0, MODE_SMA, PRICE_CLOSE, 0);
}

double getFastSma() {
    return iMA(NULL, Period(), FastSma, 0, MODE_SMA, PRICE_CLOSE, 0);
}

double getStopSma() {
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
    double stopInPips = (fast - stop) / normalizeDigits();
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

    double target = fast + TPFactor * MathAbs(fast - stop);
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
    double stopInPips = (stop - fast) / normalizeDigits();
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

    double target = fast - TPFactor * MathAbs(stop - fast);
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
            double low = getLow();
            stop = Bid - EmaToSwingStopFactor * (Bid - low) - spread;
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
            double high = getHigh();
            stop = Ask + EmaToSwingStopFactor * (high - Ask) + spread;
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
        double stop = getStopSma();
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

    trailOrders();

    checkPendingOrdersForClose();

    if (ordersForSymbol(Symbol()) >= MaxSimultaneousOrders) {
        Print("Max simutaneous orders reached, closing pending orders.");
        closePendingOrders();
        return;
    }

    checkCrosses();
}

