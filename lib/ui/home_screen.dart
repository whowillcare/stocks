import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'package:intl/intl.dart';
import '../domain/model/search_result.dart';
import '../domain/model/stock_data.dart' as domain; // Alias to avoid collision
import 'home_provider.dart';
import 'stock_session.dart';
import '../domain/strategy/strategy.dart'; // For calculation logic

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  Widget build(BuildContext context) {
    return Consumer<HomeProvider>(
      builder: (context, provider, child) {
        
        return DefaultTabController(
            key: ValueKey(provider.sessions.length), // Rebuilds controller when count changes
            length: provider.sessions.length,
            initialIndex: provider.currentSessionIndex < provider.sessions.length ? provider.currentSessionIndex : 0,
            child: Scaffold(
              appBar: AppBar(
                title: const Text('Stock Analyzer'),
                actions: [
                     IconButton(
                         icon: const Icon(Icons.settings),
                         tooltip: 'Global Strategy Settings',
                         onPressed: () => _showGlobalSettingsDialog(context, provider),
                     )
                ],
                bottom: PreferredSize(
                  preferredSize: const Size.fromHeight(48),
                  child: Row(
                    children: [
                      Expanded(
                        child: TabBar(
                          isScrollable: true,
                          // DefaultTabController manages the controller implicitly
                          onTap: (index) => provider.setCurrentSession(index),
                          tabs: provider.sessions.map((s) => Tab(
                              child: Row(
                                  children: [
                                      Text(s.title),
                                      const SizedBox(width: 4),
                                      InkWell(
                                          onTap: () => provider.removeSession(provider.sessions.indexOf(s)), 
                                          child: const Icon(Icons.close, size: 16)
                                      )
                                  ]
                              )
                          )).toList(),
                        ),
                      ),
                      
                      // Add Button with Long Press History
                      GestureDetector(
                          onLongPressStart: (details) {
                              _showHistoryMenu(context, details.globalPosition, provider);
                          },
                          child: IconButton(
                            icon: const Icon(Icons.add),
                            onPressed: () => provider.addSession(),
                            tooltip: 'Add Tab (Long press for History)',
                          ),
                      ),
                    ],
                  ),
                ),
              ),
              body: Builder(
                builder: (context) {
                  // Sync provider index with TabController changes
                  final controller = DefaultTabController.of(context);
                  controller.addListener(() {
                    if (!controller.indexIsChanging && controller.index != provider.currentSessionIndex) {
                       // We can't update provider during build/notify cycle easily if this triggers loop
                       // Ideally provider is source of truth.
                       // With DefaultTabController re-creating, we rely on initialIndex.
                       // For user swipes: we need to update provider.
                       // But avoiding loop is key.
                       // We'll update only if different.
                       // Use addPostFrameCallback if needed or just separate check.
                       if (provider.currentSessionIndex != controller.index) {
                           // Use Future to avoid build-phase update
                           Future.microtask(() => provider.setCurrentSession(controller.index));
                       }
                    }
                  });
                  
                  return TabBarView(
                    children: provider.sessions.map((session) => _SessionView(session: session)).toList(),
                  );
                }
              ),
            )
        );
      },
    );
  }
  void _showHistoryMenu(BuildContext context, Offset offset, HomeProvider provider) {
      if (provider.searchHistory.isEmpty) return;
      
      showMenu<String>(
          context: context,
          position: RelativeRect.fromLTRB(offset.dx, offset.dy, offset.dx, offset.dy),
          items: provider.searchHistory.map((s) => PopupMenuItem(
              value: s,
              child: Text(s),
          )).toList(),
      ).then((value) {
          if (value != null) {
              provider.addSession();
              Future.microtask(() {
                  provider.fetchStockData(value);
              });
          }
      });
  }

  void _showGlobalSettingsDialog(BuildContext context, HomeProvider provider) {
      showDialog(
          context: context,
          builder: (context) {
              // Temp state for settings dialog
              int tempAtrPeriod = provider.atrPeriod;
              double tempAtrMult = provider.atrMultiplier;
              int tempEmaPeriod = provider.emaPeriod;
              
              double tempFomo = provider.scoreFomo;
              double tempSlightlyAbove = provider.scoreSlightlyAbove;
              double tempOptimal = provider.scoreOptimal;
              double tempFallingKnife = provider.scoreFallingKnife;
              double tempVolumeSpike = provider.scoreVolumeSpike;
              double tempSideways = provider.scoreSideways;

              return StatefulBuilder(
                  builder: (context, setState) {
                      return AlertDialog(
                          title: const Text('Global Settings'),
                          content: SingleChildScrollView(
                              child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                      const Text('Strategy Params', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.blue)),
                                      const Divider(),
                                      const Text('ATR Strategy', style: TextStyle(fontWeight: FontWeight.bold)),
                                      Row(
                                          children: [
                                              Expanded(child: TextField(
                                                  decoration: const InputDecoration(labelText: 'Period'),
                                                  keyboardType: TextInputType.number,
                                                  controller: TextEditingController(text: tempAtrPeriod.toString()),
                                                  onChanged: (v) => tempAtrPeriod = int.tryParse(v) ?? tempAtrPeriod,
                                              )),
                                              const SizedBox(width: 8),
                                              Expanded(child: TextField(
                                                  decoration: const InputDecoration(labelText: 'Multiplier'),
                                                  keyboardType: TextInputType.number,
                                                  controller: TextEditingController(text: tempAtrMult.toString()),
                                                  onChanged: (v) => tempAtrMult = double.tryParse(v) ?? tempAtrMult,
                                              )),
                                          ],
                                      ),
                                      const SizedBox(height: 8),
                                      const Text('EMA Strategy', style: TextStyle(fontWeight: FontWeight.bold)),
                                      TextField(
                                          decoration: const InputDecoration(labelText: 'Period'),
                                          keyboardType: TextInputType.number,
                                          controller: TextEditingController(text: tempEmaPeriod.toString()),
                                          onChanged: (v) => tempEmaPeriod = int.tryParse(v) ?? tempEmaPeriod,
                                      ),
                                      const SizedBox(height: 20),
                                      const Text('Risk Analysis Scores', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.blue)),
                                      const Divider(),
                                      _buildScoreInput('Price >> EMA (FOMO)', tempFomo, (v) => tempFomo = v),
                                      _buildScoreInput('Price > EMA', tempSlightlyAbove, (v) => tempSlightlyAbove = v),
                                      _buildScoreInput('Price ~ EMA (Optimal)', tempOptimal, (v) => tempOptimal = v),
                                      _buildScoreInput('Price < EMA (Falling Knife)', tempFallingKnife, (v) => tempFallingKnife = v),
                                      _buildScoreInput('Volume Spike', tempVolumeSpike, (v) => tempVolumeSpike = v),
                                      _buildScoreInput('Sideways Trend', tempSideways, (v) => tempSideways = v),
                                  ],
                              ),
                          ),
                          actions: [
                              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                              TextButton(
                                  onPressed: () {
                                      provider.updateGlobalAtrParams(period: tempAtrPeriod, multiplier: tempAtrMult);
                                      provider.updateGlobalEmaParams(period: tempEmaPeriod);
                                      provider.updateTrendParams(
                                          fomo: tempFomo,
                                          slightlyAbove: tempSlightlyAbove,
                                          optimal: tempOptimal,
                                          fallingKnife: tempFallingKnife,
                                          volumeSpike: tempVolumeSpike,
                                          sideways: tempSideways,
                                      );
                                      Navigator.pop(context);
                                  }, 
                                  child: const Text('Save')
                              ),
                          ],
                      );
                  }
              );
          }
      );
  }

  Widget _buildScoreInput(String label, double value, Function(double) onChanged) {
      return Row(
          children: [
              Expanded(flex: 3, child: Text(label, style: const TextStyle(fontSize: 12))),
              Expanded(
                  flex: 2,
                  child: SizedBox(
                      height: 35,
                      child: TextField(
                          decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 8)),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                          controller: TextEditingController(text: value.toString()),
                          onChanged: (v) {
                              final d = double.tryParse(v);
                              if (d != null) onChanged(d);
                          },
                      ),
                  ),
              ),
          ],
      );
  }
}

