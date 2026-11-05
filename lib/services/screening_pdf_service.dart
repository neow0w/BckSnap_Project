
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../core/format.dart';
import '../features/screening/posture_analysis.dart';
import '../features/screening/screening_result.dart';
import '../models/app_user.dart';
import '../models/screening.dart';
import 'auth_service.dart';
import 'screening_service.dart';

class ScreeningPdfService {
    static Future<void> download(Screening screening) async {
        final document = pw.Document();

        // Retrieve the logged-in account information.
        final AppUser? account = AuthService().currentUser;

        // Retrieve the original back photo from Firestore.
        final Uint8List? photoBytes =
            screening.hasPhoto
                ? await ScreeningService().photoOf(screening.id)
                : null;

        final pw.MemoryImage? screeningPhoto = photoBytes != null
            ? pw.MemoryImage(photoBytes)
            : null;

        // Retrieve saved screening details.
        final details = screening.details ?? {};
        final rawLevels = details['levels'];
        final rawPosture = details['posture'];

        final levels = rawLevels is List
            ? rawLevels.whereType<Map>().map((item) {
                return Map<String, dynamic>.from(item);
            }).toList()
            : <Map<String, dynamic>>[];

        final posture = rawPosture is Map
            ? Map<String, dynamic>.from(rawPosture)
            : null;

        final category = _category(screening, posture);

        // Personal information for the screened person.
        final subject = screening.subject ?? {};

        final personDetails = screening.forSelf
            ? <String, String>{
                'Full name': account?.name ?? 'Not available',
                'Email address': account?.email ?? 'Not available',
                'Phone number': account?.phone ?? 'Not available',
                'Age': account?.age?.toString() ?? 'Not available',
                'Date of birth': account?.dateOfBirth == null
                    ? 'Not available'
                    : formatDate(account!.dateOfBirth!),
                'Address': account?.address ?? 'Not available',
            }
            : <String, String>{
                'First name':
                    subject['firstName']?.toString() ?? 'Not available',
                'Middle name':
                    subject['middleName']?.toString() ?? 'Not provided',
                'Last name':
                    subject['lastName']?.toString() ?? 'Not available',
                'Age': subject['age']?.toString() ?? 'Not available',
                'Sex': subject['sex']?.toString() ?? 'Not available',
                'Relationship':
                    subject['relationship']?.toString() ?? 'Not available',
            };

        document.addPage(
            pw.MultiPage(
                pageFormat: PdfPageFormat.a4,
                margin: const pw.EdgeInsets.all(36),
                build: (context) => [
                    // REPORT HEADER
                    pw.Text(
                        'BckSnap',
                        style: pw.TextStyle(
                            fontSize: 25,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.blue900,
                        ),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                        'SCOLIOSIS SCREENING REPORT',
                        style: pw.TextStyle(
                            fontSize: 13,
                            fontWeight: pw.FontWeight.bold,
                            letterSpacing: 1.2,
                        ),
                    ),
                    pw.Divider(
                        color: PdfColors.blue900,
                        thickness: 2,
                    ),
                    pw.SizedBox(height: 12),

                    // SCREENED PERSON INFORMATION
                    _sectionTitle('SCREENED PERSON INFORMATION'),

                    for (final entry in personDetails.entries)
                        _detailRow(entry.key, entry.value),

                    pw.SizedBox(height: 18),

                    // SCREENING INFORMATION
                    _sectionTitle('SCREENING INFORMATION'),

                    _detailRow(
                        'Screening date',
                        formatDate(screening.createdAt),
                    ),
                    _detailRow(
                        'Screening ID',
                        screening.id,
                    ),
                    _detailRow(
                        'Screening type',
                        screening.forSelf
                            ? 'Self-screening'
                            : 'Screening for another person',
                    ),

                    pw.SizedBox(height: 20),

                    // SCREENING RESULT
                    _sectionTitle('SCREENING RESULT'),

                    pw.Container(
                        width: double.infinity,
                        padding: const pw.EdgeInsets.all(14),
                        decoration: pw.BoxDecoration(
                            color: _categoryColor(category),
                            borderRadius: pw.BorderRadius.circular(8),
                        ),
                        child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                                pw.Text(
                                    _categoryLabel(category),
                                    style: pw.TextStyle(
                                        fontSize: 17,
                                        fontWeight: pw.FontWeight.bold,
                                        color: PdfColors.white,
                                    ),
                                ),
                                pw.SizedBox(height: 6),
                                pw.Text(
                                    'Highest ATR: '
                                    '${screening.angle.toStringAsFixed(1)}°',
                                    style: const pw.TextStyle(
                                        fontSize: 14,
                                        color: PdfColors.white,
                                    ),
                                ),
                            ],
                        ),
                    ),

                    pw.SizedBox(height: 10),

                    _detailRow(
                        'ATR interpretation',
                        _atrLabel(screening.angle),
                    ),

                    pw.SizedBox(height: 20),

                    // SPINAL LEVEL MEASUREMENTS
                    _sectionTitle('SPINAL LEVEL MEASUREMENTS'),

                    if (levels.isEmpty)
                        pw.Text(
                            'Individual spinal level measurements '
                            'are not available.',
                            style: const pw.TextStyle(fontSize: 10),
                        )
                    else
                        pw.TableHelper.fromTextArray(
                            headers: [
                                'Spinal Level',
                                'ATR Reading',
                            ],
                            data: [
                                for (final level in levels)
                                    [
                                        level['name']?.toString() ?? 'Unknown',
                                        '${_number(level['atr']).toStringAsFixed(1)}°',
                                    ],
                            ],
                            headerStyle: pw.TextStyle(
                                fontWeight: pw.FontWeight.bold,
                                color: PdfColors.white,
                            ),
                            headerDecoration: const pw.BoxDecoration(
                                color: PdfColors.blue900,
                            ),
                            cellPadding: const pw.EdgeInsets.all(8),
                            border: pw.TableBorder.all(
                                color: PdfColors.grey300,
                            ),
                        ),

                    pw.SizedBox(height: 20),

                    // ACTUAL BACK PHOTO
                    _sectionTitle('BACK PHOTO ANALYSIS'),

                    if (screeningPhoto != null) ...[
                        pw.Center(
                            child: pw.Container(
                                width: 250,
                                height: 300,
                                decoration: pw.BoxDecoration(
                                    border: pw.Border.all(
                                        color: PdfColors.grey400,
                                    ),
                                ),
                                padding: const pw.EdgeInsets.all(5),
                                child: pw.Image(
                                    screeningPhoto,
                                    fit: pw.BoxFit.contain,
                                ),
                            ),
                        ),
                        pw.SizedBox(height: 8),
                        pw.Center(
                            child: pw.Text(
                                'Original back photo used during screening',
                                style: const pw.TextStyle(
                                    fontSize: 9,
                                    color: PdfColors.grey600,
                                ),
                            ),
                        ),
                    ] else ...[
                        pw.Container(
                            width: double.infinity,
                            padding: const pw.EdgeInsets.all(14),
                            decoration: pw.BoxDecoration(
                                color: PdfColors.grey200,
                                borderRadius: pw.BorderRadius.circular(6),
                            ),
                            child: pw.Text(
                                'The original screening photo '
                                'is unavailable.',
                                style: const pw.TextStyle(fontSize: 10),
                            ),
                        ),
                    ],

                    // POSTURE MEASUREMENTS
                    if (posture != null) ...[
                        pw.SizedBox(height: 20),

                        _sectionTitle('POSTURE MEASUREMENTS'),

                        _detailRow(
                            'Shoulder tilt',
                            '${_number(posture['shoulder_tilt']).toStringAsFixed(1)}°',
                        ),
                        _detailRow(
                            'Shoulder status',
                            _number(posture['shoulder_tilt']) >=
                                    PostureRules.shoulderTiltFlag
                                ? 'Flagged'
                                : 'Not flagged',
                        ),
                        _detailRow(
                            'Higher shoulder',
                            _label(posture['higher_shoulder']),
                        ),

                        pw.Divider(color: PdfColors.grey300),

                        _detailRow(
                            'Hip tilt',
                            '${_number(posture['hip_tilt']).toStringAsFixed(1)}°',
                        ),
                        _detailRow(
                            'Hip status',
                            _number(posture['hip_tilt']) >=
                                    PostureRules.hipTiltFlag
                                ? 'Flagged'
                                : 'Not flagged',
                        ),
                        _detailRow(
                            'Higher hip',
                            _label(posture['higher_hip']),
                        ),

                        pw.Divider(color: PdfColors.grey300),

                        _detailRow(
                            'Trunk lean',
                            '${_number(posture['trunk_lean']).toStringAsFixed(1)}°',
                        ),
                        _detailRow(
                            'Lean direction',
                            _label(posture['lean_side']),
                        ),
                    ] else ...[
                        pw.SizedBox(height: 10),
                        pw.Text(
                            'Posture measurements are unavailable '
                            'for this screening.',
                            style: const pw.TextStyle(
                                fontSize: 10,
                                color: PdfColors.grey700,
                            ),
                        ),
                    ],

                    pw.SizedBox(height: 24),

                    // MEDICAL DISCLAIMER
                    _sectionTitle('IMPORTANT MEDICAL DISCLAIMER'),

                    pw.Text(
                        'This report contains preliminary screening results '
                        'generated by BckSnap. It is not a medical diagnosis '
                        'and does not confirm the presence or absence of '
                        'scoliosis. ATR readings and photo-based posture '
                        'measurements are screening information only. '
                        'Consult a qualified healthcare professional for '
                        'clinical assessment and further evaluation.',
                        style: const pw.TextStyle(
                            fontSize: 9,
                            color: PdfColors.grey800,
                        ),
                    ),

                    pw.SizedBox(height: 18),

                    pw.Divider(color: PdfColors.grey400),

                    pw.Center(
                        child: pw.Text(
                            'Generated by BckSnap',
                            style: const pw.TextStyle(
                                fontSize: 9,
                                color: PdfColors.grey600,
                            ),
                        ),
                    ),
                ],
            ),
        );

        final fileName = 'BckSnap_Screening_${screening.id}.pdf';

        await Printing.sharePdf(
            bytes: await document.save(),
            filename: fileName,
        );
    }

    // DETERMINE SCREENING CATEGORY
    static ResultCategory _category(
        Screening screening,
        Map<String, dynamic>? posture,
    ) {
        if (screening.angle >= ResultRules.referAtr) {
            return ResultCategory.refer;
        }

        if (screening.angle >= ResultRules.borderlineAtr) {
            return ResultCategory.borderline;
        }

        if (posture != null) {
            final shoulder = _number(posture['shoulder_tilt']);
            final hip = _number(posture['hip_tilt']);

            if (shoulder >= PostureRules.shoulderTiltFlag ||
                hip >= PostureRules.hipTiltFlag) {
                return ResultCategory.borderline;
            }
        }

        return ResultCategory.noSign;
    }

    // CATEGORY LABEL
    static String _categoryLabel(ResultCategory category) {
        switch (category) {
            case ResultCategory.refer:
                return 'REFERRAL RANGE';
            case ResultCategory.borderline:
                return 'BORDERLINE';
            case ResultCategory.noSign:
                return 'NO SIGN';
        }
    }

    // CATEGORY COLOR
    static PdfColor _categoryColor(ResultCategory category) {
        switch (category) {
            case ResultCategory.refer:
                return PdfColors.red700;
            case ResultCategory.borderline:
                return PdfColors.orange700;
            case ResultCategory.noSign:
                return PdfColors.green700;
        }
    }

    // ATR INTERPRETATION
    static String _atrLabel(double angle) {
        if (angle >= ResultRules.referAtr) {
            return 'Referral range';
        }

        if (angle >= ResultRules.borderlineAtr) {
            return 'Borderline';
        }

        return 'Low';
    }

    // SECTION HEADING
    static pw.Widget _sectionTitle(String title) {
        return pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 8),
            child: pw.Text(
                title,
                style: pw.TextStyle(
                    fontSize: 11,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.blue900,
                ),
            ),
        );
    }

    // INFORMATION ROW
    static pw.Widget _detailRow(String label, String value) {
        return pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 3),
            child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                    pw.SizedBox(
                        width: 145,
                        child: pw.Text(
                            label,
                            style: pw.TextStyle(
                                fontSize: 10,
                                fontWeight: pw.FontWeight.bold,
                            ),
                        ),
                    ),
                    pw.Expanded(
                        child: pw.Text(
                            value,
                            style: const pw.TextStyle(fontSize: 10),
                        ),
                    ),
                ],
            ),
        );
    }

    // SAFE NUMBER CONVERSION
    static double _number(dynamic value) {
        if (value is num) return value.toDouble();

        return double.tryParse(value?.toString() ?? '') ?? 0;
    }

    // FORMAT LABEL
    static String _label(dynamic value) {
        final text = value?.toString() ?? 'Not available';

        if (text.isEmpty) return 'Not available';

        return '${text[0].toUpperCase()}${text.substring(1)}';
    }
}
