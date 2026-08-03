import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'glass_container.dart';

class ScannerBottomSheet extends StatelessWidget {
  final bool isMultiScan;
  final bool isQRMode;
  final Map<String, int> scannedBarcodes;
  final String latestBarcode;
  final bool hasBarcodesInFrame;

  final Widget Function(BuildContext context, String barcode)? bottomWidgetBuilder;
  final Widget Function(BuildContext context, String barcode)? multiScanItemBuilder;
  final Widget Function(BuildContext context, int totalItems, int totalQuantity)? multiScanSummaryBuilder;

  const ScannerBottomSheet({
    super.key,
    required this.isMultiScan,
    required this.isQRMode,
    required this.scannedBarcodes,
    required this.latestBarcode,
    required this.hasBarcodesInFrame,
    this.bottomWidgetBuilder,
    this.multiScanItemBuilder,
    this.multiScanSummaryBuilder,
  });

  @override
  Widget build(BuildContext context) {
    int totalItems = scannedBarcodes.length;
    int totalQuantity = scannedBarcodes.values.fold(0, (a, b) => a + b);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isMultiScan && scannedBarcodes.isNotEmpty)
            multiScanSummaryBuilder != null
                ? multiScanSummaryBuilder!(context, totalItems, totalQuantity)
                : Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      margin: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.qr_code, color: Colors.white, size: 16),
                          const SizedBox(width: 6),
                          Text(
                            '$totalItems mã',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          const SizedBox(width: 12),
                          Container(width: 1, height: 12, color: Colors.white54),
                          const SizedBox(width: 12),
                          const Icon(Icons.inventory_2_outlined, color: Colors.greenAccent, size: 16),
                          const SizedBox(width: 6),
                          Text(
                            '$totalQuantity SP',
                            style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ),

          if (isMultiScan && scannedBarcodes.isNotEmpty) const SizedBox(height: 8),

          if (isMultiScan && scannedBarcodes.isNotEmpty)
            Builder(
              builder: (context) {
                final recentEntries = scannedBarcodes.entries.toList();
                final int totalCards = recentEntries.length;
                final int maxCards = 3;
                final int cardsToShow = totalCards > maxCards ? maxCards : totalCards;
                final displayEntries = recentEntries.sublist(totalCards - cardsToShow);

                return SizedBox(
                  height: 100.0 + (maxCards - 1) * 12.0,
                  child: Stack(
                    alignment: Alignment.topCenter,
                    children: List.generate(cardsToShow, (i) {
                      final entry = displayEntries[i];
                      final int offsetFromTop = cardsToShow - 1 - i;

                      return AnimatedPositioned(
                        key: ValueKey(entry.key),
                        duration: const Duration(milliseconds: 500),
                        curve: Curves.easeOutQuart,
                        top: i * 12.0,
                        left: 20.0 + (offsetFromTop * 16.0),
                        right: 20.0 + (offsetFromTop * 16.0),
                        child: Container(
                          height: 95,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E1E1E), // Dark Mode Card
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.1), width: 1),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.6),
                                blurRadius: 15,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.05),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  isQRMode ? Icons.qr_code_2 : CupertinoIcons.barcode,
                                  color: Colors.white54,
                                  size: 28,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: multiScanItemBuilder != null
                                    ? SingleChildScrollView(
                                        child: multiScanItemBuilder!(context, entry.key),
                                      )
                                    : Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Text(
                                            entry.key,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w700,
                                              fontSize: 16,
                                              letterSpacing: 0.5,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            'Sản phẩm chưa có tên',
                                            style: TextStyle(
                                              color: Colors.white.withValues(alpha: 0.5),
                                              fontSize: 13,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                              ),
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: Colors.blueAccent.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      'x${entry.value}',
                                      style: const TextStyle(
                                        color: Colors.blueAccent,
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  ),
                );
              },
            ),

          if (!isMultiScan) ...[
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: GlassContainer(
                borderRadius: 24,
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      hasBarcodesInFrame ? Icons.check_circle : Icons.document_scanner,
                      color: hasBarcodesInFrame ? Colors.greenAccent : Colors.white54,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      hasBarcodesInFrame
                          ? (isQRMode ? 'Phát hiện QR Code' : 'Phát hiện mã vạch')
                          : (isQRMode ? 'Đưa QR Code vào khung hình' : 'Đưa mã vạch vào khung hình'),
                      style: TextStyle(
                        color: hasBarcodesInFrame ? Colors.white : Colors.white70,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ]
        ],
    );
  }
}
