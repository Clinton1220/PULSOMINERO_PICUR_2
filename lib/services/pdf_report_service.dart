import 'dart:typed_data';
import 'package:flutter/material.dart' show DateTimeRange;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/vibration_record.dart';

class PdfReportService {
  static const PdfColor brandGreen = PdfColor.fromInt(0xFF153D22);
  static const PdfColor brandLime = PdfColor.fromInt(0xFF84CC16);
  static const PdfColor bgLight = PdfColor.fromInt(0xFFF4F6F4);

  /// Genera y abre el menú nativo para imprimir, guardar o compartir por WhatsApp el PDF.
  static Future<void> printOrSharePdf(
    Uint8List bytes, {
    required String filename,
  }) async {
    await Printing.sharePdf(bytes: bytes, filename: filename);
  }

  /// Genera el reporte técnico oficial en PDF de un ensayo individual.
  static Future<Uint8List> generateSingleRecordPdf(
      VibrationRecord record) async {
    final pdf = pw.Document();

    final maxInc = record.samples.isEmpty
        ? 0.0
        : record.samples
            .map((s) => s.inclination.abs())
            .reduce((a, b) => a > b ? a : b);
    final maxGas = record.samples.isEmpty
        ? 0.0
        : record.samples.map((s) => s.gasPpm).reduce((a, b) => a > b ? a : b);
    final features = record.analysis.features;

    final risk = record.analysis.riskLevel.toUpperCase();
    PdfColor riskColor = PdfColors.green;
    if (risk == 'MEDIO') riskColor = PdfColors.amber;
    if (risk == 'ALTO') riskColor = PdfColors.red;

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // 1. ENCABEZADO INSTITUCIONAL
              pw.Container(
                padding: const pw.EdgeInsets.all(14),
                decoration: pw.BoxDecoration(
                  color: brandGreen,
                  borderRadius: pw.BorderRadius.circular(8),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'PULSO MINERO · TELEMETRÍA IOT & IA',
                          style: const pw.TextStyle(
                            color: brandLime,
                            fontSize: 16,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.SizedBox(height: 3),
                        pw.Text(
                          'Informe Técnico de Monitoreo Vibracional y Atmosférico (SST)',
                          style: const pw.TextStyle(
                            color: PdfColors.white,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: pw.BoxDecoration(
                        color: riskColor,
                        borderRadius: pw.BorderRadius.circular(6),
                      ),
                      child: pw.Text(
                        'RIESGO: $risk',
                        style: const pw.TextStyle(
                          color: PdfColors.white,
                          fontSize: 11,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 16),

              // 2. DATOS GENERALES DEL ENSAYO
              pw.Container(
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  color: bgLight,
                  borderRadius: pw.BorderRadius.circular(6),
                  border: pw.Border.all(color: PdfColors.grey300),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    _infoItem('ID de Ensayo', record.id),
                    _infoItem('Fecha y Hora',
                        record.startedAt.toLocal().toString().substring(0, 19)),
                    _infoItem('Muestras', '${record.samples.length} pts (4 Hz)'),
                    _infoItem('Nube Firebase',
                        record.isSyncedToCloud ? 'Sincronizado' : 'Pendiente'),
                  ],
                ),
              ),
              pw.SizedBox(height: 16),

              // 3. CUADRO DE MÉTRICAS CLAVE
              pw.Text(
                '1. RESUMEN DE TELEMETRÍA SENSORIAL',
                style: const pw.TextStyle(
                  fontSize: 11,
                  fontWeight: pw.FontWeight.bold,
                  color: brandGreen,
                ),
              ),
              pw.SizedBox(height: 8),
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey300),
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                    children: [
                      _tableHeader('Parámetro'),
                      _tableHeader('Valor Obtenido'),
                      _tableHeader('Umbral Seguro'),
                      _tableHeader('Estado Operativo'),
                    ],
                  ),
                  pw.TableRow(
                    children: [
                      _tableCell('Vibración Resultante (MPU6050)'),
                      _tableCell(
                          '${record.analysis.maximumAmplitude.toStringAsFixed(2)} m/s²',
                          isBold: true),
                      _tableCell('< 1.00 m/s²'),
                      _tableCell(
                          record.analysis.maximumAmplitude >= 2.0
                              ? 'Crítico'
                              : (record.analysis.maximumAmplitude >= 1.0
                                  ? 'Precaución'
                                  : 'Normal'),
                          color: riskColor),
                    ],
                  ),
                  pw.TableRow(
                    children: [
                      _tableCell('Gas Atmosférico (MQ-135)'),
                      _tableCell('${maxGas.toStringAsFixed(0)} PPM',
                          isBold: true),
                      _tableCell('< 600 PPM'),
                      _tableCell(
                          maxGas > 1000
                              ? 'Peligro'
                              : (maxGas > 600 ? 'Advertencia' : 'Seguro'),
                          color: maxGas > 600 ? PdfColors.red : PdfColors.green),
                    ],
                  ),
                  pw.TableRow(
                    children: [
                      _tableCell('Inclinación Estructural (Tilt)'),
                      _tableCell('${maxInc.toStringAsFixed(1)}°', isBold: true),
                      _tableCell('< 15.0°'),
                      _tableCell(maxInc > 15 ? 'Alerta Talud' : 'Estable',
                          color:
                              maxInc > 15 ? PdfColors.red : PdfColors.green),
                    ],
                  ),
                  if (features != null)
                    pw.TableRow(
                      children: [
                        _tableCell('Frecuencia Dominante (FFT)'),
                        _tableCell(
                            '${features.dominantFrequency.toStringAsFixed(1)} Hz',
                            isBold: true),
                        _tableCell('15.0 - 45.0 Hz (Maquinaria)'),
                        _tableCell('Identificada'),
                      ],
                    ),
                ],
              ),
              pw.SizedBox(height: 18),

              // 4. SECCIÓN MOTOR DE IA EXPLICABLE (XAI)
              pw.Text(
                '2. DICTAMEN DE INTELIGENCIA ARTIFICIAL EXPLICABLE (XAI)',
                style: const pw.TextStyle(
                  fontSize: 11,
                  fontWeight: pw.FontWeight.bold,
                  color: brandGreen,
                ),
              ),
              pw.SizedBox(height: 8),
              pw.Container(
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  color: bgLight,
                  borderRadius: pw.BorderRadius.circular(6),
                  border: pw.Border.all(color: brandGreen, width: 1.2),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text(
                          'Diagnóstico: ${record.analysis.title}',
                          style: const pw.TextStyle(
                            fontSize: 13,
                            fontWeight: pw.FontWeight.bold,
                            color: brandGreen,
                          ),
                        ),
                        pw.Text(
                          'Certeza: ${(record.analysis.confidence * 100).toStringAsFixed(0)}%',
                          style: const pw.TextStyle(
                            fontSize: 11,
                            fontWeight: pw.FontWeight.bold,
                            color: brandGreen,
                          ),
                        ),
                      ],
                    ),
                    pw.Divider(color: PdfColors.grey300, height: 16),
                    pw.Text(
                      'Justificación Técnica del Algoritmo:',
                      style: const pw.TextStyle(
                        fontSize: 10,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.SizedBox(height: 6),
                    ...record.analysis.reasons.map(
                      (reason) => pw.Padding(
                        padding: const pw.EdgeInsets.only(bottom: 3),
                        child: pw.Row(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text('- ',
                                style: const pw.TextStyle(
                                    fontWeight: pw.FontWeight.bold)),
                            pw.Expanded(
                              child: pw.Text(reason,
                                  style: const pw.TextStyle(fontSize: 9.5)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              pw.Spacer(),

              // 5. ESPACIO PARA FIRMAS DE RESPONSABILIDAD SST
              pw.Container(
                padding: const pw.EdgeInsets.only(top: 10),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                  children: [
                    _signatureBox('Ingeniero de Seguridad (SST)', 'C.C. / Matrícula Profesional'),
                    _signatureBox('Supervisor de Turno Minero', 'Firma y Sello'),
                  ],
                ),
              ),
              pw.SizedBox(height: 10),

              // 6. PIE DE PÁGINA
              pw.Divider(color: PdfColors.grey300),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'Generado automáticamente por Pulso Minero IoT App',
                    style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
                  ),
                  pw.Text(
                    'Documento de Telemetría Oficial · Minería Segura',
                    style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  /// Genera un reporte consolidado en PDF con la lista de ensayos filtrados.
  static Future<Uint8List> generateConsolidatedPdf(
    List<VibrationRecord> records, {
    DateTimeRange? dateRange,
  }) async {
    final pdf = pw.Document();

    final dateRangeStr = dateRange == null
        ? 'Historial Completo'
        : '${dateRange.start.toLocal().toString().substring(0, 10)} hasta ${dateRange.end.toLocal().toString().substring(0, 10)}';

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return [
            // Encabezado
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                color: brandGreen,
                borderRadius: pw.BorderRadius.circular(8),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'PULSO MINERO · CONSOLIDADO DE TELEMETRÍA',
                        style: const pw.TextStyle(
                          color: brandLime,
                          fontSize: 14,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.Text(
                        'Rango Auditado: $dateRangeStr',
                        style: const pw.TextStyle(
                            color: PdfColors.white, fontSize: 9),
                      ),
                    ],
                  ),
                  pw.Text(
                    '${records.length} Ensayos',
                    style: const pw.TextStyle(
                      color: PdfColors.white,
                      fontSize: 12,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 14),

            // Tabla con todos los ensayos
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300),
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                  children: [
                    _tableHeader('Fecha'),
                    _tableHeader('Clasificación'),
                    _tableHeader('Vib. Máx'),
                    _tableHeader('Gas Máx'),
                    _tableHeader('Riesgo'),
                    _tableHeader('Nube'),
                  ],
                ),
                ...records.map((r) {
                  final maxGas = r.samples.isEmpty
                      ? 0.0
                      : r.samples.map((s) => s.gasPpm).reduce((a, b) => a > b ? a : b);
                  final risk = r.analysis.riskLevel.toUpperCase();
                  PdfColor rColor = PdfColors.green;
                  if (risk == 'MEDIO') rColor = PdfColors.amber;
                  if (risk == 'ALTO') rColor = PdfColors.red;

                  return pw.TableRow(
                    children: [
                      _tableCell(r.startedAt.toLocal().toString().substring(0, 16)),
                      _tableCell(r.analysis.title),
                      _tableCell('${r.analysis.maximumAmplitude.toStringAsFixed(2)} m/s²'),
                      _tableCell('${maxGas.toStringAsFixed(0)} PPM'),
                      _tableCell(risk, color: rColor, isBold: true),
                      _tableCell(r.isSyncedToCloud ? 'Nube (OK)' : 'Local'),
                    ],
                  );
                }),
              ],
            ),
            pw.SizedBox(height: 30),

            // Firmas
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
              children: [
                _signatureBox('Responsable SST', 'Firma y Cédula'),
                _signatureBox('Jefe de Mina / Operaciones', 'Firma y Aprobación'),
              ],
            ),
          ];
        },
      ),
    );

    return pdf.save();
  }

  static pw.Widget _infoItem(String label, String value) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(label,
            style: const pw.TextStyle(color: PdfColors.grey600, fontSize: 8)),
        pw.SizedBox(height: 2),
        pw.Text(value,
            style: const pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold)),
      ],
    );
  }

  static pw.Widget _tableHeader(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Text(
        text,
        style: const pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold),
      ),
    );
  }

  static pw.Widget _tableCell(
    String text, {
    bool isBold = false,
    PdfColor? color,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 8.5,
          fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: color ?? PdfColors.black,
        ),
      ),
    );
  }

  static pw.Widget _signatureBox(String role, String caption) {
    return pw.Column(
      children: [
        pw.Container(
          width: 170,
          decoration: const pw.BoxDecoration(
            border: pw.Border(top: pw.BorderSide(color: PdfColors.black, width: 1)),
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Text(role,
            style: const pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
        pw.Text(caption,
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
      ],
    );
  }
}
