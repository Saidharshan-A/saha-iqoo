import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/db/sync_engine.dart';

/// A compact widget showing the number of pending sync items
/// with a manual "sync now" trigger.
class SyncIndicator extends StatefulWidget {
  const SyncIndicator({super.key});

  @override
  State<SyncIndicator> createState() => _SyncIndicatorState();
}

class _SyncIndicatorState extends State<SyncIndicator> {
  int _pending = 0;
  StreamSubscription<int>? _sub;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _pending = SyncEngine.instance.pendingCount;
    _sub = SyncEngine.instance.pendingCountStream.listen((count) {
      if (mounted) setState(() => _pending = count);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _triggerSync() async {
    setState(() => _syncing = true);
    await SyncEngine.instance.syncNow();
    if (mounted) setState(() => _syncing = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasItems = _pending > 0;

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              hasItems ? Icons.cloud_upload_outlined : Icons.cloud_done,
              size: 20,
              color: hasItems ? Colors.orange.shade700 : Colors.green.shade600,
            ),
            const SizedBox(width: 8),
            Text(
              hasItems ? '$_pending pending' : 'All synced',
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                color:
                    hasItems ? Colors.orange.shade700 : Colors.green.shade600,
              ),
            ),
            if (hasItems) ...[
              const SizedBox(width: 8),
              SizedBox(
                width: 28,
                height: 28,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  iconSize: 18,
                  onPressed: _syncing ? null : _triggerSync,
                  icon: _syncing
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.sync),
                  tooltip: 'Sync now',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
