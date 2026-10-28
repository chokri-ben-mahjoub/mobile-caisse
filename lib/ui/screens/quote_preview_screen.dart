import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../data/quote.dart';
import '../../data/quote_share.dart';
import '../theme.dart';
import 'quote_share_sheet.dart';

/// In-app preview of the quote PDF, with share / save buttons underneath.
class QuotePreviewScreen extends StatelessWidget {
  const QuotePreviewScreen({super.key, required this.share});
  final QuoteShare share;

  Quote get quote => share.quote;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return Scaffold(
      appBar: AppBar(title: Text('Aperçu · ${quote.number}')),
      body: Column(
        children: [
          Expanded(
            child: PdfPreview(
              build: (_) async => Uint8List.fromList(await share.pdfBytes()),
              useActions: false,
              canChangeOrientation: false,
              canChangePageFormat: false,
              canDebug: false,
              allowPrinting: false,
              allowSharing: false,
              scrollViewDecoration: BoxDecoration(color: pal.bg),
              pdfPreviewPageDecoration: const BoxDecoration(
                color: Colors.white,
                boxShadow: [BoxShadow(color: Color(0x33000000), blurRadius: 14, offset: Offset(0, 4))],
              ),
              loadingWidget: const CircularProgressIndicator(),
              onError: (ctx, e) => Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Aperçu impossible : $e', textAlign: TextAlign.center),
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => runShare(context, share.saveOrPrint),
                      icon: const Icon(Icons.download_rounded),
                      label: const Text('Télécharger'),
                      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: () => showQuoteShareSheet(context, share),
                      icon: const Icon(Icons.send_rounded),
                      label: const Text('Envoyer'),
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
