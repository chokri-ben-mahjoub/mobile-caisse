import 'package:barcode_widget/barcode_widget.dart' as bw;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/demo_data.dart';
import '../../logic/settings_provider.dart';
import '../theme.dart';

/// Printable / on-screen EAN-13 barcodes of the demo products, so a prospect
/// can scan them with the app during a demonstration.
class DemoCodesScreen extends StatelessWidget {
  const DemoCodesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsProvider>().settings;
    final demo = DemoData.products();

    return Scaffold(
      appBar: AppBar(title: const Text('Codes-barres de démo')),
      body: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        itemCount: demo.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (_, i) {
          final p = demo[i];
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          p.name,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Text(
                        s.money(p.price),
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: context.pal.accent,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // White background in both themes so cameras can read it.
                  Container(
                    color: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      vertical: 8,
                      horizontal: 12,
                    ),
                    child: bw.BarcodeWidget(
                      barcode: bw.Barcode.ean13(),
                      data: p.barcode,
                      height: 72,
                      style: const TextStyle(fontSize: 12, color: Colors.black),
                      color: Colors.black,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
