import 'payment_models.dart';

/// Datas locais "YYYY-MM-DD" (sem fuso) usadas nos relatórios.
String dateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}'
    '-${d.day.toString().padLeft(2, '0')}';

/// Mês "YYYY-MM".
String monthKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';

class DayValues {
  final DateTime date;
  final int revenueCents;
  final int expensesCents;
  const DayValues(this.date, this.revenueCents, this.expensesCents);
}

/// GET /finance/reports/summary.
class ReportSummary {
  final int revenueCents;
  final int expensesCents;
  final int resultCents;
  final Map<PaymentMethod, int> byMethod;
  final List<DayValues> series;
  final int doneCount;
  final int soldCents;
  final int avgTicketCents;
  final int avgPerClientCents;
  final int openCents;

  const ReportSummary({
    required this.revenueCents,
    required this.expensesCents,
    required this.resultCents,
    this.byMethod = const {},
    this.series = const [],
    this.doneCount = 0,
    this.soldCents = 0,
    this.avgTicketCents = 0,
    this.avgPerClientCents = 0,
    this.openCents = 0,
  });

  factory ReportSummary.fromJson(Map<String, dynamic> j) => ReportSummary(
        revenueCents: (j['revenue_cents'] ?? 0) as int,
        expensesCents: (j['expenses_cents'] ?? 0) as int,
        resultCents: (j['result_cents'] ?? 0) as int,
        byMethod: {
          for (final e in ((j['by_method'] as Map?) ?? const {}).entries)
            PaymentMethod.fromApi(e.key as String) ?? PaymentMethod.other:
                e.value as int,
        },
        series: [
          for (final d in (j['series'] as List? ?? const []))
            DayValues(
              DateTime.parse((d as Map)['date'] as String),
              (d['revenue_cents'] ?? 0) as int,
              (d['expenses_cents'] ?? 0) as int,
            ),
        ],
        doneCount: (j['done_count'] ?? 0) as int,
        soldCents: (j['sold_cents'] ?? 0) as int,
        avgTicketCents: (j['avg_ticket_cents'] ?? 0) as int,
        avgPerClientCents: (j['avg_per_client_cents'] ?? 0) as int,
        openCents: (j['open_cents'] ?? 0) as int,
      );
}

/// Item de GET /finance/reports/services.
class ServiceRevenue {
  final String name;
  final bool isKit;
  final int count;
  final int totalCents;
  const ServiceRevenue(this.name, this.isKit, this.count, this.totalCents);

  factory ServiceRevenue.fromJson(Map<String, dynamic> j) => ServiceRevenue(
        (j['service_name'] ?? '') as String,
        (j['is_kit'] ?? false) as bool,
        (j['count'] ?? 0) as int,
        (j['total_cents'] ?? 0) as int,
      );
}

/// GET /finance/goals/:month.
class Goal {
  final String month;
  final int? targetCents;
  final int achievedCents;
  final int? percent;
  final int remainingCents;
  final int daysLeft;
  final int neededPerDayCents;

  const Goal({
    required this.month,
    this.targetCents,
    this.achievedCents = 0,
    this.percent,
    this.remainingCents = 0,
    this.daysLeft = 0,
    this.neededPerDayCents = 0,
  });

  bool get hasTarget => targetCents != null;

  factory Goal.fromJson(Map<String, dynamic> j) => Goal(
        month: j['month'] as String,
        targetCents: j['target_cents'] as int?,
        achievedCents: (j['achieved_cents'] ?? 0) as int,
        percent: j['percent'] as int?,
        remainingCents: (j['remaining_cents'] ?? 0) as int,
        daysLeft: (j['days_left'] ?? 0) as int,
        neededPerDayCents: (j['needed_per_day_cents'] ?? 0) as int,
      );
}
