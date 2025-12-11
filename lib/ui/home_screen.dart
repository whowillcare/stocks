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
          key: ValueKey(
            provider.sessions.length,
          ), // Rebuilds controller when count changes
          length: provider.sessions.length,
          initialIndex: provider.currentSessionIndex < provider.sessions.length
              ? provider.currentSessionIndex
              : 0,
          child: Scaffold(
            appBar: AppBar(
              title: const Text('Stock Analyzer'),
              actions: [
                IconButton(
                  icon: const Icon(Icons.settings),
                  tooltip: 'Global Strategy Settings',
                  onPressed: () => _showGlobalSettingsDialog(context, provider),
                ),
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
                        tabs: provider.sessions
                            .map(
                              (s) => Tab(
                                child: Row(
                                  children: [
                                    Text(s.title),
                                    const SizedBox(width: 4),
                                    InkWell(
                                      onTap: () => provider.removeSession(
                                        provider.sessions.indexOf(s),
                                      ),
                                      child: const Icon(Icons.close, size: 16),
                                    ),
                                  ],
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ),

                    // Add Button with Long Press History
                    GestureDetector(
                      onLongPressStart: (details) {
                        _showHistoryMenu(
                          context,
                          details.globalPosition,
                          provider,
                        );
                      },
                      child: IconButton(
                        icon: const Icon(Icons.add),
                        onPressed: () => provider.addSession(),
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
                  if (!controller.indexIsChanging &&
                      controller.index != provider.currentSessionIndex) {
                    // We can't update provider during build/notify cycle easily if this triggers loop
                    // Ideally provider is source of truth.
                    // With DefaultTabController re-creating, we rely on initialIndex.
                    // For user swipes: we need to update provider.
                    // But avoiding loop is key.
                    // We'll update only if different.
                    // Use addPostFrameCallback if needed or just separate check.
                    if (provider.currentSessionIndex != controller.index) {
                      // Use Future to avoid build-phase update
                      Future.microtask(
                        () => provider.setCurrentSession(controller.index),
                      );
                    }
                  }
                });

                return TabBarView(
                  children: provider.sessions
                      .map((session) => _SessionView(session: session))
                      .toList(),
                );
              },
            ),
          ),
        );
      },
    );
  }

  void _showHistoryMenu(
    BuildContext context,
    Offset offset,
    HomeProvider provider,
  ) {
    if (provider.searchHistory.isEmpty) return;

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        offset.dx,
        offset.dy,
        offset.dx,
        offset.dy,
      ),
      items: provider.searchHistory
          .map((s) => PopupMenuItem(value: s, child: Text(s)))
          .toList(),
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
        int tempAtrPeriod = provider.atrPeriod;
        double tempStopMult = provider.atrMultiplier;
        double tempTrailMult = provider.trailMultiplier;
        int tempEmaPeriod = provider.emaPeriod;

        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Global Strategy Settings'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'ATR Strategy',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  TextField(
                    decoration: const InputDecoration(labelText: 'Period'),
                    keyboardType: TextInputType.number,
                    controller: TextEditingController(
                      text: tempAtrPeriod.toString(),
                    ),
                    onChanged: (v) =>
                        tempAtrPeriod = int.tryParse(v) ?? tempAtrPeriod,
                  ),
                  TextField(
                    decoration: const InputDecoration(
                      labelText: 'Stop Loss Multiplier (ISL)',
                    ),
                    keyboardType: TextInputType.number,
                    controller: TextEditingController(
                      text: tempStopMult.toString(),
                    ),
                    onChanged: (v) =>
                        tempStopMult = double.tryParse(v) ?? tempStopMult,
                  ),
                  TextField(
                    decoration: const InputDecoration(
                      labelText: 'Trailing Stop Multiplier',
                    ),
                    keyboardType: TextInputType.number,
                    controller: TextEditingController(
                      text: tempTrailMult.toString(),
                    ),
                    onChanged: (v) =>
                        tempTrailMult = double.tryParse(v) ?? tempTrailMult,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'EMA Strategy',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  TextField(
                    decoration: const InputDecoration(labelText: 'Period'),
                    keyboardType: TextInputType.number,
                    controller: TextEditingController(
                      text: tempEmaPeriod.toString(),
                    ),
                    onChanged: (v) =>
                        tempEmaPeriod = int.tryParse(v) ?? tempEmaPeriod,
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () {
                    provider.updateGlobalAtrParams(
                      period: tempAtrPeriod,
                      multiplier: tempStopMult,
                      trailMultiplier: tempTrailMult,
                    );
                    provider.updateGlobalEmaParams(period: tempEmaPeriod);
                    Navigator.pop(context);
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
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
                onToggleMaximize: () =>
                    setState(() => _isMaximized = !_isMaximized),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchSection(
    BuildContext context,
    HomeProvider provider,
    StockSession session,
  ) {
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
            fieldViewBuilder:
                (context, textEditingController, focusNode, onFieldSubmitted) {
                  if (session.symbol != null &&
                      textEditingController.text.isEmpty) {
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

  Widget _buildEntryConfig(
    BuildContext context,
    HomeProvider provider,
    StockSession session,
  ) {
    return _EntryInputSection(
      entryDate: session.entryDate,
      entryPrice: session.entryPrice,
      onUpdate: (date, price) =>
          provider.updateEntryParams(entryDate: date, entryPrice: price),
      onClear: () => provider.clearEntryParams(),
    );
  }

  Widget _buildStrategyConfig(
    BuildContext context,
    HomeProvider provider,
    StockSession session,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Stop Strategy (Configured Globally)',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
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
    if (session.errorMessage != null)
      return Text(
        'Error: ${session.errorMessage}',
        style: const TextStyle(color: Colors.red),
      );
    if (session.stockQuote == null)
      return const Text('Enter a symbol to start.');

    final lastCandle = session.stockQuote!.candles.last;
    final lastClose = lastCandle.close;
    final cutLoss = session.cutLossPrice ?? 0.0;
    final trailing = session.trailingStopPrice;

    final date = DateTime.fromMillisecondsSinceEpoch(lastCandle.date * 1000);
    final dateStr = DateFormat('yyyy-MM-dd').format(date);
    final entryPrice = session.entryPrice;
    double percentage(double price) {
      var usePrice =
          entryPrice == null &&
              session.stockQuote != null &&
              session.stockQuote!.candles.isNotEmpty
          ? session.stockQuote!.candles.last.close
          : (entryPrice ?? 0.0);
      return (price - usePrice) / usePrice * 100;
    }

    final trailingProfit = trailing != null ? percentage(trailing) : 0.0;
    final cutLossProfit = percentage(cutLoss);

    return Card(
      color: Colors.blue.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              children: [
                Text(
                  'Date: $dateStr',
                  style: const TextStyle(fontStyle: FontStyle.italic),
                ),
                Text(
                  'Current Price: ${lastClose.toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 18),
                ),
              ],
            ),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Wrap(
                  children: [
                    const Text(
                      'Cut Loss',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                      ),
                    ),
                    Tooltip(
                      message: 'Cut Loss: ${cutLossProfit.toStringAsFixed(2)}%',
                      child: Text(
                        cutLoss.toStringAsFixed(2),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.red,
                        ),
                      ),
                    ),
                  ],
                ),
                if (trailing != null)
                  Wrap(
                    children: [
                      const Text(
                        'Trailing Profit',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.grey,
                        ),
                      ),
                      Tooltip(
                        message:
                            'Trailing Profit: ${trailingProfit.toStringAsFixed(2)}%',
                        child: Text(
                          trailing.toStringAsFixed(2),
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: trailingProfit > 0
                                ? Colors.green
                                : Colors.red,
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 8),
            // EMA Display
            Wrap(
              spacing: 12,
              children: [
                Text(
                  'EMA10: ${EmaStopStrategy.calculateValidSeries(session.stockQuote!.candles, 10).last?.toStringAsFixed(2) ?? '-'}',
                  style: const TextStyle(color: Colors.blue, fontSize: 12),
                ),
                Text(
                  'EMA20: ${EmaStopStrategy.calculateValidSeries(session.stockQuote!.candles, 20).last?.toStringAsFixed(2) ?? '-'}',
                  style: const TextStyle(color: Colors.orange, fontSize: 12),
                ),
                Text(
                  'EMA50: ${EmaStopStrategy.calculateValidSeries(session.stockQuote!.candles, 50).last?.toStringAsFixed(2) ?? '-'}',
                  style: const TextStyle(color: Colors.purple, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Trend Analysis Section
            if (session.trendAnalysis != null) ...[
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text(
                  '${session.trendAnalysis!.trend} • Score: ${session.trendAnalysis!.trendScore}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: _getTrendColor(session.trendAnalysis!.trend),
                  ),
                ),
                subtitle: Text(
                  session.trendAnalysis!.entryAdvice,
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        session.trendAnalysis!.notes.join('\n'),
                        style: const TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            Text(
              session.equation ?? '',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Color _getTrendColor(String trend) {
    if (trend.toLowerCase().contains('uptrend')) return Colors.green;
    if (trend.toLowerCase().contains('downtrend')) return Colors.red;
    return Colors.orange;
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
    _priceController = TextEditingController(
      text: widget.entryPrice?.toString() ?? '',
    );
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
                const Text(
                  'Optional Entry Details',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                if (widget.entryDate != null || widget.entryPrice != null)
                  TextButton(
                    onPressed: widget.onClear,
                    child: const Text('Clear'),
                  ),
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
                        lastDate: DateTime.now().add(
                          const Duration(days: 1),
                        ), // Allow today/tomorrow for timezone safety
                      );
                      if (picked != null) {
                        widget.onUpdate(picked, widget.entryPrice);
                      }
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Entry Date',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                      ),
                      child: Text(
                        widget.entryDate != null
                            ? DateFormat('yyyy-MM-dd').format(widget.entryDate!)
                            : 'Select Date',
                        style: TextStyle(
                          color: widget.entryDate != null
                              ? Colors.black
                              : Colors.grey,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _priceController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Entry Price',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
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
      tooltipSettings: InteractiveTooltip(enable: true),
      tooltipDisplayMode: TrackballDisplayMode.groupAllPoints,
      // builder: _buildTrackballTooltip,
    );
    // Attempt init
    if (widget.session.stockQuote != null) {
      _resetVisibleRange();
    }
  }

  int _volumeScaleFactor = 1;

  /*  Widget _buildTrackballTooltip(BuildContext context, TrackballDetails details) {
    // Get point information
    final pointInfo = details.point;
    if (pointInfo == null) return const SizedBox();
    
    // Get candles data
    final candles = widget.session.stockQuote?.candles;
    if (candles == null || candles.isEmpty) return const SizedBox();
    
    // Match candle by x-value (DateTime)
    final xValue = pointInfo.x;
    Candle? matchedCandle;
     
    if (xValue is DateTime) {
      // Convert to timestamp for comparison
      final targetTimestamp = xValue.millisecondsSinceEpoch ~/ 1000;
      
      // Find exact or closest candle by timestamp
      int closestIndex = 0;
      int minDiff = (candles[0].date - targetTimestamp).abs();
      
      for (int i = 0; i < candles.length; i++) {
        final diff = (candles[i].date - targetTimestamp).abs();
        if (diff < minDiff) {
          minDiff = diff;
          closestIndex = i;
        }
        // If exact match found, use it
        if (diff == 0) {
          closestIndex = i;
          break;
        }
      }
      
      matchedCandle = candles[closestIndex];
    }
    
    if (matchedCandle == null) return const SizedBox();
    
    final c = matchedCandle;

    // Format date
    final date = DateTime.fromMillisecondsSinceEpoch(c.date * 1000);
    final dateStr = "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";

    // OHLC values
    final open  = c.open.toStringAsFixed(2);
    final high  = c.high.toStringAsFixed(2);
    final low   = c.low.toStringAsFixed(2);
    final close = c.close.toStringAsFixed(2);

    // Apply scale factor
    final scale = _volumeScaleFactor;
    final volScaled = c.volume / scale;
    final volStr = scale == 1
        ? volScaled.toStringAsFixed(0)
        : scale == 1000
            ? "${volScaled.toStringAsFixed(1)}K"
            : "${volScaled.toStringAsFixed(1)}M";

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("📅 $dateStr", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          Text("O: $open   H: $high", style: const TextStyle(color: Colors.white)),
          Text("L: $low    C: $close", style: const TextStyle(color: Colors.white)),
          Text("Vol: $volStr", style: const TextStyle(color: Colors.white)),
        ],
      ),
    );
  } */

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
    final lastDate = DateTime.fromMillisecondsSinceEpoch(
      candles.last.date * 1000,
    );

    // Default to visibleDays from provider
    final days = provider.visibleDays;
    setState(() {
      _visibleMin = lastDate.subtract(Duration(days: days));
      _visibleMax = lastDate.add(
        Duration(hours: 12),
      ); // Small buffer to show the last candle clearly
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
    const seriesName = 'Price';

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
                  Provider.of<HomeProvider>(
                    context,
                    listen: false,
                  ).updateVisibleDays(days);
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
          axes: [
            NumericAxis(
              name: 'volumeAxis',
              opposedPosition: false,
              majorGridLines: const MajorGridLines(width: 0),
              maximum: null, // Auto-scale
            ),
          ],
          zoomPanBehavior: _zoomPanBehavior,
          trackballBehavior: _trackballBehavior,
          indicators: [
            EmaIndicator<domain.Candle, DateTime>(
              name: 'EMA 10',
              seriesName: seriesName,
              period: 10,
              valueField: 'close',
              signalLineColor: Colors.blue,
            ),
            EmaIndicator<domain.Candle, DateTime>(
              name: 'EMA 20',
              seriesName: seriesName,
              period: 20,
              valueField: 'close',
              signalLineColor: Colors.orange,
            ),
            EmaIndicator<domain.Candle, DateTime>(
              name: 'EMA 50',
              seriesName: seriesName,
              period: 50,
              valueField: 'close',
              signalLineColor: Colors.purple,
            ),
          ],
          series: <CartesianSeries<domain.Candle, DateTime>>[
            // Volume bars (behind candles) - scaled down for visibility
            ColumnSeries<domain.Candle, DateTime>(
              dataSource: candles,
              xValueMapper: (domain.Candle c, _) =>
                  DateTime.fromMillisecondsSinceEpoch(c.date * 1000),
              yValueMapper: (domain.Candle c, _) {
                // Smart scaling: calculate divisor based on max volume in dataset
                final maxVolume = candles
                    .map((c) => c.volume)
                    .reduce((a, b) => a > b ? a : b);
                final scaleFactor = maxVolume > 1000000
                    ? 1000000 // Millions -> show in M
                    : maxVolume > 1000
                    ? 1000 // Thousands -> show in K
                    : 1; // Small volumes, no scaling
                _volumeScaleFactor = scaleFactor;
                return c.volume / scaleFactor;
              },
              name: 'Volume',
              yAxisName: 'volumeAxis',
              color: Colors.blue.withValues(alpha: 0.3),
              borderColor: Colors.blue.withValues(alpha: 0.5),
              borderWidth: 1,
              width: 0.8, // 80% of available space
              spacing: 0.1, // 10% gap between bars
            ),
            // Candlesticks (on top)
            CandleSeries<domain.Candle, DateTime>(
              name: seriesName,
              dataSource: candles,
              xValueMapper: (domain.Candle c, _) =>
                  DateTime.fromMillisecondsSinceEpoch(c.date * 1000),
              lowValueMapper: (domain.Candle c, _) => c.low,
              highValueMapper: (domain.Candle c, _) => c.high,
              openValueMapper: (domain.Candle c, _) => c.open,
              closeValueMapper: (domain.Candle c, _) => c.close,
              spacing: 0.1, // 10% gap between candles
            ),
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
                  icon: Icon(
                    widget.isMaximized
                        ? Icons.close_fullscreen
                        : Icons.open_in_full,
                    color: Colors.white,
                  ),
                  onPressed: widget.onToggleMaximize,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
