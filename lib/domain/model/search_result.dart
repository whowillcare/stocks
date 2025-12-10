class StockSearchResult {
  final String symbol;
  final String shortname;
  final String exchange;

  StockSearchResult({
    required this.symbol,
    required this.shortname,
    required this.exchange,
  });
  
  @override
  String toString() => '$symbol - $shortname';
}