class _SessionView extends StatefulWidget {
  final StockSession session;

  const _SessionView({required this.session});

  @override
  State<_SessionView> createState() => _SessionViewState();
}

class _SessionViewState extends State<_SessionView> {
  bool _isMaximized = false;

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<HomeProvider>(context, listen: false);
    final session = widget.session;

    if (_isMaximized) {
        return SessionChart(
            session: session,
            isMaximized: true,
            onToggleMaximize: () => setState(() => _isMaximized = !_isMaximized),
        );
    }

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Column(
              children: [
                _buildSearchSection(context, provider, session),
                const SizedBox(height: 16),
                _buildStrategyConfig(context, provider, session),
                const SizedBox(height: 16),
                _buildEntryConfig(context, provider, session),
                const SizedBox(height: 16),
                _buildResults(session),
                const SizedBox(height: 16),
              ],
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 500,
              child: SessionChart(
                  session: session,
                  isMaximized: false,
                  onToggleMaximize: () => setState(() => _isMaximized = !_isMaximized),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchSection(BuildContext context, HomeProvider provider, StockSession session) {
    return Row(
      children: [
        Expanded(
          child: Autocomplete<StockSearchResult>(
            displayStringForOption: (option) => option.symbol,
            optionsBuilder: (TextEditingValue textEditingValue) {
               return provider.searchCandidates(textEditingValue.text);
            },
            onSelected: (StockSearchResult selection) {
               provider.fetchStockData(selection.symbol);
            },
            fieldViewBuilder: (context, textEditingController, focusNode, onFieldSubmitted) {
                if (session.symbol != null && textEditingController.text.isEmpty) {
                    textEditingController.text = session.symbol!;
                }
                return TextField(
                    controller: textEditingController,
                    focusNode: focusNode,
                    decoration: const InputDecoration(
                        labelText: 'Search Stock (e.g. AAPL)',
                        border: OutlineInputBorder(),
                    ),
                    onSubmitted: (value) {
                         provider.fetchStockData(value.toUpperCase());
                    },
                );
            },
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: 'Force Refresh',
          onPressed: () {
            if (session.symbol != null) {
              provider.fetchStockData(session.symbol!, forceRefresh: true);
            }
          },
        ),
      ],
    );
  }

  Widget _buildEntryConfig(BuildContext context, HomeProvider provider, StockSession session) {
    return _EntryInputSection(
      entryDate: session.entryDate,
      entryPrice: session.entryPrice,
      onUpdate: (date, price) => provider.updateEntryParams(entryDate: date, entryPrice: price),
      onClear: () => provider.clearEntryParams(),
    );
  }

  Widget _buildStrategyConfig(BuildContext context, HomeProvider provider, StockSession session) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Stop Strategy (Configured Globally)', style: TextStyle(fontWeight: FontWeight.bold)),
            DropdownButton<int>(
              value: session.selectedStrategyIndex,
              items: const [
                DropdownMenuItem(value: 0, child: Text('ATR Trailing Stop')),
                DropdownMenuItem(value: 1, child: Text('EMA Stop')),
              ],
              onChanged: (value) {
                if (value != null) provider.setStrategyIndex(value);
              },
            ),
          ],
        ),
      ),
    );
  }


  Widget _buildResults(StockSession session) {
    if (session.isLoading) return const CircularProgressIndicator();
    if (session.errorMessage != null) return Text('Error: ${session.errorMessage}', style: const TextStyle(color: Colors.red));
    if (session.stockQuote == null) return const Text('Enter a symbol to start.');

    final lastCandle = session.stockQuote!.candles.last;
    final lastClose = lastCandle.close;
    final cutLoss = session.cutLossPrice ?? 0.0;
    final trailing = session.trailingStopPrice;
    
    final date = DateTime.fromMillisecondsSinceEpoch(lastCandle.date * 1000);
    final dateStr = DateFormat('yyyy-MM-dd').format(date);
    
    final trendAnalysis = session.trendAnalysis;

    return Card(
      color: Colors.blue.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
             Text('Date: $dateStr', style: const TextStyle(fontStyle: FontStyle.italic)),
             Text('Current Price: ${lastClose.toStringAsFixed(2)}', style: const TextStyle(fontSize: 18)),
             const Divider(),
             Row(
                 mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                 children: [
                     Column(
                         children: [
                             const Text('Cut Loss', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                             Text(cutLoss.toStringAsFixed(2), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.red)),
                         ],
                     ),
                     if (trailing != null)
                     Column(
                         children: [
                             const Text('Trailing Profit', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                             Text(trailing.toStringAsFixed(2), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green)),
                         ],
                     ),
                 ],
             ),
              if (session.entryPrice != null) ...[
                  const SizedBox(height: 8),
                  Text('Entry Risk: ${((session.entryPrice! - cutLoss) / session.entryPrice! * 100).toStringAsFixed(2)}%', style: const TextStyle(color: Colors.redAccent)),
              ],
              
              const SizedBox(height: 8),
              if (trendAnalysis != null) ...[
                  const Divider(),
                  Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                          color: _getRiskColor(trendAnalysis.riskLevel).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: _getRiskColor(trendAnalysis.riskLevel)),
                      ),
                      child: Column(
                          children: [
                              Text('Risk Level: ${trendAnalysis.riskLevel} (Score: ${trendAnalysis.score})', 
                                  style: TextStyle(fontWeight: FontWeight.bold, color: _getRiskColor(trendAnalysis.riskLevel))),
                              const SizedBox(height: 4),
                              Text('Trend: ${trendAnalysis.trend}', style: const TextStyle(fontWeight: FontWeight.bold)),
                              const SizedBox(height: 4),
                              Text(trendAnalysis.details, style: const TextStyle(fontSize: 11), textAlign: TextAlign.center),
                              
                              const Divider(),
                              const Text('Safe Entry Analysis (Intraday)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                              const SizedBox(height: 4),
                              Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                      Text('Range: ', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                      Text('[${trendAnalysis.safeRangeLow.toStringAsFixed(2)} - ${trendAnalysis.safeRangeHigh.toStringAsFixed(2)}]', 
                                          style: const TextStyle(fontSize: 12, fontFamily: 'Monospace')),
                                  ],
                              ),
                              const SizedBox(height: 4),
                              Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                      color: trendAnalysis.isSafeEntry ? Colors.green.shade100 : Colors.red.shade100,
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: trendAnalysis.isSafeEntry ? Colors.green : Colors.red),
                                  ),
                                  child: Text(
                                      trendAnalysis.isSafeEntry ? 'SAFE TO ENTER' : trendAnalysis.safeEntrySignal,
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold, 
                                          fontSize: 12, 
                                          color: trendAnalysis.isSafeEntry ? Colors.green.shade900 : Colors.red.shade900
                                      ),
                                      textAlign: TextAlign.center,
                                  ),
                              ),
                          ],
                      ),
                  ),
              ],
              
              const SizedBox(height: 8),
              // EMA Display
              Wrap(
                  spacing: 12,
                  children: [
                      Text('EMA10: ${EmaStopStrategy.calculateValidSeries(session.stockQuote!.candles, 10).last?.toStringAsFixed(2) ?? '-'}', style: const TextStyle(color: Colors.blue, fontSize: 12)),
                      Text('EMA20: ${EmaStopStrategy.calculateValidSeries(session.stockQuote!.candles, 20).last?.toStringAsFixed(2) ?? '-'}', style: const TextStyle(color: Colors.orange, fontSize: 12)),
                      Text('EMA50: ${EmaStopStrategy.calculateValidSeries(session.stockQuote!.candles, 50).last?.toStringAsFixed(2) ?? '-'}', style: const TextStyle(color: Colors.purple, fontSize: 12)),
                  ],
              ),
              const SizedBox(height: 8),
              Text(session.equation ?? '', style: const TextStyle(fontSize: 12, color: Colors.grey), textAlign: TextAlign.center),
           ],
         ),
       ),
     );
   }
   
   Color _getRiskColor(String level) {
       if (level.contains('Low')) return Colors.green;
       if (level.contains('Moderate')) return Colors.orange;
       if (level.contains('High')) return Colors.red;
       return Colors.grey;
   }
 

 }

