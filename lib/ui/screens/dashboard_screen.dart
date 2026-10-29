import 'dart:math' as math;

import 'package:flutter/material.dart' hide Text;
import '../i18n/text.dart';
import 'package:provider/provider.dart';

import '../../data/models.dart';
import '../../data/quote.dart';
import '../../data/report.dart';
import '../../data/report_service.dart';
import '../../data/settings_store.dart';
import '../../logic/auth_provider.dart';
import '../../logic/credits_provider.dart';
import '../../logic/products_provider.dart';
import '../../logic/purchases_provider.dart';
import '../../logic/quotes_provider.dart';
import '../../logic/sales_provider.dart';
import '../../logic/settings_provider.dart';
import '../theme.dart';
import '../widgets/daily_goal_card.dart';
import 'closing_screen.dart';
import 'customer_display_screen.dart';
import 'credits_screen.dart';
import 'purchases_screen.dart';
import 'quotes_screen.dart';
import 'stats_screen.dart';
import '../i18n/date_fmt.dart';

/// Tabs the dashboard can jump to.
enum HomeTarget { cashier, stock, history }

/// Home tab: today's figures, shortcuts, things to watch and best sellers.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, required this.onGo});
  final void Function(HomeTarget) onGo;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Report? _today;
  Report? _yesterday;
  Object? _seen;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final svc = context.read<ReportService>();
    final n = DateTime.now();
    final start = DateTime(n.year, n.month, n.day);
    final end = start.add(const Duration(days: 1));
    final t = await svc.load(start, end);
    final y = await svc.load(start.subtract(const Duration(days: 1)), start);
    if (!mounted) return;
    setState(() {
      _today = t;
      _yesterday = y;
    });
  }

  String get _greeting {
    final h = DateTime.now().hour;
    return h < 12 ? 'Bonjour' : (h < 18 ? 'Bon après-midi' : 'Bonsoir');
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final s = context.watch<SettingsProvider>().settings;
    final auth = context.watch<AuthProvider>();
    final sales = context.watch<SalesProvider>();
    if (!identical(_seen, sales.sales)) {
      // A sale or a return was recorded: refresh the figures.
      if (_seen != null) WidgetsBinding.instance.addPostFrameCallback((_) => _load());
      _seen = sales.sales;
    }
    final canSeeMoney = auth.can(Perm.history);
    final name = auth.currentName;
    final date = DateFmt('EEEE d MMMM').format(DateTime.now());

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
        children: [
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('$_greeting${name == null ? '' : ', $name'} 👋',
                    style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: -0.6)),
                const SizedBox(height: 2),
                Text('${s.storeName} · ${date[0].toUpperCase()}${date.substring(1)}',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: pal.muted, fontWeight: FontWeight.w700)),
              ]),
            ),
          ]),
          const SizedBox(height: 16),
          if (canSeeMoney) ...[
            _HeroCard(today: _today, yesterday: _yesterday, settings: s),
            const SizedBox(height: 12),
            const DailyGoalCard(padding: EdgeInsets.zero),
            const SizedBox(height: 18),
          ],
          _sectionTitle(context, 'Accès rapide'),
          _QuickActions(onGo: widget.onGo),
          _Alerts(onGo: widget.onGo, settings: s),
          if (canSeeMoney && _today != null && !_today!.isEmpty) ...[
            const SizedBox(height: 18),
            _sectionTitle(context, 'Ventes par heure'),
            _HoursChart(report: _today!, settings: s),
            if (_today!.top(5).isNotEmpty) ...[
              const SizedBox(height: 18),
              _sectionTitle(context, 'Meilleures ventes du jour'),
              _TopProducts(report: _today!, settings: s),
            ],
          ],
        ],
      ),
    );
  }
}

Widget _sectionTitle(BuildContext context, String t) => Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 0, 10),
      child: Text(t.toUpperCase(), style: TextStyle(color: context.pal.muted, fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 1.2)),
    );

