import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:koffiloop/core/theme/app_theme.dart';
import 'package:koffiloop/services/auth_service.dart';

// ---------------------------------------------------------------------------
// PLACEMENT: koffiloop/lib/features/seller_portal/screens/seller_analytics_screen.dart
// This is a NEW file. Create it at the path above.
// ---------------------------------------------------------------------------

class SellerAnalyticsScreen extends StatefulWidget {
  const SellerAnalyticsScreen({super.key});

  @override
  State<SellerAnalyticsScreen> createState() =>
      _SellerAnalyticsScreenState();
}

class _SellerAnalyticsScreenState extends State<SellerAnalyticsScreen> {
  bool _loading = true;
  String _error = '';

  // ── Overview metrics ──────────────────────────────────────────────
  int _totalOrders = 0;
  double _totalRevenue = 0;
  double _avgOrderValue = 0;
  int _uniqueCustomers = 0;
  int _totalOrdersPrev = 0;
  double _totalRevenuePrev = 0;

  // ── Status breakdown ──────────────────────────────────────────────
  int _pendingCount = 0;
  int _preparingCount = 0;
  int _readyCount = 0;
  int _completedCount = 0;
  int _cancelledCount = 0;

  // ── Revenue per day (last 14 days) ────────────────────────────────
  final List<_DayRevenue> _dailyRevenue = [];

  // ── Top items ─────────────────────────────────────────────────────
  final List<_ItemStat> _topItems = [];

  // ── Busiest hours ─────────────────────────────────────────────────
  final List<int> _hourCounts = List.filled(24, 0);

