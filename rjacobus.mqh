#ifndef RJACOBUS_MQH
#define RJACOBUS_MQH

#include <stdlib.mqh>

int buy(double stop, string comment="") {
    if (!isBuyAllowed()) {
        Print("Buy not allowed");
        return -1;
    }

    return buyNoChecks(stop, comment);

}

int buyNoChecks(double stop, string comment="") {
    if (!isStopValid(Ask, stop)) {
        Print("Aborting buy, stop too narrow");
        return -1;
    }

    double spread = Ask - Bid;
    stop -= spread;

    double target = Bid + TPFactor * MathAbs(Bid - stop);
    double volume = _getVolume(Ask, stop);
    return buy(comment, MAGIC, stop, target, volume);
}

int sell(double stop, string comment="") {
    if (!isSellAllowed()) {
        Print("Sell not allowed");
        return -1;
    }

    return sellNoChecks(stop, comment);
}

int sellNoChecks(double stop, string comment="") {
    if (!isStopValid(Bid, stop)) {
        Print("Aborting sell, stop too narrow");
        return -1;
    }

    double spread = Ask - Bid;
    stop += spread;

    double target = Ask - TPFactor * (MathAbs(Ask - stop));
    double volume = _getVolume(Bid, stop);
    return sell(comment, MAGIC, stop, target, volume);
}

bool isBuyAllowed() {
    return Ask > BuyAbove;
}

bool isSellAllowed() {
    return Bid < SellBelow;
}

double getFastSma() {
    return iMA(NULL, Period(), FastSma, 0, MODE_SMA, PRICE_CLOSE, 0);
}

double getVolume(double minVolume, double riskPercentage) {
    double volume = NormalizeDouble(((AccountFreeMargin()/100) * riskPercentage) /1000.0,2);
    volume = (volume < minVolume ? minVolume : volume);
    return volume;
}

int buy(string comment, int magic, double stop, double target, double volume) {
    int ticket = OrderSend(Symbol(), OP_BUY, volume, Ask, 3, stop, target, comment, magic);
    if (ticket == -1) {
        Print(ErrorDescription(GetLastError()));
    }
    return ticket;
}

int sell(string comment, int magic, double stop, double target, double volume) {
    int ticket = OrderSend(Symbol(), OP_SELL, volume, Bid, 3, stop, target, comment, magic);
    if (ticket == -1) {
        Print(ErrorDescription(GetLastError()));
    }
    return ticket;
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

void updateGlobalOrdersArray(Order &orders[]) {
    for (int i = 0; i < ArraySize(Orders); i++) {
        if (i < ArraySize(orders)) {
            Orders[i].ticket = orders[i].ticket;
            Orders[i].open = orders[i].open;
            Orders[i].stop = orders[i].stop;
            continue;
        }

        Orders[i].ticket = 0;
        Orders[i].open = 0;
        Orders[i].stop = 0;
    }
}

string ordersFileName() {
    return Symbol() + "_orders.txt";
}

bool loadOrdersFile(Order &orders[]) {
    if (!FileIsExist(ordersFileName())) {
        return true;
    }

    int f = FileOpen(ordersFileName(), FILE_READ|FILE_BIN);
    if (f == INVALID_HANDLE) {
        Print("FileOpen failed: " + ErrorDescription(GetLastError()));
        return false;
    }

    int arrSize = ArraySize(orders);
    int i = 0;

    bool success = true;
    while(!FileIsEnding(f)) {
        if (i++ >= arrSize) {
            break;
        }
        Order order;
        uint bytes = FileReadStruct(f, order);
        if (bytes == 0) {
            //Failed reading
            success = false;
            break;
        }
        orders[i] = order;
    }
    FileClose(f);
    return success;
}

bool writeOrdersFile(Order &orders[]) {
    int f = FileOpen(ordersFileName(), FILE_WRITE|FILE_BIN);
    if (f == INVALID_HANDLE) {
        Print("FileOpen failed: " + ErrorDescription(GetLastError()));
        return false;
    }

    for (int i = 0; i < ArraySize(orders); i++) {
        if (orders[i].ticket == 0) {
            continue;
        }
        FileWriteStruct(f, orders[i]);
    }

    FileClose(f);
    return true;
}


bool isOrderNew(Order &orders[], int ticket) {
    for (int i = 0; i < ArraySize(orders); i++) {
        Order order = orders[i];
        if (order.ticket == ticket) {
            return false;
        }
    }
    return true;
}

void initOrders(Order &orders[]) {
    for (int i = 0; i < ArraySize(orders); i++) {
        orders[i].ticket = 0;
    }
}

bool appendOrder(Order &orders[], int ticket) {
    if (!OrderSelect(ticket, SELECT_BY_TICKET)) {
        return false;
    }
    for (int i = 0; i < ArraySize(orders); i++) {
        if (orders[i].ticket != 0) { // ticket is valid
            continue;
        }

        orders[i].ticket = ticket;
        orders[i].open = OrderOpenPrice();
        orders[i].stop = OrderStopLoss();
        return true;
    }
    return false;
}

bool loadOpenTickets(int &tickets[]) {
    for (int t = OrdersTotal()-1, i = 0; t>=0 && i < ArraySize(tickets); t--) {
        if (!OrderSelect(t, SELECT_BY_POS)) {
            Print("OrderSelect failed: " + ErrorDescription(GetLastError()));
            return false;
        }

        bool activeOrder = (OrderType() == OP_BUY || OrderType() == OP_SELL);

        if (OrderSymbol() != Symbol() || !activeOrder) {
            continue;
        }
        tickets[i++] = OrderTicket();
    }
    return true;
}

bool ticketInTickets(int ticket, int &tickets[]) {
    for (int i = 0; i < ArraySize(tickets); i++) {
        if (tickets[i] == 0) { //0 means empty, no more tickets to check
            return false;
        }
        if (ticket == tickets[i]) {
            return true;
        }
    }
    return false;
}

void updateOrders() {
    Order orders[128];
    initOrders(orders);
    if (!loadOrdersFile(orders)) {
        Print("loardOrdersFile failed: " + ErrorDescription(GetLastError()));
        return;
    }

    int tickets[128];
    ArrayInitialize(tickets, 0);
    if (!loadOpenTickets(tickets)) {
        Print("loadOpenTickets failed");
        return;
    }

    //For any order loaded, check if ticket is still open
    for (int i = 0; i < ArraySize(orders); i++) {
        if (orders[i].ticket == 0) {
            continue;
        }
        if (!ticketInTickets(orders[i].ticket, tickets)) {
            PrintFormat("updateOrders: removing ticket %d", orders[i].ticket);
            orders[i].ticket = 0; //So it won't be written back to file
            orders[i].open = 0; //So it won't be written back to file
            orders[i].stop = 0; //So it won't be written back to file
        }
    }

    //Add any new orders
    for (int i = OrdersTotal()-1; i >= 0; i--){
        if (!OrderSelect(i, SELECT_BY_POS)) {
            continue;
        }
        int ticket = OrderTicket();
        bool isActive = (OrderType() == OP_BUY || OrderType() == OP_SELL);
        if (OrderSymbol() != Symbol() || !isActive)
            continue;


        if (!isOrderNew(orders, ticket)) {
            continue;
        }

        PrintFormat("updateOrders: adding new ticket %d", ticket);
        appendOrder(orders, OrderTicket());
    }

    updateGlobalOrdersArray(orders);
    if (!writeOrdersFile(orders)) {
        Print("writeOrdersFile failed");
    }
    return;
}

#endif //RJACOBUS_MQH
