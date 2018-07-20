#include <stdlib.mqh>

#include "rjacobus.mqh"

#property strict
#property copyright "Roberto Jacobus"
#property link      "github.com/gollum2411"
#property version   "1.00"

const int MAGIC = 0xa1ed;

input const int FastSma = 20;

input const int StopSma1R = 200;
input const int StopSma2R = 50;

input double    StopToCandleFactor = 2.0;
input double    EmaToSwingStopFactor = 2.0;
input double    TPFactor = 2;
input int       MaxSimultaneousOrders = 10;

input double    BuyAbove = 0;
input double    SellBelow = 0;

input int       MinimumStopInPips = 15;
input double    MaxSpreadInPips = 3;

input double    RiskPerTrade = 0.01;

bool isStopValid(double entry, double stop) {
    double stopInPips = MathAbs(entry - stop) / normalizeDigits();
    return stopInPips >= MinimumStopInPips;
}

bool buy(double stop, string comment="") {
    if (!isBuyAllowed()) {
        Print("Buy not allowed");
        return false;
    }

    if (!isStopValid(Ask, stop)) {
        Print("Aborting buy, stop too narrow");
        return false;
    }

    double spread = Ask - Bid;
    stop -= spread;

    double target = Bid + TPFactor * MathAbs(Bid - stop);
    double volume = _getVolume(Ask, stop);
    return buy(comment, MAGIC, stop, target, volume);
}

bool sell(double stop, string comment="") {
    if (!isSellAllowed()) {
        Print("Sell not allowed");
        return false;
    }

    if (!isStopValid(Bid, stop)) {
        Print("Aborting sell, stop too narrow");
        return false;
    }

    double spread = Ask - Bid;
    stop += spread;

    double target = Ask - TPFactor * (MathAbs(Ask - stop));
    double volume = _getVolume(Bid, stop);
    return sell(comment, MAGIC, stop, target, volume);
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
    if (rate != 0) {
        return 1 / rate;
    }

    pair = StringConcatenate(quotedCurrency, accCurrency);
    rate = iClose(pair, Period(), 1);

    if (rate != 0) {
        return rate;
    }

    return 0;
}

double _getVolume(double price, double stop) {

    double stopInPips = MathAbs(price - stop) / normalizeDigits();
    // 1% of account
    double r = NormalizeDouble(AccountBalance() * RiskPerTrade, 2);
    double lotSize = MarketInfo(Symbol(), MODE_LOTSIZE);
    double pipValue = 0.01 * lotSize * normalizeDigits() * getExchangeRate();
    double lots = r / (stopInPips * pipValue) * 0.01; //for micro lots
    return lots;
}

double getFastSma() {
    return iMA(NULL, Period(), FastSma, 0, MODE_SMA, PRICE_CLOSE, 0);
}

double getStopSmaFromR(int timesR) {
    int stop = 0;
    switch(timesR) {
    case 1:
        stop = StopSma1R;
    case 2:
    default:
        stop = StopSma2R;
    }
    //Regular StopEma
    return iMA(NULL, Period(), stop, 0, MODE_SMA, PRICE_CLOSE, 0);
}

void getStochShift(double &k, double &d, int shift) {
    k = iStochastic(Symbol(), Period(), 5, 3, 3, MODE_SMA, 0, MODE_MAIN, shift);
    d = iStochastic(Symbol(), Period(), 5, 3, 3, MODE_SMA, 0, MODE_SIGNAL, shift);
}

bool isBuyAllowed() {
    return Ask > BuyAbove;
}

bool isSellAllowed() {
    return Bid < SellBelow;
}

int placeBuyOrder(string comment) {
    if (!isBuyAllowed()) {
        Print("Buy not allowed");
        return -1;
    }
    double spread = Ask - Bid;
    double fast = NormalizeDouble(getFastSma(), Digits);
    double low = getLow();
    double stop = fast - EmaToSwingStopFactor * (fast - low);

    if (!isStopValid(fast, stop)) {
        Print("aborting order, stop too narrow");
        return -1;
    }

    //Adjust for spread
    stop -= spread;

    double target = fast + TPFactor * MathAbs(fast - stop);
    double volume = _getVolume(fast, stop);
    Print("abs(entry - stop) = ", MathAbs(fast - stop) / normalizeDigits());
    int ret = OrderSend(Symbol(), OP_BUYSTOP, volume,
                        fast, 3, stop, target,
                        "", MAGIC);
    if (ret == -1) {
        SendNotification("Placing buy stop order failed: " + string(GetLastError()));
        return -1;
    }

    return ret;
}

