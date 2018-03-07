#include <stdlib.mqh>

#property copyright "Roberto Jacobus"
#property link      "github.com/gollum2411"
#property version   "1.00"

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
    ADX_20 = 20
};

enum direction {
    BUY,
    SELL
};

input double    StopToCandleFactor = 1.0;
input double    TPFactor = 2;
input bool      UseTrailingStop = true;
input bool      ExitWhenCloseBeyondSma = false;
input bool      AllowSimultaneousOrders = false;
input int       MaxSimultaneousOrders = 10;
input double    MinimumLots = 0.01;

input EmaPeriods EmaPeriod = EMA_10;
input SmaPeriods SmaPeriod = SMA_20;
input AdxPeriods AdxPeriod = ADX_10;

double lastBid;
double lastAsk;
direction LAST_DIRECTION;

void buy(double stop) {
    double volume = NormalizeDouble(((AccountFreeMargin()/100) * 1) /1000.0,2);
    volume = (volume < MinimumLots ? MinimumLots : volume);
    OrderSend(Symbol(), OP_BUY, volume, Ask, 3, stop, Bid + (MathAbs(Bid - stop)) * TPFactor, "FUCK YOU JESUS", 666);
    Print(ErrorDescription(GetLastError()));
}

void sell(double stop) {
    double volume = NormalizeDouble(((AccountFreeMargin()/100) * 1) /1000.0,2);
    volume = (volume < MinimumLots ? MinimumLots : volume);
    OrderSend(Symbol(), OP_SELL, volume, Bid, 3, stop, Ask - (MathAbs(Ask - stop)) * TPFactor, "FUCK YOU JESUS", 666);
    Print(ErrorDescription(GetLastError()));
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
            if (Close[1] < getEMA()) {
                OrderClose(OrderTicket(), OrderLots(), Bid, 3, Red);
            }
            return;
        }

        if (Close[1] > getEMA()) {
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

enum State {
    StateStart,
    StateWaitForEmaTouch
};

string stateToString(State s) {
    switch(s) {
    case StateStart:
        return "START";
    case StateWaitForEmaTouch:
        return "WAIT_FOR_EMA_TOUCH";
    default:
        return "STRANGE_STATE";
    }
}

State STATE = StateWaitForEmaTouch;

void OnTick() {
    Comment(stateToString(STATE));
    if(EmaPeriod >= int(SmaPeriod)) {
        return;
    }

    if (AdxPeriod > int(EmaPeriod)) {
        return;
    }


    for( ;; ) {
        if (Volume[0] > 1) {
            break;
        }

        trailStop();
        manageOrders();
        int orderCount = OrdersTotal();

        if ((orderCount > 1 && !AllowSimultaneousOrders) ||
            (orderCount >= MaxSimultaneousOrders)) {
            break;
        }

        double high = High[1];
        double low = Low[1];
        double open = Open[1];
        double close = Close[1];

        bool bullish = open > close;
        bool bearish = ! bullish;

        double ema = getEMA();
        double sma = getSMA();

        double stop;
        direction dir = getDirection();

        double adx = getADX();
        Print("adx = ", adx);
        if (adx < 30) {
            break;
        }

        switch(STATE) {
        case StateStart:
            //Wait for EMA cross
            if (dir != LAST_DIRECTION) {
                STATE = StateWaitForEmaTouch;
            }
            break;

        case StateWaitForEmaTouch:
            if (bullish && dir == SELL && (
               (high > ema && close < ema) ||
               (close > ema && close < sma))) {
                stop = close + StopToCandleFactor * (high - low);
                sell(stop);
            }

            if (bearish && dir == BUY && (
               (low < ema && close > ema) ||
               (close < ema && close > sma))) {
                stop = close - StopToCandleFactor * (high - low);
                buy(stop);
           }

           if (dir != LAST_DIRECTION) {
                STATE = StateStart;
           }

           break;
        }

        break;
    }
    lastBid = Bid;
    lastAsk = Ask;
    LAST_DIRECTION = dir;
}
