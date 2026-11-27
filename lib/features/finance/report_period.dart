import 'package:intl/intl.dart';

/// Tamanho do período dos relatórios.
enum ReportGranularity {
  day('Dia'),
  week('Semana'),
  month('Mês'),
  custom('Período');

  const ReportGranularity(this.label);
  final String label;
}

/// Período em datas locais (sem hora), inclusivo. Semana = segunda a domingo.
class ReportPeriod {
  final ReportGranularity granularity;
  final DateTime from;
  final DateTime to;

  const ReportPeriod._(this.granularity, this.from, this.to);

  static DateTime _d(DateTime x) => DateTime(x.year, x.month, x.day);

  /// Período que contém [anchor].
  factory ReportPeriod.of(ReportGranularity g, DateTime anchor) {
    final a = _d(anchor);
    return switch (g) {
      ReportGranularity.day => ReportPeriod._(g, a, a),
      ReportGranularity.week => ReportPeriod._(
          g,
          a.subtract(Duration(days: a.weekday - 1)),
          a.add(Duration(days: 7 - a.weekday)),
        ),
      // "Período" começa no mês; o usuário escolhe as datas depois
      ReportGranularity.month || ReportGranularity.custom => ReportPeriod._(
          g, DateTime(a.year, a.month), DateTime(a.year, a.month + 1, 0)),
    };
  }

  /// Período livre (datas escolhidas).
  factory ReportPeriod.custom(DateTime from, DateTime to) =>
      ReportPeriod._(ReportGranularity.custom, _d(from), _d(to));

  /// Anda [step] períodos (‹ = -1, › = +1). Período livre não anda.
  ReportPeriod shift(int step) => switch (granularity) {
        ReportGranularity.day => ReportPeriod.of(
            granularity, DateTime(from.year, from.month, from.day + step)),
        ReportGranularity.week => ReportPeriod.of(
            granularity, DateTime(from.year, from.month, from.day + 7 * step)),
        ReportGranularity.month =>
          ReportPeriod.of(granularity, DateTime(from.year, from.month + step)),
        ReportGranularity.custom => this,
      };

  static final _day = DateFormat("EEEE, d 'de' MMMM", 'pt_BR');
  static final _short = DateFormat('dd/MM', 'pt_BR');
  static final _month = DateFormat('MMMM yyyy', 'pt_BR');

  String get label {
    final text = switch (granularity) {
      ReportGranularity.day => _day.format(from),
      ReportGranularity.month => _month.format(from),
      _ => '${_short.format(from)} a ${_short.format(to)}',
    };
    return '${text[0].toUpperCase()}${text.substring(1)}';
  }
}