  @override
  void initState() {
    super.initState();
    // Defer so context.read is safe
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadAnalytics());
  }

  Future<void> _loadAnalytics() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final uid = context.read<AuthService>().uid;
      final now = DateTime.now();
      final thirtyDaysAgo = now.subtract(const Duration(days: 30));
      final sixtyDaysAgo = now.subtract(const Duration(days: 60));

      // ── Fetch last 30 days of orders ─────────────────────────────
      final snap30 = await FirebaseFirestore.instance
          .collection('orders')
          .where('sellerId', isEqualTo: uid)
          .where('createdAt', isGreaterThanOrEqualTo: thirtyDaysAgo)
          .get();

      // ── Fetch previous 30 days for delta comparison ───────────────
      final snapPrev = await FirebaseFirestore.instance
          .collection('orders')
          .where('sellerId', isEqualTo: uid)
          .where('createdAt', isGreaterThanOrEqualTo: sixtyDaysAgo)
          .where('createdAt', isLessThan: thirtyDaysAgo)
          .get();

      final docs = snap30.docs;
      final prevDocs = snapPrev.docs;

      // ── Overview ─────────────────────────────────────────────────
      _totalOrders = docs.length;
      _totalOrdersPrev = prevDocs.length;

      final customerIds = <String>{};
      double revenue = 0;
      final statusMap = <String, int>{};
      final itemMap = <String, _ItemStat>{};
      final dayMap = <String, double>{};
      final hourMap = List.filled(24, 0);

      // Build day keys for last 14 days so chart always has 14 slots
      final last14 = List.generate(14, (i) {
        final d = now.subtract(Duration(days: 13 - i));
        return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      });
      for (final k in last14) {
        dayMap[k] = 0;
      }

      for (final doc in docs) {
        final d = doc.data();
        final status = (d['status'] as String?) ?? '';
        final total = ((d['total'] ?? 0) as num).toDouble();
        final customerId = (d['customerId'] as String?) ?? '';

        // Revenue only from completed
        if (status == 'completed') revenue += total;

        // Customer uniqueness
        if (customerId.isNotEmpty) customerIds.add(customerId);

        // Status counts
        statusMap[status] = (statusMap[status] ?? 0) + 1;

        // Daily revenue (last 14 days only)
        final ts = d['createdAt'];
        DateTime? dt;
        if (ts is Timestamp) dt = ts.toDate();
        if (dt != null && status == 'completed') {
          final key =
              '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
          if (dayMap.containsKey(key)) {
            dayMap[key] = (dayMap[key] ?? 0) + total;
          }
          // Busiest hours
          hourMap[dt.hour]++;
        }

        // Top items — items stored as Map<String, dynamic>
        final items = d['items'];
        if (items is Map) {
          items.forEach((_, val) {
            if (val is Map) {
              final name = (val['name'] as String?) ?? 'Unknown';
              final qty = ((val['qty'] ?? 1) as num).toInt();
              if (itemMap.containsKey(name)) {
                itemMap[name] = _ItemStat(
                    name: name,
                    count: itemMap[name]!.count + qty);
              } else {
                itemMap[name] = _ItemStat(name: name, count: qty);
              }
            }
          });
        }
      }

      // Previous revenue for delta
      double prevRevenue = 0;
      for (final doc in prevDocs) {
        final d = doc.data();
        if ((d['status'] as String?) == 'completed') {
          prevRevenue += ((d['total'] ?? 0) as num).toDouble();
        }
      }

      // Sort items
      final sortedItems = itemMap.values.toList()
        ..sort((a, b) => b.count.compareTo(a.count));

      // Build daily list
      final dailyList = last14
          .map((k) => _DayRevenue(
              label: k.substring(5), // MM-DD
              revenue: dayMap[k] ?? 0))
          .toList();

      setState(() {
        _totalRevenue = revenue;
        _totalRevenuePrev = prevRevenue;
        _avgOrderValue =
            _totalOrders > 0 ? revenue / _totalOrders : 0;
        _uniqueCustomers = customerIds.length;
        _pendingCount = statusMap['pending'] ?? 0;
        _preparingCount = statusMap['preparing'] ?? 0;
        _readyCount = statusMap['ready'] ?? 0;
        _completedCount = statusMap['completed'] ?? 0;
        _cancelledCount = statusMap['cancelled'] ?? 0;
        _dailyRevenue
          ..clear()
          ..addAll(dailyList);
        _topItems
          ..clear()
          ..addAll(sortedItems.take(5));
        for (int i = 0; i < 24; i++) {
          _hourCounts[i] = hourMap[i];
        }
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: isDark ? AppTheme.darkSurface : AppTheme.primary,
        foregroundColor: Colors.white,
        title: const Text(
          'Analytics',
          style: TextStyle(
            color: Colors.white,
            fontFamily: 'Georgia',
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            onPressed: _loadAnalytics,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.primary))
          : _error.isNotEmpty
              ? _ErrorView(error: _error, onRetry: _loadAnalytics)
              : RefreshIndicator(
                  color: AppTheme.primary,
                  onRefresh: _loadAnalytics,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
                    children: [
                      _SectionLabel(
                          label: 'Last 30 days', isDark: isDark),
                      const SizedBox(height: 10),
                      _OverviewGrid(
                        totalOrders: _totalOrders,
                        totalOrdersPrev: _totalOrdersPrev,
                        totalRevenue: _totalRevenue,
                        totalRevenuePrev: _totalRevenuePrev,
                        avgOrderValue: _avgOrderValue,
                        uniqueCustomers: _uniqueCustomers,
                        isDark: isDark,
                      ),
                      const SizedBox(height: 20),
                      _SectionLabel(
                          label: 'Order status breakdown',
                          isDark: isDark),
                      const SizedBox(height: 10),
                      _StatusRow(
                        pending: _pendingCount,
                        preparing: _preparingCount,
                        ready: _readyCount,
                        completed: _completedCount,
                        cancelled: _cancelledCount,
                        isDark: isDark,
                      ),
                      const SizedBox(height: 20),
                      _SectionLabel(
                          label: 'Revenue over time (last 14 days)',
                          isDark: isDark),
                      const SizedBox(height: 10),
                      _RevenueChart(
                          data: _dailyRevenue, isDark: isDark),
                      const SizedBox(height: 20),
                      _SectionLabel(
                          label: 'Top selling items', isDark: isDark),
                      const SizedBox(height: 10),
                      _TopItemsCard(
                          items: _topItems, isDark: isDark),
                      const SizedBox(height: 20),
                      _SectionLabel(
                          label: 'Busiest hours', isDark: isDark),
                      const SizedBox(height: 10),
                      _HourChart(
                          counts: _hourCounts, isDark: isDark),
                      const SizedBox(height: 20),
                      _SectionLabel(
                          label: 'Completion rate', isDark: isDark),
                      const SizedBox(height: 10),
                      _CompletionRate(
                        completed: _completedCount,
                        cancelled: _cancelledCount,
                        active:
                            _pendingCount + _preparingCount + _readyCount,
                        isDark: isDark,
                      ),
                    ],
                  ),
                ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Data models
// ─────────────────────────────────────────────────────────────────────────────

class _DayRevenue {
  final String label; // "MM-DD"
  final double revenue;
  const _DayRevenue({required this.label, required this.revenue});
}

class _ItemStat {
  final String name;
  final int count;
  const _ItemStat({required this.name, required this.count});
}

// ─────────────────────────────────────────────────────────────────────────────
// Section label
// ─────────────────────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String label;
  final bool isDark;
  const _SectionLabel({required this.label, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        fontFamily: 'Georgia',
        color:
            isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Overview metric grid (2×2)
// ─────────────────────────────────────────────────────────────────────────────

class _OverviewGrid extends StatelessWidget {
  final int totalOrders;
  final int totalOrdersPrev;
  final double totalRevenue;
  final double totalRevenuePrev;
  final double avgOrderValue;
  final int uniqueCustomers;
  final bool isDark;

  const _OverviewGrid({
    required this.totalOrders,
    required this.totalOrdersPrev,
    required this.totalRevenue,
    required this.totalRevenuePrev,
    required this.avgOrderValue,
    required this.uniqueCustomers,
    required this.isDark,
  });

  String _pct(num current, num prev) {
    if (prev == 0) return current > 0 ? '+100%' : '0%';
    final delta = ((current - prev) / prev * 100).roundToDouble();
    return delta >= 0
        ? '+${delta.toStringAsFixed(0)}%'
        : '${delta.toStringAsFixed(0)}%';
  }

  bool _isUp(num current, num prev) => current >= prev;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.35,
      children: [
        _MetricCard(
          icon: Icons.receipt_long_rounded,
          iconColor: AppTheme.primary,
          value: '$totalOrders',
          label: 'Total orders',
          delta: _pct(totalOrders, totalOrdersPrev),
          isUp: _isUp(totalOrders, totalOrdersPrev),
          isDark: isDark,
        ),
        _MetricCard(
          icon: Icons.attach_money_rounded,
          iconColor: AppTheme.success,
          value: '\$${totalRevenue.toStringAsFixed(2)}',
          label: 'Revenue',
          delta: _pct(totalRevenue, totalRevenuePrev),
          isUp: _isUp(totalRevenue, totalRevenuePrev),
          isDark: isDark,
        ),
        _MetricCard(
          icon: Icons.shopping_cart_outlined,
          iconColor: AppTheme.info,
          value: '\$${avgOrderValue.toStringAsFixed(2)}',
          label: 'Avg. order value',
          delta: null,
          isUp: true,
          isDark: isDark,
        ),
        _MetricCard(
          icon: Icons.people_alt_outlined,
          iconColor: AppTheme.secondary,
          value: '$uniqueCustomers',
          label: 'Unique customers',
          delta: null,
          isUp: true,
          isDark: isDark,
        ),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String value;
  final String label;
  final String? delta;
  final bool isUp;
  final bool isDark;

  const _MetricCard({
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.label,
    required this.delta,
    required this.isUp,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppTheme.cardShadow(isDark),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              fontFamily: 'Georgia',
              color: isDark
                  ? AppTheme.darkTextPrimary
                  : AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: isDark
                  ? AppTheme.darkTextSecondary
                  : AppTheme.textSecondary,
            ),
          ),
          if (delta != null) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  isUp
                      ? Icons.trending_up_rounded
                      : Icons.trending_down_rounded,
                  size: 12,
                  color: isUp ? AppTheme.success : AppTheme.error,
                ),
                const SizedBox(width: 2),
                Text(
                  '$delta vs prev 30d',
                  style: TextStyle(
                    fontSize: 10,
                    color: isUp ? AppTheme.success : AppTheme.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Status row
// ─────────────────────────────────────────────────────────────────────────────

class _StatusRow extends StatelessWidget {
  final int pending, preparing, ready, completed, cancelled;
  final bool isDark;

  const _StatusRow({
    required this.pending,
    required this.preparing,
    required this.ready,
    required this.completed,
    required this.cancelled,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final items = [
      _StatusChip(
          label: 'Pending',
          count: pending,
          color: AppTheme.warning,
          isDark: isDark),
      _StatusChip(
          label: 'Preparing',
          count: preparing,
          color: AppTheme.info,
          isDark: isDark),
      _StatusChip(
          label: 'Ready',
          count: ready,
          color: AppTheme.success,
          isDark: isDark),
      _StatusChip(
          label: 'Done',
          count: completed,
          color: Colors.grey,
          isDark: isDark),
      _StatusChip(
          label: 'Cancelled',
          count: cancelled,
          color: AppTheme.error,
          isDark: isDark),
    ];
    return Row(
      children: items
          .map((c) => Expanded(child: c))
          .expand((w) => [w, const SizedBox(width: 8)])
          .toList()
        ..removeLast(),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  final bool isDark;

  const _StatusChip({
    required this.label,
    required this.count,
    required this.color,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: AppTheme.cardShadow(isDark),
      ),
      child: Column(
        children: [
          Text(
            '$count',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: color,
              fontFamily: 'Georgia',
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: isDark
                  ? AppTheme.darkTextSecondary
                  : AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Revenue chart (pure Flutter — no external chart lib needed)
// ─────────────────────────────────────────────────────────────────────────────

class _RevenueChart extends StatelessWidget {
  final List<_DayRevenue> data;
  final bool isDark;

  const _RevenueChart({required this.data, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final maxRev =
        data.fold(0.0, (m, d) => d.revenue > m ? d.revenue : m);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppTheme.cardShadow(isDark),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (maxRev == 0)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  'No completed orders in the last 14 days',
                  style: TextStyle(
                    color: isDark
                        ? AppTheme.darkTextSecondary
                        : AppTheme.textSecondary,
                  ),
                ),
              ),
            )
          else ...[
            SizedBox(
              height: 140,
              child: CustomPaint(
                size: const Size(double.infinity, 140),
                painter: _LineChartPainter(
                  data: data,
                  maxValue: maxRev,
                  lineColor: AppTheme.primary,
                  fillColor: AppTheme.primary.withValues(alpha: 0.08),
                  isDark: isDark,
                ),
              ),
            ),
            const SizedBox(height: 8),
            // X-axis labels — show every 2nd
            Row(
              children: List.generate(data.length, (i) {
                final show = i == 0 ||
                    i == data.length - 1 ||
                    i % 3 == 0;
                return Expanded(
                  child: Text(
                    show ? data[i].label : '',
                    style: TextStyle(
                      fontSize: 9,
                      color: isDark
                          ? AppTheme.darkTextSecondary
                          : AppTheme.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                );
              }),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            'Max \$${maxRev.toStringAsFixed(2)} / day',
            style: TextStyle(
              fontSize: 11,
              color: isDark
                  ? AppTheme.darkTextSecondary
                  : AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _LineChartPainter extends CustomPainter {
  final List<_DayRevenue> data;
  final double maxValue;
  final Color lineColor;
  final Color fillColor;
  final bool isDark;

  const _LineChartPainter({
    required this.data,
    required this.maxValue,
    required this.lineColor,
    required this.fillColor,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty || maxValue == 0) return;

    final n = data.length;
    final w = size.width;
    final h = size.height;
    final step = w / (n - 1).clamp(1, n);

    Offset point(int i) {
      final x = i * step;
      final y = h - (data[i].revenue / maxValue * h * 0.9);
      return Offset(x, y);
    }

    // Fill path
    final fillPath = Path()..moveTo(0, h);
    for (int i = 0; i < n; i++) {
      final p = point(i);
      if (i == 0) {
        fillPath.lineTo(p.dx, p.dy);
      } else {
        final prev = point(i - 1);
        final cx = (prev.dx + p.dx) / 2;
        fillPath.cubicTo(cx, prev.dy, cx, p.dy, p.dx, p.dy);
      }
    }
    fillPath.lineTo(w, h);
    fillPath.close();

    canvas.drawPath(fillPath, Paint()..color = fillColor);

    // Line path
    final linePath = Path();
    for (int i = 0; i < n; i++) {
      final p = point(i);
      if (i == 0) {
        linePath.moveTo(p.dx, p.dy);
      } else {
        final prev = point(i - 1);
        final cx = (prev.dx + p.dx) / 2;
        linePath.cubicTo(cx, prev.dy, cx, p.dy, p.dx, p.dy);
      }
    }

    canvas.drawPath(
      linePath,
      Paint()
        ..color = lineColor
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );

    // Dots
    for (int i = 0; i < n; i++) {
      if (data[i].revenue > 0) {
        canvas.drawCircle(
          point(i),
          3,
          Paint()..color = lineColor,
        );
      }
    }

    // Horizontal grid lines
    final gridPaint = Paint()
      ..color = (isDark ? Colors.white : Colors.black).withValues(alpha: 0.06)
      ..strokeWidth = 0.5;
    for (int g = 1; g <= 3; g++) {
      final y = h - (g / 4 * h * 0.9);
      canvas.drawLine(Offset(0, y), Offset(w, y), gridPaint);
    }
  }

  @override
  bool shouldRepaint(_LineChartPainter old) =>
      old.data != data || old.maxValue != maxValue;
}

// ─────────────────────────────────────────────────────────────────────────────
// Top items card
// ─────────────────────────────────────────────────────────────────────────────

class _TopItemsCard extends StatelessWidget {
  final List<_ItemStat> items;
  final bool isDark;

  const _TopItemsCard({required this.items, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppTheme.cardShadow(isDark),
      ),
      child: items.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                'No item data yet',
                style: TextStyle(
                    color: isDark
                        ? AppTheme.darkTextSecondary
                        : AppTheme.textSecondary),
              ),
            )
          : Column(
              children: List.generate(items.length, (i) {
                final item = items[i];
                final maxCount = items.first.count;
                final fraction =
                    maxCount > 0 ? item.count / maxCount : 0.0;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Row(
                    children: [
                      // Rank
                      Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: isDark
                              ? AppTheme.darkSurface
                              : Colors.grey.shade100,
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '${i + 1}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: isDark
                                ? AppTheme.darkTextSecondary
                                : AppTheme.textSecondary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      // Name
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.name,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: isDark
                                    ? AppTheme.darkTextPrimary
                                    : AppTheme.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 5),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: fraction,
                                minHeight: 6,
                                backgroundColor: isDark
                                    ? AppTheme.darkSurface
                                    : Colors.grey.shade100,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(
                                        AppTheme.primary),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      // Count
                      Text(
                        '${item.count}',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: isDark
                              ? AppTheme.darkTextSecondary
                              : AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Busiest hours chart (bar chart)
// ─────────────────────────────────────────────────────────────────────────────

class _HourChart extends StatelessWidget {
  final List<int> counts; // length 24
  final bool isDark;

  const _HourChart({required this.counts, required this.isDark});

  @override
  Widget build(BuildContext context) {
    // Show 6am–10pm (hours 6–22)
    final displayHours = List.generate(17, (i) => i + 6);
    final displayCounts = displayHours.map((h) => counts[h]).toList();
    final maxCount =
        displayCounts.fold(0, (m, c) => c > m ? c : m);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppTheme.cardShadow(isDark),
      ),
      child: maxCount == 0
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                'No hourly data yet',
                style: TextStyle(
                    color: isDark
                        ? AppTheme.darkTextSecondary
                        : AppTheme.textSecondary),
              ),
            )
          : Column(
              children: [
                SizedBox(
                  height: 80,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: List.generate(displayHours.length, (i) {
                      final frac = maxCount > 0
                          ? displayCounts[i] / maxCount
                          : 0.0;
                      final isHot = frac > 0.6;
                      return Expanded(
                        child: Padding(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 1.5),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              if (displayCounts[i] > 0)
                                Container(
                                  height:
                                      (frac * 70).clamp(4.0, 70.0),
                                  decoration: BoxDecoration(
                                    color: isHot
                                        ? AppTheme.primary
                                        : AppTheme.primary
                                            .withValues(alpha: 0.4),
                                    borderRadius: const BorderRadius.vertical(
                                        top: Radius.circular(3)),
                                  ),
                                )
                              else
                                Container(height: 4),
                            ],
                          ),
                        ),
                      );
                    }),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: List.generate(displayHours.length, (i) {
                    final h = displayHours[i];
                    final show = i == 0 ||
                        i == displayHours.length - 1 ||
                        i % 4 == 0;
                    String label = '';
                    if (show) {
                      label = h < 12
                          ? '${h}a'
                          : h == 12
                              ? '12p'
                              : '${h - 12}p';
                    }
                    return Expanded(
                      child: Text(
                        label,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 9,
                          color: isDark
                              ? AppTheme.darkTextSecondary
                              : AppTheme.textSecondary,
                        ),
                      ),
                    );
                  }),
                ),
              ],
            ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Completion rate
// ─────────────────────────────────────────────────────────────────────────────

class _CompletionRate extends StatelessWidget {
  final int completed;
  final int cancelled;
  final int active;
  final bool isDark;

  const _CompletionRate({
    required this.completed,
    required this.cancelled,
    required this.active,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final total = completed + cancelled + active;
    if (total == 0) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? AppTheme.darkCard : Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: AppTheme.cardShadow(isDark),
        ),
        child: Text(
          'No orders yet',
          style: TextStyle(
            color: isDark
                ? AppTheme.darkTextSecondary
                : AppTheme.textSecondary,
          ),
        ),
      );
    }

    final completedPct = completed / total;
    final cancelledPct = cancelled / total;
    final activePct = active / total;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppTheme.cardShadow(isDark),
      ),
      child: Column(
        children: [
          // Stacked bar
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: 14,
              child: Row(
                children: [
                  _BarSegment(flex: completedPct, color: AppTheme.success),
                  _BarSegment(flex: activePct, color: AppTheme.info),
                  _BarSegment(flex: cancelledPct, color: AppTheme.error),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _LegendItem(
                  color: AppTheme.success,
                  label: 'Completed',
                  pct: completedPct,
                  isDark: isDark),
              _LegendItem(
                  color: AppTheme.info,
                  label: 'Active',
                  pct: activePct,
                  isDark: isDark),
              _LegendItem(
                  color: AppTheme.error,
                  label: 'Cancelled',
                  pct: cancelledPct,
                  isDark: isDark),
            ],
          ),
        ],
      ),
    );
  }
}

class _BarSegment extends StatelessWidget {
  final double flex;
  final Color color;
  const _BarSegment({required this.flex, required this.color});

  @override
  Widget build(BuildContext context) {
    if (flex <= 0) return const SizedBox.shrink();
    return Expanded(
      flex: (flex * 100).round().clamp(1, 100),
      child: Container(color: color),
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;
  final double pct;
  final bool isDark;
  const _LegendItem(
      {required this.color,
      required this.label,
      required this.pct,
      required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Row(
        children: [
          Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                  color: color, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${(pct * 100).round()}%',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: isDark
                      ? AppTheme.darkTextPrimary
                      : AppTheme.textPrimary,
                ),
              ),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  color: isDark
                      ? AppTheme.darkTextSecondary
                      : AppTheme.textSecondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Error view
// ─────────────────────────────────────────────────────────────────────────────

class _ErrorView extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  const _ErrorView({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded,
                size: 48, color: AppTheme.error),
            const SizedBox(height: 12),
            const Text('Failed to load analytics',
                style:
                    TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(error,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white),
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}