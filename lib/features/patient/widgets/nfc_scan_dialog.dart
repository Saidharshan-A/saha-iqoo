import 'package:flutter/material.dart';

class NfcScanDialog extends StatelessWidget {
  const NfcScanDialog({
    super.key,
    required this.title,
    required this.instruction,
    required this.onCancel,
  });

  final String title;
  final String instruction;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      canPop: false,
      child: AlertDialog(
        icon: Icon(Icons.nfc, size: 48, color: theme.colorScheme.primary),
        title: Text(title, textAlign: TextAlign.center),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const LinearProgressIndicator(),
            const SizedBox(height: 20),
            Text(instruction, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              'Keep the card still until the phone vibrates.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: onCancel, child: const Text('Cancel')),
        ],
      ),
    );
  }
}