// ---------------------------------------------------------------------------

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.today, required this.yesterday, required this.settings});
  final Report? today;
  final Report? yesterday;
  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    final t = today;
    final net = t?.net ?? 0;
    final growth = t != null && yesterday != null ? t.growthVs(yesterday!) : null;
    // Cumulative revenue up to the current hour for the sparkline.
    final nowH = DateTime.now().hour;
    final cum = <double>[];
    var run = 0.0;
    for (var h = 0; h <= nowH; h++) {
      run += t?.byHour[h] ?? 0;
      cum.add(run);
    }

    Widget kpi(String label, String value) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(16)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Text(value, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w900)),
              ),
            ]),
          ),
        );

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
      decoration: BoxDecoration(
        gradient: kHeroGradient,
        borderRadius: BorderRadius.circular(30),
        boxShadow: accentShadow(blur: 26, dy: 12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Expanded(
            child: Text("CHIFFRE D'AFFAIRES DU JOUR",
                style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.3)),
          ),
          if (growth != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(20)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(growth >= 0 ? Icons.trending_up_rounded : Icons.trending_down_rounded, size: 15, color: Colors.white),
                const SizedBox(width: 4),
                Text('${growth >= 0 ? '+' : ''}${growth.toStringAsFixed(0)} % vs hier',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12)),
              ]),
            ),
        ]),
        const SizedBox(height: 4),
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: net),
          duration: const Duration(milliseconds: 900),
          curve: Curves.easeOutCubic,
          builder: (_, v, _) => FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(settings.money(v),
                style: const TextStyle(color: Colors.white, fontSize: 44, fontWeight: FontWeight.w900, letterSpacing: -1.5)),
          ),
        ),
        SizedBox(
          height: 64,
          child: CustomPaint(size: const Size(double.infinity, 64), painter: _SparkPainter(cum)),
        ),
        const SizedBox(height: 8),
        Row(children: [
          kpi('Ventes', '${t?.salesCount ?? 0}'),
          const SizedBox(width: 8),
          kpi('Panier moyen', settings.money(t?.avgBasket ?? 0)),
          const SizedBox(width: 8),
          kpi('Bénéfice', settings.money(t?.profit ?? 0)),
        ]),
      ]),
    );
  }
}

/// Smooth white area chart of the day's cumulative revenue.
class _SparkPainter extends CustomPainter {
  _SparkPainter(this.values);
  final List<double> values;

