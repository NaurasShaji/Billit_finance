import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:image/image.dart' as img;
import 'package:qr/qr.dart';

import '../models/sale.dart';

/// Creates a standards-compatible UPI payment QR containing the actual sale
/// amount and invoice reference. Returns null when no UPI ID is configured.
class PaymentQrService {
  static Future<Uint8List?> generateForSale(Sale sale) async {
    final settings = Hive.box<dynamic>('app_settings');
    final upiId = settings.get('upi_id', defaultValue: '').toString().trim();
    if (upiId.isEmpty) return null;

    final payeeName =
        settings.get('upi_payee_name', defaultValue: '').toString().trim();
    final notePrefix = settings
        .get('upi_note_prefix', defaultValue: 'Invoice')
        .toString()
        .trim();
    final note =
        [notePrefix, sale.id].where((part) => part.isNotEmpty).join(' ');
    final paymentUri = Uri(
      scheme: 'upi',
      host: 'pay',
      queryParameters: <String, String>{
        'pa': upiId,
        if (payeeName.isNotEmpty) 'pn': payeeName,
        'am': sale.totalAmount.toStringAsFixed(2),
        'cu': 'INR',
        'tr': sale.id,
        if (note.isNotEmpty) 'tn': note,
      },
    ).toString();

    final code = QrCode.fromData(
      data: paymentUri,
      errorCorrectLevel: QrErrorCorrectLevel.M,
    );
    final matrix = QrImage(code);
    const scale = 8;
    const quietZone = 4;
    final side = (matrix.moduleCount + quietZone * 2) * scale;
    final canvas = img.Image(width: side, height: side);
    img.fill(canvas, color: img.ColorRgb8(255, 255, 255));

    for (var row = 0; row < matrix.moduleCount; row++) {
      for (var col = 0; col < matrix.moduleCount; col++) {
        if (matrix.isDark(row, col)) {
          final x = (col + quietZone) * scale;
          final y = (row + quietZone) * scale;
          img.fillRect(
            canvas,
            x1: x,
            y1: y,
            x2: x + scale - 1,
            y2: y + scale - 1,
            color: img.ColorRgb8(0, 0, 0),
          );
        }
      }
    }

    return Uint8List.fromList(img.encodePng(canvas));
  }

  /// Returns only a QR image explicitly uploaded in invoice settings.
  /// No bundled/default QR is shown when the user has not added one.
  static Future<Uint8List?> loadStaticQrFallback() async {
    final settings = Hive.box<dynamic>('app_settings');
    final saved = settings.get('payment_qr_base64')?.toString().trim() ?? '';
    if (saved.isEmpty) return null;
    try {
      return base64Decode(saved);
    } catch (_) {
      return null;
    }
  }
}
