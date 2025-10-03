/*

   Expanding Grid
   Copyright 2014-2025, Orchard Forex
   https://orchardforex.com

*/

#property copyright "Copyright 2014-2025, Orchard Forex"
#property link "https://orchardforex.com"
#property version "3.00"

#include <Trade/Trade.mqh>
CTrade        Trade;
CPositionInfo PositionInfo;

struct CLegData {
   int    count;
   double tailPrice;
   double averagePrice;
   double volPrice;
   double volTotal;

   void   Init() {
      count        = 0;
      tailPrice    = 0;
      averagePrice = 0;
      volPrice     = 0;
      volTotal     = 0;
   }

   void Update() {
      count++;
      volPrice += PositionInfo.PriceOpen() * PositionInfo.Volume();
      volTotal += PositionInfo.Volume();
      averagePrice = volPrice / volTotal;
      if ( PositionInfo.PositionType() == POSITION_TYPE_BUY \ && ( tailPrice == 0 || PositionInfo.PriceOpen() < tailPrice ) ) tailPrice = PositionInfo.PriceOpen();
      if ( PositionInfo.PositionType() == POSITION_TYPE_SELL \ && ( tailPrice == 0 || PositionInfo.PriceOpen() > tailPrice ) ) tailPrice = PositionInfo.PriceOpen();
   }
};

input double InpTakeProfitPips   = 20.0;  // Take profit pips
input double InpGridSizePips     = 20.0;  // Grid spacing pips
input double InpMartingaleFactor = 0.2;   // Martingale exponential growth (1+g)^n
input double InpRecoveryPips     = 100.0; // Martingale max recovery pips
input double InpExpansionFactor  = 0.2;   // Grid size expansion factor
input bool   InpUseAveraging     = false; // Close at an average price

input double InpVolume           = 0.01;     // initial Volume
input long   InpMagic            = 250800;   // Magic
const string InpComment          = "Expanding Grid"; // Trade comment

double       TakeProfit;
double       GridSize;
double       Recovery;

CLegData     BuyData;
CLegData     SellData;

;
int OnInit() {

   Trade.SetExpertMagicNumber( InpMagic );

   TakeProfit = PipsToDouble( Symbol(), InpTakeProfitPips );
   GridSize   = PipsToDouble( Symbol(), InpGridSizePips );
   Recovery   = InpRecoveryPips == 0 ? 0 : PipsToDouble( Symbol(), InpRecoveryPips ) - TakeProfit;

   BuyData.Init();
   SellData.Init();

   return ( INIT_SUCCEEDED );
}

void OnDeinit( const int reason ) {}

void OnTick() {

   MqlTick tick;
   SymbolInfoTick( Symbol(), tick );

   double buyGridSize  = GetGridSize( BuyData );
   double sellGridSize = GetGridSize( SellData );

   if ( BuyData.count == 0 || tick.ask <= ( BuyData.tailPrice - buyGridSize ) ) {
      OpenTrade( ORDER_TYPE_BUY, BuyData );
   }
   if ( InpUseAveraging ) {
      UpdateTakeProfit( POSITION_TYPE_BUY, BuyData.averagePrice + TakeProfit );
   }

   if ( SellData.count == 0 || tick.bid >= ( SellData.tailPrice + sellGridSize ) ) {
      OpenTrade( ORDER_TYPE_SELL, SellData );
   }
   if ( InpUseAveraging ) {
      UpdateTakeProfit( POSITION_TYPE_SELL, SellData.averagePrice - TakeProfit );
   }
}

void OnTradeTransaction( const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result ) {

   if ( trans.symbol != Symbol() ) return;
   if ( trans.type != TRADE_TRANSACTION_DEAL_ADD ) return;

   GetPositionData( BuyData, SellData );
}

double GetGridSize( CLegData &data ) {

   double gridSize = ( data.count <= 1 ) ? GridSize : GridSize * pow( ( 1 + InpExpansionFactor ), ( data.count ) );

   return gridSize;
}

