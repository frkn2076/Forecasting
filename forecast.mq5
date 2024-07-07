//+------------------------------------------------------------------+
//|                                                       FURKAN.mq5 |
//|                        Copyright 2024, MetaQuotes Software Corp. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+

#include <Trade\Trade.mqh>
#include <Trade\OrderInfo.mqh>
#property strict

// Include necessary WinAPI declarations
#import "shell32.dll"
   int ShellExecuteW(int hwnd, string lpOperation, string lpFile, string lpParameters, string lpDirectory, int nShowCmd);
#import

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
CTrade trade;
COrderInfo     m_order;
string mySymbol = "GBPUSD";

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
  {
   Print("Started");
   OnTimer();
   EventSetTimer(60 * 60); // 1 hour
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OnTick()
  {
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OnTimer()
  {
   Print("Leverage: ", AccountInfoInteger(ACCOUNT_LEVERAGE));
   
   CallPredictor("predictor");
    
   // Wait 30 seconds -> 30 * 1000
   Print("Waiting python script to be completed!");
   Sleep(30 * 1000);
    
   double currentBuyPrice = SymbolInfoDouble(mySymbol,SYMBOL_ASK);
   double currentSellPrice = SymbolInfoDouble(mySymbol,SYMBOL_BID);
   double freeMargin = AccountInfoDouble(ACCOUNT_FREEMARGIN);
   double accountProfit = AccountInfoDouble(ACCOUNT_PROFIT);

   double spread = MathAbs(currentSellPrice - currentBuyPrice);
   
   double minPrediction, maxPrediction;
   GetPrediction("predictor", minPrediction, maxPrediction);
   
   Print("CurrentBuyPrice: ", currentBuyPrice);
   Print("CurrentSellPrice: ", currentSellPrice);
   Print("Account Profit: ", accountProfit);

   if(spread < 1 && freeMargin > 250)
     {
      if(maxPrediction > (currentBuyPrice + 0.0002))
      {
         double margin = (maxPrediction - currentBuyPrice) * 0.7;
         Print("Margin:", margin);
         Print("maxPrediction:", maxPrediction);
         Print("currentBuyPrice:", currentBuyPrice);
         Print("(maxPrediction - currentBuyPrice) * 0.7:", (maxPrediction - currentBuyPrice) * 0.7);
         BuyDirectly(currentBuyPrice, spread + margin);
      }
      
      if(minPrediction < (currentSellPrice - 0.0002)) 
      {
         double margin = (currentSellPrice - minPrediction) * 0.7;
         Print("Margin:", margin);
         Print("minPrediction:", minPrediction);
         Print("currentSellPrice:", currentSellPrice);
         Print("(currentSellPrice - minPrediction) * 0.7:", (currentSellPrice - minPrediction) * 0.7);
         SellDirectly(currentSellPrice, spread + margin);
      }
     }
   else 
    {
      Print("No order since Spread is: ", spread, " and free margin is: ", freeMargin);
    }
  }
  
void CallPredictor(string path)
{
    string folderPath = "C:\\Users\\Furkan\\AppData\\Roaming\\MetaQuotes\\Terminal\\D0E8209F77C8CF37AD8BF550E51FF075\\MQL5\\Files\\" + path + "\\";
    string command = "cd /d " + folderPath + " && python predictor.py";
    string logFilePath = "logs.txt";
   
   // Execute the command within the folder
    int scriptResult = ShellExecuteW(0, "open", "cmd.exe", "/c " + command + " > " + logFilePath + " 2>&1", "", 0);
    if(scriptResult > 32)
    {
        Print("Batch file executed successfully for ", path);
    }
    else
    {
        Print("Error executing batch file. Error code: ", scriptResult, "path: ", path);
        ExpertRemove();
        return;
    }
}

void GetPrediction(string path, double &outDouble1, double &outDouble2)
  {
  
  int handle = FileOpen(path + "\\prediction.txt", FILE_READ|FILE_ANSI|FILE_TXT);
   
   // Check if the file was successfully opened
   if (handle < 0)
     {
      Print("Error opening prediction.txt file:", handle, " path: ", path);
      Print(GetLastError());
      ExpertRemove();
      return;
     }
   
   // Read the result from the file
   string resultStr = FileReadString(handle);
   FileClose(handle);

   string result[];
   StringSplit(resultStr, ',', result);
   
   // Convert result to double
   double minPrediction = StringToDouble(result[0]);
   double maxPrediction = StringToDouble(result[1]);
   
   Print("Min prediction: ", minPrediction, " for ", path);
   Print("Max prediction:", maxPrediction, " for ", path);
   // Calculate or assign values to the output parameters
   outDouble1 = minPrediction;
   outDouble2 = maxPrediction;
  }

void BuyDirectly(double ask, double profit)
  {
   Print(" -- Buy Order  -- Ask:", ask, ", tp:", ask+profit);
   trade.BuyLimit(0.01,ask,mySymbol,0,ask+profit);
  }

void SellDirectly(double bid, double profit)
  {
   Print(" -- Sell Order  -- Bid:", bid, ", tp:", bid-profit);
   trade.SellLimit(0.01,bid,mySymbol,0,bid-profit);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int HasActivePosition(ENUM_POSITION_TYPE positionType, double checkPrice, double margin)
  {
   for(int i = 0; i < PositionsTotal(); i++)
     {
      if(PositionGetTicket(i) && PositionGetInteger(POSITION_TYPE) == positionType)
        {
         double positionPrice= PositionGetDouble(POSITION_PRICE_OPEN);
         double normalizedPositionPrice = NormalizeDouble(positionPrice, 4);
         double normalizedCheckPrice = NormalizeDouble(checkPrice, 4);
         if(MathAbs(normalizedCheckPrice - normalizedPositionPrice) <= margin)
           {
            Print("Has active position");
            return true;
           }
        }
     }
   Print("No active position");
   return false;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool HasActiveOrder(ENUM_ORDER_TYPE type, double checkPrice, double margin)
  {
   ENUM_POSITION_TYPE type2 = type == ORDER_TYPE_BUY_LIMIT ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
   for(int i=OrdersTotal()-1; i>=0; i--)
     {
      if(m_order.SelectByIndex(i))
        {
         if(m_order.OrderType()== type)
           {
            double orderPrice= m_order.PriceOpen();
            double normalizedOrderPrice = NormalizeDouble(orderPrice, 4);
            double normalizedCheckPrice = NormalizeDouble(checkPrice, 4);
            if(MathAbs(normalizedCheckPrice - normalizedOrderPrice) <= margin)
              {
               Print("Has active order");
               return true;
              }
           }
        }
     }
   Print("No active order");
   return false;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int PositionCount(ENUM_POSITION_TYPE positionType)
  {
   int res = 0;
   for(int i = 0; i < PositionsTotal(); i++)
     {
      if(PositionGetTicket(i) && PositionGetInteger(POSITION_TYPE) == positionType)
        {
         res++;
        }
     }
   return res;
  }
  
void StringSplit(const string inputData, const string delimiter, string &result[])
{
   // Initialize variables
   int startPos = 0;
   int endPos = StringFind(inputData, delimiter, startPos);
   int index = 0;

   // Loop until no more delimiters are found
   while (endPos != -1)
   {
      // Get the substring from startPos to endPos
      result[index] = StringSubstr(inputData, startPos, endPos - startPos);
      // Update startPos to the character after the current delimiter
      startPos = endPos + StringLen(delimiter);
      // Find the next delimiter
      endPos = StringFind(inputData, delimiter, startPos);
      // Move to the next index in the result array
      index++;
   }

   // Add the last substring (or the whole string if no delimiter was found)
   result[index] = StringSubstr(inputData, startPos, StringLen(inputData) - startPos);
}

void CloseAllPositionsAndOrders()
{

    // Close all positions
    for(int i = 0; i < PositionsTotal(); i++)
     {
      if(PositionGetTicket(i))
        {
           ulong positionTicket = PositionGetTicket(i);
           if(!trade.PositionClose(positionTicket))
           {
               Print("Failed to close position: ", trade.ResultRetcode(), " ", trade.ResultRetcodeDescription());
           }
        }
     }
    
    
    
    // Delete all pending orders
    for(int i=OrdersTotal()-1; i>=0; i--)
     {
      if(m_order.SelectByIndex(i))
        {
        ulong orderTicket = OrderGetTicket(i);
         if(!trade.OrderDelete(orderTicket))
            {
               Print("Failed to delete order: ", trade.ResultRetcode(), " ", trade.ResultRetcodeDescription());
            }
        }
     }
    
    Print("All positions and orders have been closed/deleted.");
}
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
