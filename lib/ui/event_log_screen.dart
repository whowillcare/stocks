import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'home_provider.dart';
import 'home_screen.dart'; // For SessionView
import 'package:intl/intl.dart';
import '../domain/model/stock_event.dart';

class EventLogScreen extends StatelessWidget {
  const EventLogScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Event Log'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: () {
              Provider.of<HomeProvider>(context, listen: false).clearEvents();
            },
          ),
        ],
      ),
      body: Consumer<HomeProvider>(
        builder: (context, provider, child) {
          if (provider.eventLog.isEmpty) {
            return const Center(child: Text('No events logged.'));
          }

          // 1. Group events by symbol
          final eventsBySymbol = <String, List<StockEvent>>{};
          for (var event in provider.eventLog) {
            eventsBySymbol.putIfAbsent(event.symbol, () => []).add(event);
          }

          // 2. Identify 'Latest Date' for each symbol
          final todaySymbols = <String>[];
          final yesterdaySymbols = <String>[];
          final olderSymbols = <String>[];

          final now = DateTime.now();
          final today = DateTime(now.year, now.month, now.day);
          final yesterday = today.subtract(const Duration(days: 1));

          eventsBySymbol.forEach((symbol, events) {
            // Sort events: Newest first
            events.sort((a, b) => b.timestamp.compareTo(a.timestamp));

            if (events.isEmpty) return;

            final latest = events.first.timestamp;
            final latestDate = DateTime(latest.year, latest.month, latest.day);

            if (latestDate.isAtSameMomentAs(today)) {
              todaySymbols.add(symbol);
            } else if (latestDate.isAtSameMomentAs(yesterday)) {
              yesterdaySymbols.add(symbol);
            } else {
              olderSymbols.add(symbol);
            }
          });

          // Helper to sort symbols within buckets by their latest event time (desc)
          int compareSymbols(String a, String b) {
            final dateA = eventsBySymbol[a]!.first.timestamp;
            final dateB = eventsBySymbol[b]!.first.timestamp;
            return dateB.compareTo(dateA);
          }

          todaySymbols.sort(compareSymbols);
          yesterdaySymbols.sort(compareSymbols);
          olderSymbols.sort(compareSymbols);

          // 3. Build the UI List
          final sections = <Widget>[];

          Widget buildSectionHeader(String title) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            );
          }

          Widget buildSymbolTile(String symbol) {
            final events = eventsBySymbol[symbol]!;
            final latest = events.first;

            return ExpansionTile(
              leading: GestureDetector(
                onTap: () => _navigateToSession(context, symbol),
                child: CircleAvatar(
                  child: Text(symbol.substring(0, min(2, symbol.length))),
                ),
              ),
              title: GestureDetector(
                onTap: () => _navigateToSession(context, symbol),
                child: Text(
                  symbol,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              subtitle: Text(
                latest.message,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              children: events.map((event) {
                return ListTile(
                  dense: true,
                  title: Text(event.message),
                  subtitle: Text(
                    DateFormat('yyyy-MM-dd HH:mm').format(event.timestamp),
                  ),
                  leading: Icon(
                    event.type == 'stop_loss'
                        ? Icons.trending_up
                        : event.type == 'warning'
                        ? Icons.warning
                        : Icons.info,
                    size: 16,
                    color: event.type == 'stop_loss'
                        ? Colors.green
                        : event.type == 'warning'
                        ? Colors.orange
                        : Colors.grey,
                  ),
                );
              }).toList(),
            );
          }

          if (todaySymbols.isNotEmpty) {
            sections.add(buildSectionHeader('Today'));
            sections.addAll(todaySymbols.map(buildSymbolTile));
          }

          if (yesterdaySymbols.isNotEmpty) {
            sections.add(buildSectionHeader('Yesterday'));
            sections.addAll(yesterdaySymbols.map(buildSymbolTile));
          }

          if (olderSymbols.isNotEmpty) {
            sections.add(buildSectionHeader('Older'));
            sections.addAll(olderSymbols.map(buildSymbolTile));
          }

          return ListView(children: sections);
        },
      ),
    );
  }

  int min(int a, int b) => a < b ? a : b;

  void _navigateToSession(BuildContext context, String symbol) {
    final provider = Provider.of<HomeProvider>(context, listen: false);
    final sessionIndex = provider.sessions.indexWhere(
      (s) => s.symbol == symbol,
    );

    if (sessionIndex != -1) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => Scaffold(
            appBar: AppBar(title: Text('$symbol Session')),
            body: SessionView(session: provider.sessions[sessionIndex]),
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Active session for this symbol not found.'),
        ),
      );
    }
  }
}
