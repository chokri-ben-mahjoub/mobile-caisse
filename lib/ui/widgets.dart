import 'package:flutter/material.dart';

/// Light-blue banner showing a big amount.
class TotalBanner extends StatelessWidget {
  const TotalBanner({super.key, required this.label, required this.amount, this.sub});
  final String label;
  final String amount;
  final String? sub;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1)),
              if (sub != null) Text(sub!, style: const TextStyle(fontSize: 12)),
            ],
          ),
          const Spacer(),
          FittedBox(
            child: Text(amount, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }
}

void showMsg(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}
