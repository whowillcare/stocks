
import 'package:flutter_test/flutter_test.dart';
import 'package:stocks/domain/model/stock_data.dart';
import 'package:stocks/domain/strategy/strategy.dart';

void main() {
  group('Strategy Tests', () {
    test('ATR Stop Calculation', () {
      // Create a list of candles with known values
      // TRs:
      // Day 1: H-L=5, |H-Cp|=?, |L-Cp|=? -> Assume 5
      // Day 2: H-L=5
      
      final candles = List.generate(20, (i) {
        return Candle(
            date: i,
            open: 100,
            high: 105,
            low: 100,
            close: 102,
            volume: 1000
        );
      });
      // Last close is 102.
      // TR is max(5, |105-102|, |100-102|) = 5 (approx constant for this simplified data)
      // ATR should be 5.
      
      final strategy = AtrStopStrategy(period: 14, multiplier: 2.0);
      final stop = strategy.calculateStopPrice(candles);
      
      // Stop = LastClose - (ATR * 2) = 102 - (5 * 2) = 92
      expect(stop, closeTo(92.0, 0.1));
    });

    test('EMA Stop Calculation', () {
      final candles = List.generate(50, (i) {
        return Candle(
            date: i,
            open: 100,
            high: 100,
            low: 100,
            close: 100, // Constant price
            volume: 1000
        );
      });
      
      // EMA of constant series is the constant.
      final strategy = EmaStopStrategy(period: 20);
      final stop = strategy.calculateStopPrice(candles);
      
      expect(stop, closeTo(100.0, 0.1));
    });
  });
}
