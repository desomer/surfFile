import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:super_container_layout/ai/vibe_chat_attachment.dart';

void main() {
  test('encodeDibToPng, dibToBmpBytes and trimEncodedImageBytes convert clipboard bitmaps cleanly', () {
    // 1. DIB 32 bits BI_RGB 2x2 bottom-up avec alpha=0 partout (cas GDI PrintScreen).
    final gdiDib = Uint8List(40 + 16);
    final gdiHeader = ByteData.sublistView(gdiDib);
    gdiHeader.setUint32(0, 40, Endian.little); // biSize
    gdiHeader.setInt32(4, 2, Endian.little); // width = 2
    gdiHeader.setInt32(8, 2, Endian.little); // height = 2 (bottom-up)
    gdiHeader.setUint16(12, 1, Endian.little); // planes = 1
    gdiHeader.setUint16(14, 32, Endian.little); // 32 bpp
    gdiHeader.setUint32(16, 0, Endian.little); // BI_RGB
    // Ligne 0 mémoire = ligne du bas : bleu (0,0,255) puis vert (0,255,0), alpha=0
    gdiDib.setAll(40, [255, 0, 0, 0, 0, 255, 0, 0]);
    // Ligne 1 mémoire = ligne du haut : rouge (255,0,0) puis blanc (255,255,255), alpha=0
    gdiDib.setAll(48, [0, 0, 255, 0, 255, 255, 255, 0]);

    final bmp = VibeChatAttachment.dibToBmpBytes(gdiDib);
    expect(bmp, isNotNull);
    expect(bmp![0], 0x42);
    expect(bmp[1], 0x4D);
    expect(ByteData.sublistView(bmp).getUint32(10, Endian.little), 14 + 40);

    final png = VibeChatAttachment.encodeDibToPng(gdiDib);
    expect(png, isNotNull);
    expect(png!.sublist(0, 8), [
      0x89,
      0x50,
      0x4E,
      0x47,
      0x0D,
      0x0A,
      0x1A,
      0x0A,
    ]);

    // Décompression de l'IDAT pour vérifier les pixels RGBA exacts (Sub-unfilter).
    final idatLen = ByteData.sublistView(png).getUint32(33, Endian.big);
    final filtered = zlib.decode(png.sublist(41, 41 + idatLen));
    expect(filtered.length, 2 * (1 + 2 * 4));
    Uint8List decodeSubRow(List<int> row) {
      expect(row[0], 1);
      final out = Uint8List(row.length - 1);
      for (var i = 0; i < out.length; i++) {
        final left = i >= 4 ? out[i - 4] : 0;
        out[i] = (row[i + 1] + left) & 0xFF;
      }
      return out;
    }

    final topRow = decodeSubRow(filtered.sublist(0, 9));
    final bottomRow = decodeSubRow(filtered.sublist(9, 18));
    // Haut-gauche = rouge opaque, haut-droite = blanc opaque
    expect(topRow, [255, 0, 0, 255, 255, 255, 255, 255]);
    // Bas-gauche = bleu opaque, bas-droite = vert opaque
    expect(bottomRow, [0, 0, 255, 255, 0, 255, 0, 255]);

    // 2. DIBV5 32 bits BI_BITFIELDS 2x1 avec canal alpha mixte (0 et 128 préservés).
    final dibV5 = Uint8List(124 + 8);
    final v5 = ByteData.sublistView(dibV5);
    v5.setUint32(0, 124, Endian.little);
    v5.setInt32(4, 2, Endian.little);
    v5.setInt32(8, -1, Endian.little); // top-down
    v5.setUint16(12, 1, Endian.little);
    v5.setUint16(14, 32, Endian.little);
    v5.setUint32(16, 3, Endian.little); // BI_BITFIELDS
    v5.setUint32(40, 0x00FF0000, Endian.little); // R
    v5.setUint32(44, 0x0000FF00, Endian.little); // G
    v5.setUint32(48, 0x000000FF, Endian.little); // B
    v5.setUint32(52, 0xFF000000, Endian.little); // A
    v5.setUint32(124, 0x00102030, Endian.little); // alpha = 0
    v5.setUint32(128, 0x80405060, Endian.little); // alpha = 128

    final pngAlpha = VibeChatAttachment.encodeDibToPng(dibV5)!;
    final idatAlphaLen = ByteData.sublistView(pngAlpha)
        .getUint32(33, Endian.big);
    final filteredAlpha = zlib.decode(pngAlpha.sublist(41, 41 + idatAlphaLen));
    final alphaRow = decodeSubRow(filteredAlpha);
    expect(alphaRow, [0x10, 0x20, 0x30, 0x00, 0x40, 0x50, 0x60, 0x80]);

    // 3. DIB 24 bits BI_RGB 3x1 avec alignement de ligne sur 4 octets (stride = 12 pour 9 octets utiles).
    final dib24 = Uint8List(40 + 12);
    ByteData.sublistView(dib24)
      ..setUint32(0, 40, Endian.little)
      ..setInt32(4, 3, Endian.little)
      ..setInt32(8, 1, Endian.little)
      ..setUint16(12, 1, Endian.little)
      ..setUint16(14, 24, Endian.little);
    // Pixels BGR : (10,20,30), (40,50,60), (70,80,90) + 3 octets de padding (0xAA)
    dib24.setAll(40, [30, 20, 10, 60, 50, 40, 90, 80, 70, 0xAA, 0xAA, 0xAA]);
    final png24 = VibeChatAttachment.encodeDibToPng(dib24)!;
    final idat24Len = ByteData.sublistView(png24).getUint32(33, Endian.big);
    final row24 = decodeSubRow(zlib.decode(png24.sublist(41, 41 + idat24Len)));
    expect(row24, [10, 20, 30, 255, 40, 50, 60, 255, 70, 80, 90, 255]);

    // 4. Troncature des zéros de bourrage GlobalSize après IEND / EOI / RIFF.
    final paddedPng = Uint8List.fromList([...png, 0, 0, 0, 0, 0]);
    expect(VibeChatAttachment.trimEncodedImageBytes(paddedPng), png);

    final jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0xFF, 0xD9]);
    final paddedJpeg = Uint8List.fromList([...jpeg, 0, 0, 0]);
    expect(VibeChatAttachment.trimEncodedImageBytes(paddedJpeg), jpeg);

    // 5. withName conserve toutes les métadonnées et octets.
    final att = VibeChatAttachment.image(
      name: 'presse-papiers.png',
      bytes: png,
    );
    final renamed = att.withName('presse-papiers-2.png');
    expect(renamed.name, 'presse-papiers-2.png');
    expect(renamed.mimeType, 'image/png');
    expect(renamed.bytes, png);
    expect(renamed.isImage, isTrue);
  });
}
