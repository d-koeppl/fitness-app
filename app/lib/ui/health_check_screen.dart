import 'package:flutter/material.dart';

/// Phase 0's only screen: proves the app reaches the deployed API on
/// every platform. Replaced by the real shell in phase 4.
class HealthCheckScreen extends StatefulWidget {
  const HealthCheckScreen({super.key, required this.checkStatus, required this.apiBaseUrl});

  final Future<String> Function() checkStatus;
  final String apiBaseUrl;

  @override
  State<HealthCheckScreen> createState() => _HealthCheckScreenState();
}

class _HealthCheckScreenState extends State<HealthCheckScreen> {
  late Future<String> _status = widget.checkStatus();

  void _retry() {
    // Start the request outside setState: an arrow closure here would
    // return the assigned Future, which setState rejects.
    final next = widget.checkStatus();
    setState(() {
      _status = next;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Fitness')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FutureBuilder<String>(
            future: _status,
            builder: (context, snapshot) {
              final (IconData icon, String label, Color color) = switch (snapshot) {
                AsyncSnapshot(connectionState: ConnectionState.waiting) =>
                  (Icons.hourglass_empty, 'Checking…', theme.colorScheme.outline),
                AsyncSnapshot(hasError: true) =>
                  (Icons.cloud_off, 'API unreachable', theme.colorScheme.error),
                AsyncSnapshot(:final data) =>
                  (Icons.cloud_done, 'API status: $data', theme.colorScheme.primary),
              };
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 48, color: color),
                  const SizedBox(height: 12),
                  Text(label, style: theme.textTheme.titleLarge),
                  const SizedBox(height: 4),
                  Text(widget.apiBaseUrl, style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
                  if (snapshot.hasError) ...[
                    const SizedBox(height: 16),
                    FilledButton.tonal(onPressed: _retry, child: const Text('Retry')),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
