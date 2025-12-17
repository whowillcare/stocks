import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'home_provider.dart';
import 'home_screen.dart'; // For SessionView
import 'package:intl/intl.dart';

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

          // Group by symbol
          final grouped = <String, List<dynamic>>{};
          for (var event in provider.eventLog) {
            grouped.putIfAbsent(event.symbol, () => []).add(event);
          }

          final symbols = grouped.keys.toList();

          return ListView.builder(
            itemCount: symbols.length,
            itemBuilder: (context, index) {
              final symbol = symbols[index];
              final events = grouped[symbol]!;
              // Sort events: newest first for display
              events.sort((a, b) => b.timestamp.compareTo(a.timestamp));

              final latest = events.first;

              return ExpansionTile(
                leading: GestureDetector(
                  onTap: () {
                    // Find session or fallback
                    final provider = Provider.of<HomeProvider>(
                      context,
                      listen: false,
                    );
                    final sessionIndex = provider.sessions.indexWhere(
                      (s) => s.symbol == symbol,
                    );

                    if (sessionIndex != -1) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => Scaffold(
                            appBar: AppBar(title: Text('$symbol Session')),
                            body: SessionView(
                              session: provider.sessions[sessionIndex],
                            ),
                          ),
                        ),
                      );
                    } else {
                      // Optional: Allow viewing archived/deleted session if we stored it?
                      // For now just show snackbar
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Active session for this symbol not found.',
                          ),
                        ),
                      );
                    }
                  },
                  child: CircleAvatar(
                    child: Text(symbol.substring(0, min(2, symbol.length))),
                  ),
                ),
                title: GestureDetector(
                  onTap: () {
                    // Duplicate logic for title tap
                    final provider = Provider.of<HomeProvider>(
                      context,
                      listen: false,
                    );
                    final sessionIndex = provider.sessions.indexWhere(
                      (s) => s.symbol == symbol,
                    );
                    if (sessionIndex != -1) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => Scaffold(
                            appBar: AppBar(title: Text('$symbol Session')),
                            body: SessionView(
                              session: provider.sessions[sessionIndex],
                            ),
                          ),
                        ),
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Active session for this symbol not found.',
                          ),
                        ),
                      );
                    }
                  },
                  child: Text(
                    symbol,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                subtitle: Text(
                  latest.message, // Changed from original to match instruction
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
                          : Icons.info,
                      size: 16,
                      color: event.type == 'stop_loss'
                          ? Colors.green
                          : Colors.grey,
                    ),
                  );
                }).toList(),
              );
            },
          );
        },
      ),
    );
  }

  int min(int a, int b) => a < b ? a : b;
}