  @override
  void paint(Canvas canvas, Size size) {
    final maxV = values.isEmpty ? 0.0 : values.reduce(math.max);
    final base = Paint()
      ..color = Colors.white.withValues(alpha: 0.25)
      ..strokeWidth = 1.5;
    if (values.length < 2 || maxV <= 0) {
      canvas.drawLine(Offset(0, size.height - 2), Offset(size.width, size.height - 2), base);
      return;
    }
    final dx = size.width / (values.length - 1);
    Offset pt(int i) => Offset(i * dx, size.height - 6 - (values[i] / maxV) * (size.height - 14));
    final line = Path()..moveTo(pt(0).dx, pt(0).dy);
    for (var i = 1; i < values.length; i++) {
      final a = pt(i - 1), b = pt(i);
      final mid = (a.dx + b.dx) / 2;
      line.cubicTo(mid, a.dy, mid, b.dy, b.dx, b.dy);
    }
    final area = Path.from(line)
      ..lineTo(pt(values.length - 1).dx, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.white.withValues(alpha: 0.35), Colors.white.withValues(alpha: 0)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      line,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
    final last = pt(values.length - 1);
    canvas.drawCircle(last, 5, Paint()..color = Colors.white);
    canvas.drawCircle(last, 9, Paint()..color = Colors.white.withValues(alpha: 0.25));
  }

  @override
  bool shouldRepaint(_SparkPainter old) => old.values.length != values.length || (values.isNotEmpty && old.values.last != values.last);
}

// ---------------------------------------------------------------------------

class _Action {
  const _Action(this.label, this.icon, this.colors, this.onTap);
  final String label;
  final IconData icon;
  final List<Color> colors;
  final VoidCallback onTap;
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.onGo});
  final void Function(HomeTarget) onGo;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    void push(Widget w) => Navigator.push(context, MaterialPageRoute(builder: (_) => w));
    final actions = <_Action>[
      _Action('Caisse', Icons.point_of_sale_rounded, [AppAccent.current.light, AppAccent.current.main], () => onGo(HomeTarget.cashier)),
      _Action('Devis', Icons.description_rounded, const [Color(0xFFA78BFA), Color(0xFF6D28D9)], () => push(const QuotesScreen())),
      _Action('Crédit', Icons.account_balance_wallet_rounded, const [Color(0xFFFBBF24), Color(0xFFEA580C)], () => push(const CreditsScreen())),
      if (auth.can(Perm.stock))
        _Action('Achats', Icons.local_shipping_rounded, const [Color(0xFF34D673), Color(0xFF12A150)], () => push(const PurchasesScreen())),
      if (auth.can(Perm.stock)) _Action('Stock', Icons.warehouse_rounded, const [Color(0xFF22D3EE), Color(0xFF0891B2)], () => onGo(HomeTarget.stock)),
      if (auth.can(Perm.history))
        _Action('Stats', Icons.insights_rounded, const [Color(0xFFFB7185), Color(0xFFE11D48)], () => push(const StatsScreen())),
      if (auth.can(Perm.closing))
        _Action('Clôture', Icons.lock_clock_rounded, const [Color(0xFF94A3B8), Color(0xFF475569)], () => push(const ClosingScreen())),
      _Action('Écran client', Icons.cast_connected_rounded, const [Color(0xFF818CF8), Color(0xFF4338CA)], () => push(const CustomerDisplayScreen())),
    ];
    const perRow = 4;
    final rows = <Widget>[];
    for (var i = 0; i < actions.length; i += perRow) {
      final chunk = actions.skip(i).take(perRow).toList();
      rows.add(Padding(
        padding: EdgeInsets.only(top: i == 0 ? 0 : 12),
        child: Row(children: [
          for (var j = 0; j < perRow; j++) ...[
            if (j > 0) const SizedBox(width: 10),
            Expanded(child: j < chunk.length ? _ActionTile(action: chunk[j]) : const SizedBox()),
          ],
        ]),
      ));
    }
    return Column(children: rows);
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({required this.action});
  final _Action action;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return Material(
      color: pal.card,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: action.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(22), boxShadow: pal.shadow),
          child: Column(children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: action.colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: action.colors.last.withValues(alpha: 0.38), blurRadius: 10, offset: const Offset(0, 4))],
              ),
              child: Icon(action.icon, color: Colors.white, size: 24),
            ),
            const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(action.label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
            ),
          ]),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _Alerts extends StatelessWidget {
  const _Alerts({required this.onGo, required this.settings});
  final void Function(HomeTarget) onGo;
  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final auth = context.watch<AuthProvider>();
    final low = context.watch<ProductsProvider>().lowCount;
    final credits = context.watch<CreditsProvider>();
    final purchases = context.watch<PurchasesProvider>();
    final pendingQuotes = context.watch<QuotesProvider>().quotes.where((q) => q.status == QuoteStatus.pending).length;
    void push(Widget w) => Navigator.push(context, MaterialPageRoute(builder: (_) => w));

    final items = <Widget>[
      if (low > 0 && auth.can(Perm.stock))
        _alert(context, Icons.warning_amber_rounded, const Color(0xFFEA580C), '$low produit${low > 1 ? 's' : ''} en stock bas', 'À réapprovisionner',
            () => onGo(HomeTarget.stock)),
      if (credits.outstanding > 0.0005)
        _alert(context, Icons.account_balance_wallet_rounded, pal.badFg, '${settings.money(credits.outstanding)} à récupérer',
            '${credits.open.length} client${credits.open.length > 1 ? 's' : ''} avec un crédit', () => push(const CreditsScreen())),
      if (purchases.owed > 0.0005 && auth.can(Perm.stock))
        _alert(context, Icons.local_shipping_rounded, const Color(0xFF6D28D9), '${settings.money(purchases.owed)} à payer', 'Aux fournisseurs',
            () => push(const PurchasesScreen())),
      if (pendingQuotes > 0)
        _alert(context, Icons.description_rounded, kBlue, '$pendingQuotes devis en attente', 'À relancer', () => push(const QuotesScreen())),
    ];
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _sectionTitle(context, 'À surveiller'),
        ...items,
      ]),
    );
  }

  Widget _alert(BuildContext context, IconData icon, Color color, String title, String sub, VoidCallback onTap) {
    final pal = context.pal;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: pal.card,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), boxShadow: pal.shadow),
            child: Row(children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(14)),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                  Text(sub, style: TextStyle(color: pal.muted, fontWeight: FontWeight.w700, fontSize: 12)),
                ]),
              ),
              Icon(Icons.chevron_right_rounded, color: pal.muted),
            ]),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _HoursChart extends StatelessWidget {
  const _HoursChart({required this.report, required this.settings});
  final Report report;
  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    const from = 6, to = 23;
    final vals = [for (var h = from; h <= to; h++) math.max(0.0, report.byHour[h])];
    final maxV = vals.reduce(math.max);
    final peak = report.peakHour;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      decoration: BoxDecoration(color: pal.card, borderRadius: BorderRadius.circular(22), boxShadow: pal.shadow),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (peak != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text('Pic à $peak h · ${settings.money(report.byHour[peak])}', style: TextStyle(color: pal.muted, fontWeight: FontWeight.w800, fontSize: 12)),
          ),
        SizedBox(
          height: 96,
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            for (var i = 0; i < vals.length; i++)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 1.5),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: maxV <= 0 ? 0 : vals[i] / maxV),
                    duration: Duration(milliseconds: 500 + i * 25),
                    curve: Curves.easeOutCubic,
                    builder: (_, v, _) => FractionallySizedBox(
                      heightFactor: math.max(v, 0.04),
                      alignment: Alignment.bottomCenter,
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(5),
                          gradient: vals[i] <= 0
                              ? null
                              : LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: from + i == peak ? const [Color(0xFF34D673), Color(0xFF12A150)] : [AppAccent.current.light, AppAccent.current.main],
                                ),
                          color: vals[i] <= 0 ? pal.soft2 : null,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 6),
        Row(children: [
          for (var h = from; h <= to; h++)
            Expanded(
              child: Text(h % 3 == 0 ? '$h' : '', textAlign: TextAlign.center, style: TextStyle(color: pal.muted, fontSize: 10, fontWeight: FontWeight.w700)),
            ),
        ]),
      ]),
    );
  }
}

