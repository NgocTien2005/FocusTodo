import 'package:flutter/material.dart';

class EmptyState extends StatelessWidget {
  const EmptyState({super.key});

  @override
  Widget build(BuildContext context) => const Center(
    child: Padding(
      padding: EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.checklist_rounded, size: 64),
          SizedBox(height: 16),
          Text('A little focus goes a long way'),
          SizedBox(height: 8),
          Text(
            'Coming next: create TODOs and set reminders.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );
}
