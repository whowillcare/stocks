// Position sizing calculator for risk-based trade management
import 'dart:math';

class PositionSizingCalculator {
  /// Calculate number of shares to buy based on risk parameters
  /// 
  /// [accountSize]: Total account value in dollars
  /// [riskPercentage]: Risk per trade as decimal (e.g., 0.02 for 2%)
  /// [entryPrice]: Planned entry price per share
  /// [stopLoss]: Stop loss price per share
  /// 
  /// Returns number of shares to purchase (rounded down to whole shares)
  static int calculateShares({
    required double accountSize,
    required double riskPercentage,
    required double entryPrice,
    required double stopLoss,
  }) {
    if (entryPrice <= stopLoss) return 0; // Invalid: stop should be below entry
    
    final riskAmount = accountSize * riskPercentage;
    final priceRisk = entryPrice - stopLoss; // Risk per share
    final shares = (riskAmount / priceRisk).floor();
    
    return max(0, shares);
  }
  
  /// Calculate position size in dollars
  static double calculatePositionSize({
    required double accountSize,
    required double riskPercentage,
    required double entryPrice,
    required double stopLoss,
  }) {
    final shares = calculateShares(
      accountSize: accountSize,
      riskPercentage: riskPercentage,
      entryPrice: entryPrice,
      stopLoss: stopLoss,
    );
    
    return shares * entryPrice;
  }
  
  /// Calculate risk-reward ratio
  /// Returns how many R (risk units) the target represents
  static double calculateRiskRewardRatio({
    required double entryPrice,
    required double stopLoss,
    required double target,
  }) {
    final risk = entryPrice - stopLoss;
    if (risk <= 0) return 0;
    
    final reward = target - entryPrice;
    return reward / risk;
  }
}