class _TopProducts extends StatelessWidget {
  const _TopProducts({required this.report, required this.settings});
  final Report report;
  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final top = report.top(5);
    final maxR = top.first.revenue <= 0 ? 1.0 : top.first.revenue;
    const medals = [Color(0xFFFBBF24), Color(0xFF94A3B8), Color(0xFFD97706)];
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
      decoration: BoxDecoration(color: pal.card, borderRadius: BorderRadius.circular(22), boxShadow: pal.shadow),
      child: Column(children: [
        for (var i = 0; i < top.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: (i < 3 ? medals[i] : pal.soft).withValues(alpha: i < 3 ? 0.25 : 1),
                child: Text('${i + 1}', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: i < 3 ? medals[i] : pal.accent)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text(top[i].name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800))),
                    Text(settings.money(top[i].revenue), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
                  ]),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: top[i].revenue / maxR),
                      duration: const Duration(milliseconds: 700),
                      curve: Curves.easeOutCubic,
                      builder: (_, v, _) => LinearProgressIndicator(
                        value: v,
                        minHeight: 6,
                        backgroundColor: pal.soft2,
                        valueColor: AlwaysStoppedAnimation(kBlue),
                      ),
                    ),
                  ),
                ]),
              ),
            ]),
          ),
      ]),
    );
  }
}