int placeSellOrder(string comment) {
    if (!isSellAllowed()) {
        Print("Sell not allowed");
        return -1;
    }
    double spread = Ask - Bid;
    double fast = NormalizeDouble(getFastSma(), Digits);
    double high = getHigh();
    double stop = fast + EmaToSwingStopFactor * (high - fast);

    if (!isStopValid(fast, stop)) {
        Print("aborting order, stop too narrow");
        return -1;
    }

    //Adjust for spread
    stop += spread;

    double target = fast - TPFactor * MathAbs(stop - fast);
    double volume = _getVolume(fast, stop);
    Print("abs(entry - stop) = ", MathAbs(fast - stop) / normalizeDigits());
    int ret = OrderSend(Symbol(), OP_SELLSTOP, volume,
                        fast, 3, stop, target,
                        "", MAGIC);
    if (ret == -1) {
        SendNotification("Placing sell stop order failed: " + string(GetLastError()));
        return -1;
    }

    return ret;
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
    int ticket;

    double currK, currD, prevK, prevD;
    getStochShift(currK, currD, 1);
    getStochShift(prevK, prevD, 2);

    //bullish
    if (prevK <= 20 && prevD <= 20 && prevK < prevD && currK > currD)
    {
        if (Ask > getFastSma()) {
            double low = getLow();
            stop = Bid - EmaToSwingStopFactor * (Bid - low);
            if (buy(stop, "buy stoch cross")) {
                closePendingOrders();
            }
            return;
        }
        Print("bullish cross: %k = ", currK, " %%d = ", currD);
        ticket = placeBuyOrder("Place buy order: stoch cross");
        if (ticket == -1) {
            return;
        }

        closePendingOrdersExcept(ticket);
        return;
    }

    if (prevK >= 80 && prevD >= 80 && prevK > prevD && currK < currD)
    {
        if (Bid < getFastSma()) {
            double high = getHigh();
            stop = Ask + EmaToSwingStopFactor * (high - Ask);
            if (sell(stop, "sell stoch cross")) {
                closePendingOrders();
            }
            return;
        }
        Print("bearish cross: %k = ", currK, " %%d = ", currD);
        ticket = placeSellOrder("Place sell order: stoch cross");
        if (ticket == -1) {
            return;
        }

        closePendingOrdersExcept(ticket);
        return;
    }
}

void closePendingOrders() {
    for (int order = OrdersTotal() - 1; order >= 0; order--) {
        if (!OrderSelect(order, SELECT_BY_POS)) {
            continue;
        }
        int type = OrderType();
        if (OrderSymbol() != Symbol() ) {
            continue;
        }

        if (type != OP_BUYSTOP && type != OP_SELLSTOP) {
            continue;
        }

        if (!OrderDelete(OrderTicket())) {
            SendNotification("failed to delete ticket " + string(OrderTicket()));
        }
    }
}

void closePendingOrdersExcept(int ticket) {
    for (int order = OrdersTotal() - 1; order >= 0; order--) {
        if (!OrderSelect(order, SELECT_BY_POS)) {
            continue;
        }
        int type = OrderType();
        if (OrderSymbol() != Symbol() || OrderTicket() == ticket ) {
            continue;
        }

        if (type != OP_BUYSTOP && type != OP_SELLSTOP) {
            continue;
        }

        if (!OrderDelete(OrderTicket())) {
            SendNotification("failed to delete ticket " + string(OrderTicket()));
        }
    }
}

void trailOrders() {
    //Don't trail
    if (StopSma2R == 0) {
        return;
    }
    for (int order = OrdersTotal() - 1; order >= 0; order--) {
        if (!OrderSelect(order, SELECT_BY_POS)) {
            continue;
        }

        int type = OrderType();
        if (OrderSymbol() != Symbol()) {
            continue;
        }

        if (type != OP_BUY && type != OP_SELL) {
            continue;
        }

        double R = NormalizeDouble(AccountBalance() * RiskPerTrade, 2);
        int timesR = int(MathFloor(OrderProfit() / R));

        if (timesR <= 1) {
            continue;
        }

        double stop = getStopSmaFromR(timesR);
        PrintFormat("Stop loss = ", OrderStopLoss(), ", Stop MA = ", stop);
        PrintFormat("R = %f, Open profit = %f", R, OrderProfit());
        PrintFormat("Ticket %d is at %dR", OrderTicket(), timesR);

        Print("Moving stop...");
        if ((type == OP_BUY && stop > OrderStopLoss()) ||
           (type == OP_SELL && stop < OrderStopLoss())) {
            if (!OrderModify(OrderTicket(), OrderOpenPrice(), stop, OrderTakeProfit(), 0, Blue)) {
                SendNotification("OrderModify failed for ticket " + string(OrderTicket()) +
                                 ", error = " + string(GetLastError()));
            }
            continue;
        }
    }
}

int OnInit() {
    Print("OnInit: getExchangeRate: ", getExchangeRate());

    if (!IsTradeAllowed()) {
        return 0;
    }

    if (BuyAbove == 0 || SellBelow == 0) {
        string message = StringFormat("rjacobus_stoch_levels: %s uninitialized. Aborting...", Symbol());
        SendNotification(message);
        return -1;
    }

    string initMessage = StringFormat("rjacobus_stoch_levels: %s: BuyAbove=%f SellBelow=%f fastMA=%d stopMA=%d",
        Symbol(), BuyAbove, SellBelow, FastSma, StopSma2R);

    SendNotification(initMessage);
    return 0;
}

double getSpreadInPips() {
    return (Ask - Bid) / normalizeDigits();
}

bool isNewCandle()
{
    static datetime last;
    datetime curr = Time[0];

    if (curr == last)
        return false;

    last = curr;
    return true;
}

void OnTick() {
    Comment("rjacobus_stoch_levels " + Symbol());
    //Invalid conditions

    if (!isNewCandle()) {
        return;
    }

    trailOrders();

    if (ordersForSymbol(Symbol()) >= MaxSimultaneousOrders) {
        Print("Max simutaneous orders reached, closing pending orders.");
        closePendingOrders();
        return;
    }

    double spread = getSpreadInPips();
    if (spread > MaxSpreadInPips) {
        Print("Aborting, spread too wide: ", spread);
        return;
    }


    checkCrosses();
}

