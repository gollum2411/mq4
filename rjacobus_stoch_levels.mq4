#include <stdlib.mqh>

#include "rjacobus.mqh"
#include "rjacobus_fade_range.mqh"

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

const double StochLow = 30;
const double StochHigh = 70;

bool isStopValid(double entry, double stop) {
    double stopInPips = MathAbs(entry - stop) / normalizeDigits();
    return stopInPips >= MinimumStopInPips;
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


double originalStopLoss(int ticket) {
    for (int i = 0; i < ArraySize(Orders); i++) {
        if (ticket == Orders[i].ticket) {
            return Orders[i].stop;
        }
    }
    return -1;
}

double getStopFromR(int order, double timesR) {
    if (!OrderSelect(order, SELECT_BY_POS)) {
        Print("getStopFromR: OrderSelect error: ", GetLastError());
        return -1;
    }

    if (timesR < 0.5) {
        return OrderStopLoss();
    }

    bool isLong = OrderType() == OP_BUY;
    bool isShort = OrderType() == OP_SELL;
    double currPrice = isLong ? Ask : Bid;
    int ticket = OrderTicket();
    int type = OrderType();
    double currStopLoss = OrderStopLoss();
    double originalStopLoss = NormalizeDouble(originalStopLoss(OrderTicket()), Digits);
    double openPrice = OrderOpenPrice();
    double openProfit = OrderProfit();

    if (!isLong && !isShort)
        return -1;

    PrintFormat("getStopFromR: ticket %d: original stop loss = %f, timesR = %f",
                ticket, originalStopLoss, timesR);


    double diffPoints = MathAbs(openPrice - currPrice);
    double halfR = AccountBalance() * RiskPerTrade / 2; //0.5R
    double targetStopShift = halfR * diffPoints / openProfit;

    PrintFormat("getStopFromR: openProfit=%f, diffPoints=%f, halfR=%f, targetStopShift=%f",
                openProfit, diffPoints, halfR, targetStopShift);

    int stopSma = 0;
    //If R between 0.5 and 1R, move stop loss to half the original distance, to risk 0.5R
    if (timesR >= 0.5 && timesR < 1) {
        PrintFormat("getStopFromR: ticket %d: moving stop to risk 0.5R at most",
                    ticket);
        if (isLong) {
            return openPrice - targetStopShift;
        } else if (isShort) {
            return openPrice + targetStopShift;
        }
        return -1;
    }

    //If current R is between 1 and 1.5R, move stop loss to secure 0.5R
    else if (timesR >= 1 && timesR < 1.5) {
        PrintFormat("getStopFromR: ticket %d: moving stop to secure gain at 0.5 R",
                    ticket);
        if (isLong) {
            return openPrice + targetStopShift;
        } else if (isShort) {
            return openPrice - targetStopShift;
        }
        return -1;

    } else if (timesR >= 1.5 && timesR < 2) {
        PrintFormat("getStopFromR: ticket %d: moving stop to secure gain at 1R",
                    ticket);
        if (isLong) {
            return openPrice + targetStopShift*2;
        } else if (isShort) {
            return openPrice - targetStopShift*2;
        }
        return -1;
    } else {
        //Anything above 2R
        PrintFormat("getStopFromR: ticket %d: moving stop to the %d SMA",
                    ticket, StopSma2R);
        double stop = iMA(NULL, Period(), StopSma2R, 0, MODE_SMA, PRICE_CLOSE, 0);
        if ((isLong && stop > currStopLoss) ||
            (isShort && stop < currStopLoss)) {
            return stop;
        }
        return -1;
    }
    return -1;
}

void getStochShift(double &k, double &d, int shift) {
    k = iStochastic(Symbol(), Period(), 5, 3, 3, MODE_SMA, 0, MODE_MAIN, shift);
    d = iStochastic(Symbol(), Period(), 5, 3, 3, MODE_SMA, 0, MODE_SIGNAL, shift);
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
                        StringFormat("%f", stop), MAGIC);
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
                        StringFormat("%f", stop), MAGIC);
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
    if (prevK <= StochLow && prevD <= StochLow && prevK < prevD && currK > currD)
    {
        if (Ask > getFastSma()) {
            double low = getLow();
            stop = Bid - EmaToSwingStopFactor * (Bid - low);
            if (buy(stop, StringFormat("%f", stop)) != -1) {
                closePendingOrders();
            }
            return;
        }
        ticket = placeBuyOrder("Place buy order: stoch cross");
        if (ticket == -1) {
            return;
        }

        closePendingOrdersExcept(ticket);
        return;
    }

    if (prevK >= StochHigh && prevD >= StochHigh && prevK > prevD && currK < currD)
    {
        if (Bid < getFastSma()) {
            double high = getHigh();
            stop = Ask + EmaToSwingStopFactor * (high - Ask);
            if (sell(stop, StringFormat("%f", stop)) != -1) {
                closePendingOrders();
            }
            return;
        }
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

        double currStopLoss = OrderStopLoss();
        int type = OrderType();
        if (OrderSymbol() != Symbol()) {
            continue;
        }

        if (type != OP_BUY && type != OP_SELL) {
            continue;
        }

        double R = NormalizeDouble(AccountBalance() * RiskPerTrade, 2);
        double timesR = NormalizeDouble(OrderProfit() / R, 2);

        if (timesR < 0) {
            continue;
        }

        double stop = getStopFromR(order, timesR);
        if (stop == -1) {
            Print("error from getStopFromR");
            continue;
        }

        //suggested stop would go against us
        if ((type == OP_BUY && stop <= currStopLoss) ||
            (type == OP_SELL && stop >= currStopLoss)) {
            continue;
        }

        PrintFormat("Ticket %d: open profit = %f, %.2fR", OrderTicket(),
                    OrderProfit(), timesR);
        PrintFormat("Ticket %d: current stop = %f, moving stop to %f",
                    OrderTicket(), OrderStopLoss(), stop);
        Print("Moving stop...");
        if (!OrderModify(OrderTicket(), OrderOpenPrice(), stop, OrderTakeProfit(), 0, Blue)) {
            SendNotification("OrderModify failed for ticket " + string(OrderTicket()) +
                             ", error = " + string(GetLastError()));
        }
    }
}