class _EntryInputSection extends StatefulWidget {
  final DateTime? entryDate;
  final double? entryPrice;
  final Function(DateTime?, double?) onUpdate;
  final VoidCallback onClear;

  const _EntryInputSection({
    required this.entryDate,
    required this.entryPrice,
    required this.onUpdate,
    required this.onClear,
  });

  @override
  State<_EntryInputSection> createState() => _EntryInputSectionState();
}

class _EntryInputSectionState extends State<_EntryInputSection> {
  late TextEditingController _priceController;

  @override
  void initState() {
    super.initState();
    _priceController = TextEditingController(text: widget.entryPrice?.toString() ?? '');
  }

  @override
  void didUpdateWidget(covariant _EntryInputSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.entryPrice != oldWidget.entryPrice) {
        if (widget.entryPrice == null) {
            _priceController.text = '';
        } else if (double.tryParse(_priceController.text) != widget.entryPrice) {
             _priceController.text = widget.entryPrice.toString();
        }
    }
  }

  @override
  void dispose() {
    _priceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                    const Text('Optional Entry Details', style: TextStyle(fontWeight: FontWeight.bold)),
                    if (widget.entryDate != null || widget.entryPrice != null)
                        TextButton(onPressed: widget.onClear, child: const Text('Clear'))
                ],
            ),
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: widget.entryDate ?? DateTime.now(),
                        firstDate: DateTime(2000),
                        lastDate: DateTime.now().add(const Duration(days: 1)), // Allow today/tomorrow for timezone safety
                      );
                      if (picked != null) {
                        widget.onUpdate(picked, widget.entryPrice);
                      }
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Entry Date',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      ),
                      child: Text(
                        widget.entryDate != null ? DateFormat('yyyy-MM-dd').format(widget.entryDate!) : 'Select Date',
                        style: TextStyle(color: widget.entryDate != null ? Colors.black : Colors.grey),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _priceController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                        labelText: 'Entry Price',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    ),
                    onChanged: (val) {
                         widget.onUpdate(widget.entryDate, double.tryParse(val));
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class SessionChart extends StatefulWidget {
  final StockSession session;
  final bool isMaximized;
  final VoidCallback onToggleMaximize;

  const SessionChart({
    super.key,
    required this.session,
    required this.isMaximized,
    required this.onToggleMaximize,
  });

  @override
  State<SessionChart> createState() => _SessionChartState();
}

class _SessionChartState extends State<SessionChart> {
  late ZoomPanBehavior _zoomPanBehavior;
  late TrackballBehavior _trackballBehavior;
  DateTime? _visibleMin;
  DateTime? _visibleMax;
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _zoomPanBehavior = ZoomPanBehavior(
      enablePinching: true,
      enablePanning: true,
      enableMouseWheelZooming: true,
      zoomMode: ZoomMode.x,
    );
    _trackballBehavior = TrackballBehavior(
      enable: true,
      activationMode: ActivationMode.singleTap,
      tooltipDisplayMode: TrackballDisplayMode.floatAllPoints,
    );

    // Attempt init
    if (widget.session.stockQuote != null) {
      _resetVisibleRange();
    }
  }
  
  @override
  void didUpdateWidget(SessionChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.session.symbol != oldWidget.session.symbol) {
       _resetVisibleRange();
    } else if (_visibleMin == null && widget.session.stockQuote != null) {
       _resetVisibleRange();
    }
  }
  
  void _resetVisibleRange() {
      final candles = widget.session.stockQuote?.candles;
      if (candles == null || candles.isEmpty) return;
      
      final provider = Provider.of<HomeProvider>(context, listen: false);
      final lastDate = DateTime.fromMillisecondsSinceEpoch(candles.last.date * 1000);
      
      // Default to visibleDays from provider
      final days = provider.visibleDays;
      setState(() {
          _visibleMin = lastDate.subtract(Duration(days: days));
          _visibleMax = lastDate.add(Duration(hours: 12)); // Small buffer to show the last candle clearly
      });
  }

  @override
  void dispose() {
      _debounceTimer?.cancel();
      super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.session.stockQuote == null) return const SizedBox();

    final candles = widget.session.stockQuote!.candles;

    return Stack(
      children: [
        SfCartesianChart(
          onActualRangeChanged: (ActualRangeChangedArgs args) {
              if (args.axisName == 'primaryXAxis') {
                  final minMillis = args.visibleMin as num?;
                  final maxMillis = args.visibleMax as num?;
                  
                  if (minMillis != null && maxMillis != null) {
                       _debounceTimer?.cancel();
                       _debounceTimer = Timer(const Duration(milliseconds: 800), () {
                           if (!mounted) return;
                           final diff = maxMillis - minMillis;
                           final days = (diff / (1000 * 3600 * 24)).round();
                           Provider.of<HomeProvider>(context, listen: false).updateVisibleDays(days);
                       });
                  }
              }
          },
          primaryXAxis: DateTimeAxis(
            name: 'primaryXAxis',
            majorGridLines: const MajorGridLines(width: 0),
            initialVisibleMinimum: _visibleMin,
            initialVisibleMaximum: _visibleMax,
          ),
          primaryYAxis: NumericAxis(
            opposedPosition: true,
            majorGridLines: const MajorGridLines(width: 0.5),
          ),
          zoomPanBehavior: _zoomPanBehavior,
          trackballBehavior: _trackballBehavior,
          indicators: [
            EmaIndicator<domain.Candle, DateTime>(
              name: 'EMA 10',
              seriesName: 'Candles',
              period: 10,
              valueField: 'close',
              signalLineColor: Colors.blue,
            ),
            EmaIndicator<domain.Candle, DateTime>(
              name: 'EMA 20',
              seriesName: 'Candles',
              period: 20,
              valueField: 'close',
              signalLineColor: Colors.orange,
            ),
            EmaIndicator<domain.Candle, DateTime>(
              name: 'EMA 50',
              seriesName: 'Candles',
              period: 50,
              valueField: 'close',
              signalLineColor: Colors.purple,
            ),
          ],
          series: <CartesianSeries<domain.Candle, DateTime>>[
            CandleSeries<domain.Candle, DateTime>(
              name: 'Candles',
              dataSource: candles,
              xValueMapper: (domain.Candle c, _) => DateTime.fromMillisecondsSinceEpoch(c.date * 1000),
              lowValueMapper: (domain.Candle c, _) => c.low,
              highValueMapper: (domain.Candle c, _) => c.high,
              openValueMapper: (domain.Candle c, _) => c.open,
              closeValueMapper: (domain.Candle c, _) => c.close,
            )
          ],
        ),
        Positioned(
          right: 8,
          top: 8,
          child: Container(
            color: Colors.black26,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: Icon(widget.isMaximized ? Icons.close_fullscreen : Icons.open_in_full, color: Colors.white),
                  onPressed: widget.onToggleMaximize,
                )
              ],
            ),
          ),
        )
      ],
    );
  }
}
