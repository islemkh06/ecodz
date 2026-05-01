import 'dart:typed_data';
import 'package:exif/exif.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ---------------------------------------------------------------------------
// Model
// ---------------------------------------------------------------------------

class PhotoExifMetadata {
  final double? gpsLat;
  final double? gpsLon;
  final DateTime? takenAt;
  final String? deviceMake;
  final String? deviceModel;
  final int? imageWidth;
  final int? imageHeight;
  final Map<String, String> rawExif;

  const PhotoExifMetadata({
    this.gpsLat,
    this.gpsLon,
    this.takenAt,
    this.deviceMake,
    this.deviceModel,
    this.imageWidth,
    this.imageHeight,
    this.rawExif = const {},
  });

  bool get hasGps => gpsLat != null && gpsLon != null;
  bool get hasTimestamp => takenAt != null;
}

// ---------------------------------------------------------------------------
// Service
// ---------------------------------------------------------------------------

class PhotoMetadataService {
  PhotoMetadataService._();
  static final instance = PhotoMetadataService._();

  final _supabase = Supabase.instance.client;

  // ── EXIF extraction ───────────────────────────────────────────────────────

  /// Reads EXIF metadata from raw image bytes.
  /// Returns an empty [PhotoExifMetadata] if parsing fails or no EXIF present.
  Future<PhotoExifMetadata> extractMetadata(Uint8List bytes) async {
    try {
      final data = await readExifFromBytes(bytes);
      if (data.isEmpty) return const PhotoExifMetadata();

      final rawMap = data.map((k, v) => MapEntry(k, v.printable));

      return PhotoExifMetadata(
        gpsLat:      _parseGpsCoordinate(data['GPS GPSLatitude'],  data['GPS GPSLatitudeRef']),
        gpsLon:      _parseGpsCoordinate(data['GPS GPSLongitude'], data['GPS GPSLongitudeRef']),
        takenAt:     _parseExifDateTime(data['EXIF DateTimeOriginal'] ?? data['Image DateTime']),
        deviceMake:  data['Image Make']?.printable,
        deviceModel: data['Image Model']?.printable,
        imageWidth:  int.tryParse(data['EXIF ExifImageWidth']?.printable ?? ''),
        imageHeight: int.tryParse(data['EXIF ExifImageLength']?.printable ?? ''),
        rawExif:     rawMap,
      );
    } catch (_) {
      return const PhotoExifMetadata();
    }
  }

  // ── Persist metadata ──────────────────────────────────────────────────────

  /// Saves extracted metadata to the `preuve_metadata` table.
  /// This is non-blocking — a failure here does NOT break the upload flow.
  Future<void> saveMetadata({
    required int preuveId,
    required int actId,
    required String photoType, // 'avant' | 'apres'
    required PhotoExifMetadata meta,
  }) async {
    try {
      await _supabase.from('preuve_metadata').insert({
        'id_preuve':    preuveId,
        'id_act':       actId,
        'photo_type':   photoType,
        'gps_lat':      meta.gpsLat,
        'gps_lon':      meta.gpsLon,
        'taken_at':     meta.takenAt?.toUtc().toIso8601String(),
        'device_make':  meta.deviceMake,
        'device_model': meta.deviceModel,
        'image_width':  meta.imageWidth,
        'image_height': meta.imageHeight,
        'raw_exif':     meta.rawExif,
      });
      // The DB trigger `trg_fraud_score_on_metadata` runs automatically
      // and calls compute_fraud_score() to populate fraud_score + flags.
    } catch (_) {
      // Intentionally silent — metadata is supplementary, not critical
    }
  }

  /// Fetches the fraud score for a proof photo (0–100).
  /// Returns null if metadata has not been processed yet.
  Future<int?> getFraudScore(int preuveId) async {
    try {
      final row = await _supabase
          .from('preuve_metadata')
          .select('fraud_score, flags, verified_at')
          .eq('id_preuve', preuveId)
          .maybeSingle();

      return row?['fraud_score'] as int?;
    } catch (_) {
      return null;
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Parses DMS GPS coordinates from an EXIF tag.
  /// Tag value is typically formatted as: "[deg, min, sec]"
  double? _parseGpsCoordinate(IfdTag? coordTag, IfdTag? refTag) {
    if (coordTag == null) return null;

    try {
      // The exif package represents GPS as a list of rationals
      // coordTag.values is a IfdValues wrapping a list of Ratio
      final raw = coordTag.printable; // e.g. "[51, 28, 12.45]"
      final cleaned = raw.replaceAll('[', '').replaceAll(']', '').trim();
      final parts = cleaned.split(', ');

      if (parts.isEmpty) return null;

      double deg = _rationalToDouble(parts[0]);
      double min = parts.length > 1 ? _rationalToDouble(parts[1]) : 0.0;
      double sec = parts.length > 2 ? _rationalToDouble(parts[2]) : 0.0;

      double result = deg + (min / 60.0) + (sec / 3600.0);

      final ref = refTag?.printable ?? '';
      if (ref == 'S' || ref == 'W') result = -result;

      return result;
    } catch (_) {
      return null;
    }
  }

  double _rationalToDouble(String s) {
    s = s.trim();
    if (s.contains('/')) {
      final parts = s.split('/');
      if (parts.length == 2) {
        final num = double.tryParse(parts[0]) ?? 0.0;
        final den = double.tryParse(parts[1]) ?? 1.0;
        return den != 0 ? num / den : 0.0;
      }
    }
    return double.tryParse(s) ?? 0.0;
  }

  /// Parses EXIF datetime string "2024:06:15 14:23:00" → [DateTime].
  DateTime? _parseExifDateTime(IfdTag? tag) {
    if (tag == null) return null;
    try {
      final s = tag.printable.trim(); // "2024:06:15 14:23:00"
      if (s.length < 19) return null;

      final datePart = '${s.substring(0, 4)}-${s.substring(5, 7)}-${s.substring(8, 10)}';
      final timePart = s.substring(11, 19);
      return DateTime.tryParse('${datePart}T$timePart');
    } catch (_) {
      return null;
    }
  }
}