void GetPositionData( CLegData &buyData, CLegData &sellData ) {

   buyData.Init();
   sellData.Init();

   for ( int i = PositionsTotal() - 1; i >= 0; i-- ) {

      if ( !SelectPosition( i ) ) continue;

      if ( PositionInfo.PositionType() == POSITION_TYPE_BUY ) {
         buyData.Update();
      }
      else {
         sellData.Update();
      }
   }
}

void UpdateTakeProfit( ENUM_POSITION_TYPE type, double takeProfitPrice ) {

   takeProfitPrice = NormalizeDouble( takeProfitPrice, Digits() );

   for ( int i = PositionsTotal() - 1; i >= 0; i-- ) {

      if ( !SelectPosition( i, type ) ) continue;

      if ( takeProfitPrice != PositionInfo.TakeProfit() ) {
         Trade.PositionModify( PositionInfo.Ticket(), PositionInfo.StopLoss(), takeProfitPrice );
      }
   }
}

void OpenTrade( ENUM_ORDER_TYPE type, CLegData &data ) {

   MqlTick tick;
   SymbolInfoTick( Symbol(), tick );

   double openPrice       = ( type == ORDER_TYPE_BUY ) ? tick.ask : tick.bid;
   openPrice              = NormalizeDouble( openPrice, Digits() );
   double volume          = GetVolume( type, data, openPrice );

   double takeProfitPrice = 0;
   if ( !InpUseAveraging ) {
      takeProfitPrice = ( type == ORDER_TYPE_BUY ) ? openPrice + TakeProfit : openPrice - TakeProfit;
      takeProfitPrice = NormalizeDouble( takeProfitPrice, Digits() );
   }

   if ( Trade.PositionOpen( Symbol(), type, volume, openPrice, 0, takeProfitPrice, InpComment ) ) {
      data.volPrice += Trade.ResultPrice() * Trade.ResultVolume();
      data.volTotal += Trade.ResultVolume();
      data.averagePrice = data.volPrice / data.volTotal;
   }
}

double GetVolume( ENUM_ORDER_TYPE type, CLegData &data, double price ) {

   double volume = InpVolume * pow( ( 1 + InpMartingaleFactor ), data.count );
   volume        = NormalizeDouble( volume, 2 );

   if ( Recovery == 0 ) return volume;

   double newVolTotal = data.volTotal + volume;
   double newVolPrice = data.volPrice + ( volume * price );
   double newAverage  = newVolPrice / newVolTotal;

   if ( ( type == ORDER_TYPE_BUY && newAverage <= ( price + Recovery ) )       //
        || ( type == ORDER_TYPE_SELL && newAverage >= ( price - Recovery ) ) ) //
      return volume;

   newAverage = ( type == ORDER_TYPE_BUY ) ? price + Recovery : price - Recovery;

   volume     = ( ( data.volPrice / newAverage ) - data.volTotal ) / ( 1 - ( price / newAverage ) );

   volume     = NormalizeDouble( volume, 2 );

   return volume;
}

bool SelectPosition( int index ) {

   if ( !PositionInfo.SelectByIndex( index ) ) return false;
   if ( PositionInfo.Symbol() != Symbol() ) return false;
   if ( PositionInfo.Magic() != InpMagic ) return false;

   return true;
}

bool SelectPosition( int index, int type ) {

   if ( !SelectPosition( index ) ) return false;
   if ( PositionInfo.PositionType() != type ) return false;

   return true;
}

double PipsToDouble( string symbol, double pips ) { return PointsToDouble( symbol, PipsToPoints( symbol, pips ) ); }

int    PipsToPoints( string symbol, double pips ) {
   int d = ( int )SymbolInfoInteger( symbol, SYMBOL_DIGITS );
   return ( int )( pips * ( ( d == 3 || d == 5 ) ? 10 : 1 ) );
}

double PointsToDouble( string symbol, int points ) { return ( points * SymbolInfoDouble( symbol, SYMBOL_POINT ) ); }