int OnInit() {
    Print("OnInit: getExchangeRate: ", getExchangeRate());

    if (!IsTradeAllowed()) {
        return 0;
    }

    if (FileIsExist(ordersFileName())) {
        Print("Found orders file...");
    }

    if (BuyAbove == 0 || SellBelow == 0) {
        string message = StringFormat("rjacobus_stoch_levels: %s uninitialized. Aborting...", Symbol());
        SendNotification(message);
        return -1;
    }

    string initMessage = StringFormat("rjacobus_stoch_levels: %s: BuyAbove=%f SellBelow=%f "
                                      "fastMA=%d StopSma2R=%d StochLevels=[%f,%f]",
        Symbol(), BuyAbove, SellBelow, FastSma, StopSma2R, StochLow, StochHigh);

    Print(initMessage);
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

bool isNewMinuteCandle() {
    static datetime last;
    datetime curr = iTime(Symbol(), PERIOD_M1, 0);
    if (curr == last) {
        return false;
    }

    last = curr;
    return true;
}

void OnTick() {
    Comment("rjacobus_stoch_levels " + Symbol());

    if (isNewMinuteCandle()) {
        updateOrders();
        trailOrders();
    }

    if (!isNewCandle()) {
        return;
    }

    static int lastOrderCount = ordersForSymbol(Symbol());
    if (lastOrderCount != ordersForSymbol(Symbol())) {
        PrintFormat("New orders detected, updating orders...");
        lastOrderCount = OrdersTotal();
        updateOrders();
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

    checkRangeFade();
}

