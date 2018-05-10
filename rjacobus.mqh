double getVolume(double minVolume, double riskPercentage) {
    double volume = NormalizeDouble(((AccountFreeMargin()/100) * riskPercentage) /1000.0,2);
    volume = (volume < minVolume ? minVolume : volume);
    return volume;
}

void buy(string comment, int magic, double stop, double target, double volume) {
    OrderSend(Symbol(), OP_BUY, volume, Ask, 3, stop, target, comment, magic);
    Print(ErrorDescription(GetLastError()));
}

void sell(string comment, int magic, double stop, double target, double volume) {
    OrderSend(Symbol(), OP_SELL, volume, Bid, 3, stop, target, comment, magic);
    Print(ErrorDescription(GetLastError()));
}

//Returns the number of open orders for sym
int ordersForSymbol(string sym) {
    int total = 0;
    for (int order = OrdersTotal()-1; order >= 0; order--) {
        OrderSelect(order, SELECT_BY_POS);
        if (OrderSymbol() != sym) {
            continue;
        }

        int type = OrderType();
        if (type != OP_BUY && type != OP_SELL) {
            continue;
        }
        total++;
    }
    return total;
}

struct Candle {
    double high;
    double low;
    double open;
    double close;

    bool isBullish;
    bool isBearish;
};

Candle newCandle(int n) {
    double h = High[n];
    Candle candle;
    candle.high = High[n];
    candle.low = Low[n];
    candle.open = Open[n];
    candle.close = Close[n];
    candle.isBullish = Close[n] > Open[n];
    candle.isBearish = Close[n] < Open[n];

    return candle;
}

