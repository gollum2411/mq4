#include <stdlib.mqh>

double getVolume(double minVolume, double riskPercentage) {
    double volume = NormalizeDouble(((AccountFreeMargin()/100) * riskPercentage) /1000.0,2);
    volume = (volume < minVolume ? minVolume : volume);
    return volume;
}

bool buy(string comment, int magic, double stop, double target, double volume) {
    int ticket = OrderSend(Symbol(), OP_BUY, volume, Ask, 3, stop, target, comment, magic);
    if (ticket == -1) {
        Print(ErrorDescription(GetLastError()));
        return false;
    }
    return true;
}

bool sell(string comment, int magic, double stop, double target, double volume) {
    int ticket = OrderSend(Symbol(), OP_SELL, volume, Bid, 3, stop, target, comment, magic);
    if (ticket == -1) {
        Print(ErrorDescription(GetLastError()));
        return false;
    }
    return true;
}

//Returns the number of open orders for sym
int ordersForSymbol(string sym) {
    int total = 0;
    for (int order = OrdersTotal()-1; order >= 0; order--) {
        if (!OrderSelect(order, SELECT_BY_POS)) {
            continue;
        }

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

struct Order {
    int ticket;
    double open;
    double stop;
};


static Order Orders[1024];
static int OrderIdx = 0;

bool isOrderNew(int ticket) {
    for (int i = 0; i < OrderIdx; i++) {
        Order order = Orders[i];
        if (order.ticket == ticket) {
            return false;
        }
    }
    return true;
}

void addOrder(int ticket) {
    if (!OrderSelect(ticket, SELECT_BY_TICKET)) {
        return;
    }
    Order order;
    order.ticket = ticket;
    order.open = OrderOpenPrice();
    order.stop = OrderStopLoss();
    Orders[OrderIdx++] = order;
    PrintFormat("addOrder: ticket: %d, stop: %f", order.ticket, order.stop);
}

void updateOrders() {
    for (int i = OrdersTotal()-1; i >= 0; i--){
        if (!OrderSelect(i, SELECT_BY_POS)) {
            continue;
        }
        if (OrderSymbol() != Symbol())
            continue;

        if (!isOrderNew(OrderTicket())) {
            continue;
        }

        addOrder(OrderTicket());
    }
}


