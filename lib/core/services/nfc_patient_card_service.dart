import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:nfc_manager/nfc_manager.dart';

/// Compact, versioned profile stored on a SAHA NFC patient card.
///
/// Contains the identity fields used by the patient registration form.
/// Medical records are intentionally excluded.
class NfcPatientCardData {
  const NfcPatientCardData({
    required this.patientId,
    required this.fullName,
    required this.age,
    required this.gender,
    this.aadhaarLast4,
    this.phone,
    this.village,
    this.district,
    this.state,
  });

  factory NfcPatientCardData.decode(String source) {
    if (!source.startsWith('{')) {
      final values = source.split('\u001f');
      if (values.length != 10 || values.first != '$schemaVersion') {
        throw const NfcPatientCardException(
          'This is not a supported SAHA patient card.',
        );
      }
      final age = int.tryParse(values[3]);
      if (values[1].isEmpty ||
          values[2].isEmpty ||
          age == null ||
          values[4].isEmpty) {
        throw const NfcPatientCardException(
          'The SAHA card profile is incomplete.',
        );
      }
      String? optional(int index) =>
          values[index].isEmpty ? null : values[index];
      return NfcPatientCardData(
        patientId: values[1],
        fullName: values[2],
        age: age,
        gender: values[4],
        aadhaarLast4: optional(5),
        phone: optional(6),
        village: optional(7),
        district: optional(8),
        state: optional(9),
      );
    }

    final value = jsonDecode(source);
    if (value is! Map<String, dynamic> ||
        (value['v'] != 1 && value['v'] != schemaVersion)) {
      throw const NfcPatientCardException(
        'This is not a supported SAHA patient card.',
      );
    }

    final id = value['id'];
    final name = value['n'];
    final age = value['a'];
    final gender = value['g'];
    if (id is! String ||
        id.isEmpty ||
        name is! String ||
        name.isEmpty ||
        age is! int ||
        gender is! String ||
        gender.isEmpty) {
      throw const NfcPatientCardException(
        'The SAHA card profile is incomplete.',
      );
    }

    return NfcPatientCardData(
      patientId: id,
      fullName: name,
      age: age,
      gender: gender,
      aadhaarLast4: value['h'] as String?,
      phone: value['p'] as String?,
      village: value['l'] as String?,
      district: value['d'] as String?,
      state: value['s'] as String?,
    );
  }

  static const int schemaVersion = 2;

  final String patientId;
  final String fullName;
  final int age;
  final String gender;
  final String? aadhaarLast4;
  final String? phone;
  final String? village;
  final String? district;
  final String? state;

  Map<String, dynamic> toCompactMap() => {
        'v': schemaVersion,
        'id': patientId,
        'n': fullName,
        'a': age,
        'g': gender,
        if (aadhaarLast4?.isNotEmpty == true) 'h': aadhaarLast4,
        if (phone?.isNotEmpty == true) 'p': phone,
        if (village?.isNotEmpty == true) 'l': village,
        if (district?.isNotEmpty == true) 'd': district,
        if (state?.isNotEmpty == true) 's': state,
      };

  String encode() {
    String clean(String? value) => (value ?? '').replaceAll('\u001f', ' ');
    return [
      '$schemaVersion',
      clean(patientId),
      clean(fullName),
      '$age',
      clean(gender),
      clean(aadhaarLast4),
      clean(phone),
      clean(village),
      clean(district),
      clean(state),
    ].join('\u001f');
  }
}

class NfcPatientCardException implements Exception {
  const NfcPatientCardException(this.message, {this.cancelled = false});

  final String message;
  final bool cancelled;

  @override
  String toString() => message;
}

/// Reads and writes SAHA patient profiles using NDEF NFC tags.
class NfcPatientCardService {
  NfcPatientCardService._();

  static final NfcPatientCardService instance = NfcPatientCardService._();
  static const String mimeType = 'application/saha';
  static const String _legacyMimeType = 'application/vnd.saha.patient+json';

  Completer<dynamic>? _activeCompleter;

  Future<bool> isAvailable() => NfcManager.instance.isAvailable();

  Future<NfcPatientCardData> readCard() async {
    await _prepareSession<NfcPatientCardData>();
    final completer = _activeCompleter! as Completer<NfcPatientCardData>;

    await NfcManager.instance.startSession(
      onDiscovered: (tag) async {
        try {
          final ndef = Ndef.from(tag);
          if (ndef == null) {
            throw const NfcPatientCardException(
              'This card does not support NDEF. Try another NFC card.',
            );
          }

          final message = ndef.cachedMessage ?? await ndef.read();
          final record = message.records.cast<NdefRecord?>().firstWhere(
                (item) =>
                    item != null &&
                    {mimeType, _legacyMimeType}.contains(
                      utf8.decode(item.type, allowMalformed: true),
                    ),
                orElse: () => null,
              );
          if (record == null) {
            throw const NfcPatientCardException(
              'No SAHA patient profile was found on this card.',
            );
          }

          final profile =
              NfcPatientCardData.decode(utf8.decode(record.payload));
          await _finishSession();
          if (!completer.isCompleted) completer.complete(profile);
        } catch (error) {
          await _failSession(completer, error);
        }
      },
      onError: (error) async {
        await _failSession(completer, NfcPatientCardException(error.message));
      },
    );

    return completer.future;
  }

  Future<void> writeCard(NfcPatientCardData profile) async {
    await _prepareSession<void>();
    final completer = _activeCompleter! as Completer<void>;
    final message = NdefMessage([
      NdefRecord.createMime(
        mimeType,
        Uint8List.fromList(utf8.encode(profile.encode())),
      ),
    ]);

    await NfcManager.instance.startSession(
      onDiscovered: (tag) async {
        try {
          final ndef = Ndef.from(tag);
          if (ndef == null) {
            throw const NfcPatientCardException(
              'This card does not support NDEF. Try another NFC card.',
            );
          }
          if (!ndef.isWritable) {
            throw const NfcPatientCardException(
              'This NFC card is read-only.',
            );
          }
          if (message.byteLength > ndef.maxSize) {
            throw NfcPatientCardException(
              'This card needs ${message.byteLength} bytes but only '
              '${ndef.maxSize} bytes are available.',
            );
          }

          await ndef.write(message);
          await _finishSession();
          if (!completer.isCompleted) completer.complete();
        } catch (error) {
          await _failSession(completer, error);
        }
      },
      onError: (error) async {
        await _failSession(completer, NfcPatientCardException(error.message));
      },
    );

    return completer.future;
  }

  Future<void> cancel() async {
    final completer = _activeCompleter;
    await _finishSession();
    if (completer != null && !completer.isCompleted) {
      completer.completeError(
        const NfcPatientCardException('NFC scan cancelled.', cancelled: true),
      );
    }
  }

  Future<void> _prepareSession<T>() async {
    if (_activeCompleter != null) {
      throw const NfcPatientCardException(
          'An NFC operation is already active.');
    }
    if (!await isAvailable()) {
      throw const NfcPatientCardException(
        'NFC is unavailable. Turn on NFC in phone settings and try again.',
      );
    }
    _activeCompleter = Completer<T>();
  }

  Future<void> _finishSession() async {
    try {
      await NfcManager.instance.stopSession();
    } catch (_) {
      // The session may already be closed by Android.
    }
    _activeCompleter = null;
  }

  Future<void> _failSession(
    Completer<dynamic> completer,
    Object error,
  ) async {
    await _finishSession();
    if (!completer.isCompleted) {
      completer.completeError(
        error is NfcPatientCardException
            ? error
            : NfcPatientCardException('NFC operation failed: $error'),
      );
    }
  }
}
