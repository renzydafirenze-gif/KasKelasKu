import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'data/repository.dart';
import 'models.dart';
import 'view_model.dart';

const String appVersion = '1.2.2';

// coverage:ignore-start
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: KasKelasKuApp()));
}
// coverage:ignore-end

String rupiah(int amount) =>
    NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0)
        .format(amount);

const _months = [
  'Januari',
  'Februari',
  'Maret',
  'April',
  'Mei',
  'Juni',
  'Juli',
  'Agustus',
  'September',
  'Oktober',
  'November',
  'Desember'
];
const _monthsShort = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'Mei',
  'Jun',
  'Jul',
  'Agu',
  'Sep',
  'Okt',
  'Nov',
  'Des'
];

String monthLabel(String period) =>
    '${_months[int.parse(period.substring(5, 7)) - 1]} ${period.substring(0, 4)}';

String shortMonthLabel(String period) =>
    '${_monthsShort[int.parse(period.substring(5, 7)) - 1]} ${period.substring(2, 4)}';

String dateLabel(String iso) {
  final date = DateTime.parse(iso);
  return '${date.day} ${_monthsShort[date.month - 1]} ${date.year}';
}

String periodOf(DateTime date) => monthOf(date);

Future<void> showError(BuildContext context, Object error) async {
  if (!context.mounted) return;
  final message = error is AppError
      ? error.message
      : 'Operasi gagal. Data lama tetap tersimpan.';
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

Future<void> showInfo(BuildContext context, String message) async {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

ThemeData _theme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF0F766E), brightness: brightness);
  final base = ThemeData(
      useMaterial3: true, colorScheme: scheme, brightness: brightness);
  final text = base.textTheme.copyWith(
    headlineLarge: base.textTheme.headlineLarge
        ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -1),
    headlineMedium: base.textTheme.headlineMedium
        ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.6),
    titleLarge:
        base.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
    titleMedium:
        base.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
    labelLarge:
        base.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
  );
  return base.copyWith(
    scaffoldBackgroundColor:
        dark ? const Color(0xFF0E1413) : const Color(0xFFF4F7F5),
    textTheme: text,
    cardTheme: CardTheme(
        elevation: 0,
        color: dark ? const Color(0xFF18201F) : Colors.white,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24))),
    appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge?.copyWith(color: scheme.onSurface)),
    inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? const Color(0xFF1F2827) : Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: scheme.primary, width: 1.5))),
    filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
            minimumSize: const Size(0, 52),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            textStyle: const TextStyle(fontWeight: FontWeight.w700))),
    outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 52),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            textStyle: const TextStyle(fontWeight: FontWeight.w600))),
    navigationBarTheme: NavigationBarThemeData(
        backgroundColor: dark ? const Color(0xFF141B1A) : Colors.white,
        surfaceTintColor: Colors.transparent,
        indicatorColor: scheme.primaryContainer,
        elevation: 0,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow),
    dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withOpacity(0.4), space: 1, thickness: 1),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}

class KasKelasKuApp extends HookConsumerWidget {
  const KasKelasKuApp({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dark = ref.watch(darkModeProvider);
    return MaterialApp(
      title: 'KasKelasKu',
      debugShowCheckedModeBanner: false,
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      home: const _Gate(),
    );
  }
}

class _Gate extends ConsumerStatefulWidget {
  const _Gate();
  @override
  ConsumerState<_Gate> createState() => _GateState();
}

class _GateState extends ConsumerState<_Gate> {
  bool _loading = true;
  Member? _user;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final user = await ref.read(treasuryProvider).repository.open();
      if (!mounted) return;
      setState(() {
        _user = user;
        _error = null;
        _loading = false;
      });
      ref.read(sessionProvider.state).state = user;
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const _Splash();
    if (_error != null) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.storage_outlined, size: 56),
                const SizedBox(height: 16),
                const Text('Data tidak bisa dibuka.',
                    style:
                        TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                const Text('Data lama tetap tersimpan. Coba lagi.',
                    textAlign: TextAlign.center),
                const SizedBox(height: 24),
                FilledButton(onPressed: _load, child: const Text('Coba lagi')),
              ]),
            ),
          ),
        ),
      );
    }
    final user = _user;
    if (user == null) {
      return OnboardingScreen(onCreated: (member) {
        setState(() => _user = member);
        ref.read(sessionProvider.state).state = member;
      });
    }
    return const HomeScreen();
  }
}

class _Splash extends StatelessWidget {
  const _Splash();
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const _Logo(size: 64),
          const SizedBox(height: 20),
          Text('KasKelasKu',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.4)),
          const SizedBox(height: 24),
          const SizedBox(
              width: 24, height: 24, child: CircularProgressIndicator()),
        ]),
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo({this.size = 48});
  final double size;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
          gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [scheme.primary, scheme.primary.withOpacity(0.72)]),
          borderRadius: BorderRadius.circular(size * 0.3)),
      child: Icon(Icons.savings_outlined,
          color: scheme.onPrimary, size: size * 0.5),
    );
  }
}

class OnboardingScreen extends HookConsumerWidget {
  const OnboardingScreen({super.key, required this.onCreated});
  final ValueChanged<Member> onCreated;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = useTextEditingController();
    final busy = useState(false);
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Center(child: _Logo(size: 72)),
                    const SizedBox(height: 28),
                    Text('KasKelasKu',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineLarge),
                    const SizedBox(height: 8),
                    Text('Catatan kas kelas yang rapi, cepat, dan offline.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyLarge?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant)),
                    const SizedBox(height: 32),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text('Mulai', style: theme.textTheme.titleLarge),
                              const SizedBox(height: 4),
                              Text('Kamu akan menjadi Bendahara.',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                      color:
                                          theme.colorScheme.onSurfaceVariant)),
                              const SizedBox(height: 20),
                              TextField(
                                key: const Key('owner_name_input'),
                                controller: name,
                                textCapitalization: TextCapitalization.words,
                                decoration: const InputDecoration(
                                    labelText: 'Nama kamu',
                                    hintText: 'Contoh: Budi'),
                                onSubmitted: (_) => _create(
                                    context, ref, name, busy, onCreated),
                              ),
                              const SizedBox(height: 20),
                              FilledButton(
                                key: const Key('start_btn'),
                                onPressed: busy.value
                                    ? null
                                    : () => _create(
                                        context, ref, name, busy, onCreated),
                                child:
                                    Text(busy.value ? 'Menyiapkan…' : 'Mulai'),
                              ),
                            ]),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text('Data disimpan di perangkat ini.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant)),
                  ]),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _create(
      BuildContext context,
      WidgetRef ref,
      TextEditingController name,
      ValueNotifier<bool> busy,
      ValueChanged<Member> onCreated) async {
    busy.value = true;
    try {
      final member =
          await ref.read(treasuryProvider).repository.createOwner(name.text);
      onCreated(member);
    } catch (error) {
      if (context.mounted) await showError(context, error);
    } finally {
      busy.value = false;
    }
  }
}

class HomeScreen extends HookConsumerWidget {
  const HomeScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final page = useState(0);
    final user = ref.watch(sessionProvider);
    if (user == null) return const SizedBox();
    final canWrite = user.role == Role.bendahara;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 20,
        title: const Row(children: [
          _Logo(size: 32),
          SizedBox(width: 10),
          Flexible(
              child: Text('KasKelasKu',
                  maxLines: 1, overflow: TextOverflow.ellipsis)),
        ]),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: ActionChip(
              avatar: CircleAvatar(
                  backgroundColor: scheme.primaryContainer,
                  child: Text(
                      user.name.trim().isEmpty
                          ? '?'
                          : user.name.trim()[0].toUpperCase(),
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: scheme.onPrimaryContainer))),
              label: Text('${user.name.split(' ').first} · ${user.role.label}',
                  style: const TextStyle(fontSize: 12)),
              onPressed: () => _showUserSheet(context, ref),
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: switch (page.value) {
              0 => DashboardScreen(onSeeAll: () => page.value = 1),
              1 => const HistoryScreen(),
              2 => const ReportsScreen(),
              3 => const MembersScreen(),
              _ => const SettingsScreen(),
            },
          ),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: page.value,
        onDestinationSelected: (value) => page.value = value,
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.space_dashboard_outlined),
              selectedIcon: Icon(Icons.space_dashboard),
              label: 'Ringkasan'),
          NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined),
              selectedIcon: Icon(Icons.receipt_long),
              label: 'Riwayat'),
          NavigationDestination(
              icon: Icon(Icons.summarize_outlined),
              selectedIcon: Icon(Icons.summarize),
              label: 'Laporan'),
          NavigationDestination(
              icon: Icon(Icons.group_outlined),
              selectedIcon: Icon(Icons.group),
              label: 'Anggota'),
          NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings),
              label: 'Setelan'),
        ],
      ),
      floatingActionButton: canWrite && page.value < 2
          ? FloatingActionButton.extended(
              key: const Key('add_transaction_btn'),
              onPressed: () => openTransactionEntry(context),
              icon: const Icon(Icons.add),
              label: const Text('Catat'))
          : null,
    );
  }
}

Future<void> openTransactionEntry(BuildContext context,
    {String initialType = 'IN',
    String? contributorId,
    String initialCategory = ''}) {
  return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => TransactionEntry(
          initialType: initialType,
          initialContributor: contributorId,
          initialCategory: initialCategory));
}

Future<void> _showUserSheet(BuildContext context, WidgetRef ref) async {
  final model = ref.read(treasuryProvider);
  final List<Member> members;
  try {
    members = await model.repository.members();
  } catch (error) {
    if (context.mounted) await showError(context, error);
    return;
  }
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Row(children: [
                Text('Ganti pengguna',
                    style: Theme.of(sheetContext).textTheme.titleLarge),
              ]),
            ),
            for (final member in members.where((m) => m.active))
              RadioListTile<String>(
                  value: member.id,
                  groupValue: ref.read(sessionProvider)?.id,
                  title: Text(member.name),
                  subtitle: Text(member.role.label),
                  onChanged: (id) async {
                    if (id == null) return;
                    try {
                      final active = await model.repository.switchUser(id);
                      ref.read(sessionProvider.state).state = active;
                      if (sheetContext.mounted) {
                        Navigator.pop(sheetContext);
                      }
                    } catch (error) {
                      if (sheetContext.mounted) {
                        await showError(sheetContext, error);
                      }
                    }
                  }),
            const SizedBox(height: 8),
          ])));
}

class DashboardScreen extends HookConsumerWidget {
  const DashboardScreen({super.key, this.onSeeAll});
  final VoidCallback? onSeeAll;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final model = ref.watch(treasuryProvider);
    final revision = ref.watch(revisionProvider);
    final user = ref.watch(sessionProvider);
    final tick = useState(0);
    final period = periodOf(DateTime.now());
    final future = useMemoized(() async {
      final data = await model.repository.overview(period);
      final members = await model.repository.members();
      return (data, members);
    }, [revision, period, tick.value]);
    final snapshot = useFuture(future);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    if (snapshot.hasError) {
      return Center(
          child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.error_outline, size: 40),
                const SizedBox(height: 12),
                const Text('Ringkasan gagal dimuat.'),
                const SizedBox(height: 16),
                FilledButton(
                    onPressed: () => tick.value++,
                    child: const Text('Muat ulang')),
              ])));
    }
    if (!snapshot.hasData) {
      return const Center(child: CircularProgressIndicator());
    }
    final (data, _) = snapshot.data!;
    final canWrite = user?.role == Role.bendahara;
    final progress =
        data.target == 0 ? 0.0 : (data.paid / data.target).clamp(0.0, 1.0);
    final paid = data.paid >= data.target && data.target > 0;
    final points = data.trends
        .map((row) => (row['net']! as int).toDouble())
        .toList()
        .reversed
        .take(6)
        .toList()
        .reversed
        .toList();
    return RefreshIndicator(
      onRefresh: () async {
        tick.value++;
        await Future<void>.delayed(const Duration(milliseconds: 300));
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 100),
        children: [
          Text('Halo, ${user?.name.split(' ').first ?? 'Bendahara'}',
              style: theme.textTheme.headlineMedium),
          const SizedBox(height: 4),
          Text('Ini kondisi kas kelasmu hari ini.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [scheme.primary, const Color(0xFF115E59)]),
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                    color: scheme.primary.withOpacity(0.25),
                    blurRadius: 24,
                    offset: const Offset(0, 10))
              ],
            ),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.account_balance_wallet_outlined,
                    color: Colors.white.withOpacity(0.8), size: 18),
                const SizedBox(width: 8),
                Text('Saldo kelas',
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.85),
                        fontWeight: FontWeight.w600)),
              ]),
              const SizedBox(height: 10),
              Text(rupiah(data.balance),
                  style: theme.textTheme.headlineLarge?.copyWith(
                      color: Colors.white,
                      fontSize: 36,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 20),
              Row(children: [
                Expanded(
                    child: _MoneyPill(
                        icon: Icons.south_west,
                        label: 'Masuk',
                        amount: data.income)),
                const SizedBox(width: 10),
                Expanded(
                    child: _MoneyPill(
                        icon: Icons.north_east,
                        label: 'Keluar',
                        amount: data.expense)),
              ]),
            ]),
          ),
          const SizedBox(height: 20),
          if (canWrite)
            Row(children: [
              Expanded(
                  child: _QuickAction(
                      icon: Icons.add_circle_outline,
                      label: 'Uang masuk',
                      color: scheme.primary,
                      background: scheme.primaryContainer,
                      onTap: () => openTransactionEntry(context))),
              const SizedBox(width: 12),
              Expanded(
                  child: _QuickAction(
                      icon: Icons.remove_circle_outline,
                      label: 'Uang keluar',
                      color: scheme.error,
                      background: scheme.errorContainer,
                      onTap: () =>
                          openTransactionEntry(context, initialType: 'OUT'))),
            ]),
          const SizedBox(height: 24),
          _SectionTitle('Target ${monthLabel(period)}',
              action: canWrite
                  ? TextButton(
                      key: const Key('edit_target_btn'),
                      onPressed: () =>
                          showTargetSheet(context, ref, period, data.target),
                      child: const Text('Atur'))
                  : null),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: data.target == 0
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                          Text('Belum ada target bulan ini',
                              style: theme.textTheme.titleMedium),
                          const SizedBox(height: 4),
                          Text(
                              'Tentukan target kas agar progress kelas terlihat.',
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: scheme.onSurfaceVariant)),
                          const SizedBox(height: 12),
                          if (canWrite)
                            OutlinedButton.icon(
                                onPressed: () => showTargetSheet(
                                    context, ref, period, data.target),
                                icon: const Icon(Icons.flag_outlined),
                                label: const Text('Tentukan target')),
                        ])
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                          Row(children: [
                            Expanded(
                                child: Text(rupiah(data.paid),
                                    style: theme.textTheme.headlineMedium)),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                  color: paid
                                      ? scheme.primaryContainer
                                      : scheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(20)),
                              child: Text(paid ? 'Lunas' : 'Belum lunas',
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: paid
                                          ? scheme.onPrimaryContainer
                                          : scheme.onSurfaceVariant)),
                            )
                          ]),
                          const SizedBox(height: 2),
                          Text('dari target ${rupiah(data.target)}',
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: scheme.onSurfaceVariant)),
                          const SizedBox(height: 14),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: LinearProgressIndicator(
                                value: progress,
                                minHeight: 10,
                                backgroundColor:
                                    scheme.surfaceContainerHighest),
                          ),
                          const SizedBox(height: 8),
                          Text('${(progress * 100).round()}% terkumpul',
                              style: theme.textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w600)),
                        ]),
            ),
          ),
          if (points.length > 1) ...[
            const SizedBox(height: 24),
            const _SectionTitle('Tren kas'),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: SizedBox(
                    height: 90,
                    child: CustomPaint(
                        painter: TrendPainter(points, scheme.primary),
                        child: const SizedBox.expand())),
              ),
            ),
          ],
          const SizedBox(height: 24),
          _SectionTitle('Transaksi terakhir',
              action: TextButton(
                  onPressed: onSeeAll, child: const Text('Lihat semua'))),
          const SizedBox(height: 8),
          if (data.recent.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(children: [
                  Icon(Icons.receipt_long_outlined,
                      size: 40, color: scheme.onSurfaceVariant),
                  const SizedBox(height: 12),
                  Text('Belum ada transaksi',
                      style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text('Mulai catat uang masuk kelas.',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant)),
                  if (canWrite) ...[
                    const SizedBox(height: 16),
                    FilledButton.icon(
                        onPressed: () => openTransactionEntry(context),
                        icon: const Icon(Icons.add),
                        label: const Text('Catat transaksi')),
                  ],
                ]),
              ),
            )
          else
            Card(
              child: Column(children: [
                for (var i = 0; i < data.recent.length; i++) ...[
                  if (i > 0) const Divider(indent: 68, endIndent: 16),
                  TransactionTile(entry: data.recent[i]),
                ],
              ]),
            ),
        ],
      ),
    );
  }
}

class _MoneyPill extends StatelessWidget {
  const _MoneyPill(
      {required this.icon, required this.label, required this.amount});
  final IconData icon;
  final String label;
  final int amount;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.14),
          borderRadius: BorderRadius.circular(14)),
      child: Row(children: [
        Icon(icon, size: 14, color: Colors.white.withOpacity(0.9)),
        const SizedBox(width: 6),
        Flexible(
            child: Text('$label ${rupiah(amount)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600))),
      ]),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction(
      {required this.icon,
      required this.label,
      required this.color,
      required this.background,
      required this.onTap});
  final IconData icon;
  final String label;
  final Color color;
  final Color background;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
          child: Row(children: [
            Icon(icon, color: color),
            const SizedBox(width: 10),
            Expanded(
                child: Text(label,
                    style:
                        TextStyle(color: color, fontWeight: FontWeight.w700))),
          ]),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title, {this.action});
  final String title;
  final Widget? action;
  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
      if (action != null) action!,
    ]);
  }
}

class TransactionTile extends StatelessWidget {
  const TransactionTile({super.key, required this.entry, this.onDelete});
  final CashTransaction entry;
  final VoidCallback? onDelete;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = entry.isIncome ? scheme.primary : scheme.error;
    final subtitle = [
      dateLabel(entry.date),
      if (entry.isIncome && entry.contributorName != null)
        entry.contributorName!
      else
        entry.description
    ].join(' · ');
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.12),
          child: Icon(entry.isIncome ? Icons.south_west : Icons.north_east,
              color: color, size: 20)),
      title: Text(entry.category, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: scheme.onSurfaceVariant)),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        Text('${entry.isIncome ? '+' : '-'}${rupiah(entry.amount)}',
            style: TextStyle(color: color, fontWeight: FontWeight.w700)),
        if (onDelete != null)
          IconButton(
              key: const Key('delete_tx_btn'),
              tooltip: 'Hapus transaksi',
              onPressed: onDelete,
              icon: const Icon(Icons.more_vert, size: 20)),
      ]),
    );
  }
}

class TrendPainter extends CustomPainter {
  TrendPainter(this.points, this.color);
  final List<double> points;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    final min = points.reduce((a, b) => a < b ? a : b);
    final max = points.reduce((a, b) => a > b ? a : b);
    final span = max == min ? 1.0 : max - min;
    final path = Path();
    final area = Path();
    for (var i = 0; i < points.length; i++) {
      final x = points.length == 1
          ? size.width / 2
          : i * size.width / (points.length - 1);
      final y = 8 + (size.height - 20) * (1 - (points[i] - min) / span);
      if (i == 0) {
        path.moveTo(x, y);
        area.moveTo(x, size.height);
        area.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        area.lineTo(x, y);
      }
      canvas.drawCircle(Offset(x, y), 4, Paint()..color = color);
    }
    area.lineTo(size.width, size.height);
    area.close();
    canvas.drawPath(
        area,
        Paint()
          ..shader = LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [color.withOpacity(0.25), color.withOpacity(0)])
              .createShader(Offset.zero & size));
    canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..strokeWidth = 3
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(TrendPainter oldDelegate) =>
      oldDelegate.points != points || oldDelegate.color != color;
}

class HistoryScreen extends HookConsumerWidget {
  const HistoryScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(treasuryProvider).repository;
    final revision = ref.watch(revisionProvider);
    final keyword = useTextEditingController();
    final query = useState('');
    final month = useState<String?>(null);
    final page = useState(0);
    final limit = (page.value + 1) * 100;
    final canDelete = ref.watch(sessionProvider)?.role == Role.bendahara;
    final future = useMemoized(() {
      final from = month.value == null ? null : '${month.value}-01';
      final to = month.value == null
          ? null
          : isoDate(DateTime(int.parse(month.value!.substring(0, 4)),
              int.parse(month.value!.substring(5, 7)) + 1, 0));
      return repo.history(
          keyword: query.value, from: from, to: to, limit: limit);
    }, [revision, query.value, month.value, page.value]);
    final snapshot = useFuture(future);
    final months = <String?>[
      null,
      for (var i = 0; i < 6; i++)
        periodOf(DateTime(DateTime.now().year, DateTime.now().month - i, 1))
    ];
    final scheme = Theme.of(context).colorScheme;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Riwayat', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 14),
          TextField(
            key: const Key('history_search'),
            controller: keyword,
            onChanged: (value) {
              page.value = 0;
              query.value = value.trim();
            },
            decoration: InputDecoration(
                hintText: 'Cari keterangan atau nama',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: query.value.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Hapus pencarian',
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          keyword.clear();
                          page.value = 0;
                          query.value = '';
                        })),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 38,
            child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: months.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final value = months[i];
                  return ChoiceChip(
                      label: Text(
                          value == null ? 'Semua' : shortMonthLabel(value)),
                      selected: month.value == value,
                      onSelected: (_) {
                        page.value = 0;
                        month.value = value;
                      });
                }),
          ),
        ]),
      ),
      const SizedBox(height: 8),
      Expanded(
        child: !snapshot.hasData && !snapshot.hasError
            ? const Center(child: CircularProgressIndicator())
            : snapshot.hasError
                ? Center(
                    child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text('Riwayat gagal dimuat. Periksa pencarian.',
                            style: TextStyle(color: scheme.error))))
                : snapshot.data!.isEmpty
                    ? Center(
                        child: Padding(
                            padding: const EdgeInsets.all(28),
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.search_off,
                                      size: 40, color: scheme.onSurfaceVariant),
                                  const SizedBox(height: 12),
                                  const Text('Tidak ada transaksi.'),
                                ])))
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                        itemCount: snapshot.data!.length +
                            (snapshot.data!.length == limit ? 1 : 0),
                        itemBuilder: (_, i) {
                          if (i == snapshot.data!.length) {
                            return Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: OutlinedButton(
                                  onPressed: () => page.value++,
                                  child: const Text('Muat lebih banyak')),
                            );
                          }
                          final entry = snapshot.data![i];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Card(
                                child: TransactionTile(
                                    entry: entry,
                                    onDelete: canDelete
                                        ? () => _confirmDelete(
                                            context, repo, entry.id!)
                                        : null)),
                          );
                        }),
      ),
    ]);
  }

  Future<void> _confirmDelete(
      BuildContext context, TreasuryRepository repo, int id) async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
                title: const Text('Hapus transaksi?'),
                content: const Text(
                    'Transaksi akan dihapus permanen dan dicatat di audit.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Batal')),
                  FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Hapus'))
                ]));
    if (confirmed != true) return;
    try {
      await repo.deleteTransaction(id);
    } catch (error) {
      if (context.mounted) await showError(context, error);
    }
  }
}

class ReportsScreen extends HookConsumerWidget {
  const ReportsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final model = ref.watch(treasuryProvider);
    final revision = ref.watch(revisionProvider);
    final user = ref.watch(sessionProvider);
    final period = useState(periodOf(DateTime.now()));
    final busy = useState(false);
    final future = useMemoized(
        () => model.repository.monthSnapshot(period.value),
        [revision, period.value]);
    final snapshot = useFuture(future);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    Future<void> run(Future<void> Function() action) async {
      busy.value = true;
      try {
        await action();
        if (context.mounted) await showInfo(context, 'Selesai.');
      } catch (error) {
        if (context.mounted) await showError(context, error);
      } finally {
        busy.value = false;
      }
    }

    Future<void> share(bool pdf) => run(() async {
          final files = await model.exports.report(period.value);
          await Share.shareXFiles(
              [XFile(pdf ? files.pdf.path : files.csv.path)],
              text: 'Laporan KasKelasKu ${period.value}',
              sharePositionOrigin: const Rect.fromLTWH(0, 0, 1, 1));
        });

    final data = snapshot.data;
    final target = data?['target']! as int? ?? 0;
    final paid = data?['paid']! as int? ?? 0;
    final progress = target == 0 ? 0.0 : (paid / target).clamp(0.0, 1.0);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 100),
      children: [
        Text('Laporan', style: theme.textTheme.headlineMedium),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                      tooltip: 'Bulan sebelumnya',
                      onPressed: () => period.value = periodOf(DateTime(
                          int.parse(period.value.substring(0, 4)),
                          int.parse(period.value.substring(5, 7)) - 1,
                          1)),
                      icon: const Icon(Icons.chevron_left)),
                  Text(monthLabel(period.value),
                      style: theme.textTheme.titleMedium),
                  IconButton(
                      tooltip: 'Bulan berikutnya',
                      onPressed: () => period.value = periodOf(DateTime(
                          int.parse(period.value.substring(0, 4)),
                          int.parse(period.value.substring(5, 7)) + 1,
                          1)),
                      icon: const Icon(Icons.chevron_right)),
                ]),
          ),
        ),
        const SizedBox(height: 12),
        if (data == null)
          const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()))
        else ...[
          Row(children: [
            Expanded(
                child: _StatCard(
                    label: 'Masuk',
                    value: rupiah(data['income']! as int),
                    color: scheme.primary)),
            const SizedBox(width: 10),
            Expanded(
                child: _StatCard(
                    label: 'Keluar',
                    value: rupiah(data['expense']! as int),
                    color: scheme.error)),
          ]),
          const SizedBox(height: 10),
          _StatCard(
              label: 'Saldo akhir ${shortMonthLabel(period.value)}',
              value: rupiah(data['closing']! as int),
              color: scheme.onSurface,
              wide: true),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(
                          child: Text('Target kas',
                              style: theme.textTheme.titleMedium)),
                      if (user?.role == Role.bendahara)
                        TextButton(
                            onPressed: () => showTargetSheet(
                                context, ref, period.value, target),
                            child: const Text('Atur')),
                    ]),
                    Text(
                        target == 0
                            ? 'Belum ditentukan'
                            : '${rupiah(paid)} dari ${rupiah(target)}',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: scheme.onSurfaceVariant)),
                    if (target > 0) ...[
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 10,
                            backgroundColor: scheme.surfaceContainerHighest),
                      ),
                      const SizedBox(height: 8),
                      Text(
                          paid >= target
                              ? 'Lunas'
                              : '${(progress * 100).round()}% terkumpul',
                          style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: scheme.onSurfaceVariant)),
                    ],
                  ]),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
              key: const Key('share_pdf_btn'),
              onPressed: busy.value ? null : () => share(true),
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: const Text('Bagikan PDF')),
          const SizedBox(height: 10),
          OutlinedButton.icon(
              key: const Key('share_csv_btn'),
              onPressed: busy.value ? null : () => share(false),
              icon: const Icon(Icons.table_chart_outlined),
              label: const Text('Bagikan CSV')),
          const SizedBox(height: 10),
          OutlinedButton.icon(
              onPressed: busy.value ? null : () => _share(context, model),
              icon: const Icon(Icons.cloud_download_outlined),
              label: const Text('Cadangkan data')),
          if (user?.role == Role.ketua) ...[
            const SizedBox(height: 20),
            const _SectionTitle('Persetujuan'),
            const SizedBox(height: 8),
            OutlinedButton.icon(
                onPressed: busy.value
                    ? null
                    : () async {
                        final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                                    title:
                                        const Text('Setujui dan kunci bulan?'),
                                    content: const Text(
                                        'Transaksi bulan ini tidak dapat ditambah atau dihapus setelah dikunci.'),
                                    actions: [
                                      TextButton(
                                          onPressed: () =>
                                              Navigator.pop(ctx, false),
                                          child: const Text('Batal')),
                                      FilledButton(
                                          onPressed: () =>
                                              Navigator.pop(ctx, true),
                                          child: const Text('Setujui'))
                                    ]));
                        if (confirmed == true) {
                          await run(
                              () => model.repository.approve(period.value));
                        }
                      },
                icon: const Icon(Icons.lock_outline),
                label: const Text('Setujui dan kunci')),
          ],
          if (user?.role == Role.guruWali) ...[
            const SizedBox(height: 20),
            const _SectionTitle('Verifikasi'),
            const SizedBox(height: 8),
            OutlinedButton.icon(
                onPressed: busy.value
                    ? null
                    : () => run(() => model.repository.verify(period.value)),
                icon: const Icon(Icons.verified_outlined),
                label: const Text('Verifikasi sebagai Guru Wali')),
          ],
        ],
        if (busy.value) ...[
          const SizedBox(height: 16),
          const LinearProgressIndicator(),
        ],
      ],
    );
  }

  // coverage:ignore-start
  Future<void> _share(BuildContext context, TreasuryViewModel model) async {
    try {
      final file = await model.exports.backup();
      await Share.shareXFiles([XFile(file.path)],
          text: 'Cadangan KasKelasKu',
          sharePositionOrigin: const Rect.fromLTWH(0, 0, 1, 1));
      if (context.mounted) {
        await showInfo(context, 'Cadangan siap dibagikan.');
      }
    } catch (error) {
      if (context.mounted) await showError(context, error);
    } // coverage:ignore-end
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard(
      {required this.label,
      required this.value,
      required this.color,
      this.wide = false});
  final String label;
  final String value;
  final Color color;
  final bool wide;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 6),
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleLarge
                  ?.copyWith(color: color, fontWeight: FontWeight.w800)),
        ]),
      ),
    );
  }
}

Future<void> showTargetSheet(
    BuildContext context, WidgetRef ref, String period, int current) {
  return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => TargetSheet(period: period, current: current));
}

class TargetSheet extends HookConsumerWidget {
  const TargetSheet({super.key, required this.period, required this.current});
  final String period;
  final int current;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final amount =
        useTextEditingController(text: current == 0 ? '' : '$current');
    final busy = useState(false);
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 0, 20, MediaQuery.viewInsetsOf(context).bottom + 24),
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Target ${monthLabel(period)}',
                style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text('Target kas keseluruhan bulan ini.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 16),
            TextField(
              key: const Key('target_input'),
              controller: amount,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                  labelText: 'Target rupiah', prefixText: 'Rp '),
            ),
            const SizedBox(height: 12),
            Wrap(spacing: 8, children: [
              for (final value in [10000, 20000, 50000, 100000, 200000])
                ActionChip(
                    label: Text(rupiah(value)),
                    onPressed: () => amount.text = '$value'),
            ]),
            const SizedBox(height: 20),
            FilledButton(
                key: const Key('save_target_btn'),
                onPressed: busy.value
                    ? null
                    : () async {
                        busy.value = true;
                        try {
                          await ref
                              .read(treasuryProvider)
                              .repository
                              .setTotalMonthlyTarget(
                                  period, int.tryParse(amount.text) ?? -1);
                          if (context.mounted) Navigator.pop(context);
                        } catch (error) {
                          if (context.mounted) await showError(context, error);
                        } finally {
                          busy.value = false;
                        }
                      },
                child: Text(busy.value ? 'Menyimpan…' : 'Simpan target')),
          ]),
    );
  }
}

class MembersScreen extends HookConsumerWidget {
  const MembersScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(treasuryProvider).repository;
    final revision = ref.watch(revisionProvider);
    final period = periodOf(DateTime.now());
    final future = useMemoized(() async {
      final members = await repo.members();
      final students = await repo.studentPayments(period);
      return (members, students);
    }, [revision, period]);
    final snapshot = useFuture(future);
    final editable = ref.watch(sessionProvider)!.role == Role.bendahara;
    final onlyUnpaid = useState(false);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
        child: Row(children: [
          Expanded(
              child: Text('Anggota', style: theme.textTheme.headlineMedium)),
          if (editable)
            FilledButton.icon(
                key: const Key('add_member_btn'),
                onPressed: () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    showDragHandle: true,
                    builder: (_) => const MemberSheet()),
                icon: const Icon(Icons.person_add_outlined, size: 18),
                label: const Text('Tambah')),
        ]),
      ),
      if (snapshot.hasError)
        Padding(
            padding: const EdgeInsets.all(20),
            child: Text('Daftar anggota gagal dimuat.',
                style: TextStyle(color: scheme.error)))
      else if (!snapshot.hasData)
        const Expanded(child: Center(child: CircularProgressIndicator()))
      else
        Expanded(
            child: _memberList(
                context, ref, snapshot.data!, editable, onlyUnpaid, period))
    ]);
  }

  Widget _memberList(
      BuildContext context,
      WidgetRef ref,
      (List<Member>, List<StudentPayment>) data,
      bool editable,
      ValueNotifier<bool> onlyUnpaid,
      String period) {
    final (members, students) = data;
    final paid = students.where((row) => row.paid).length;
    final totalPaid = students.fold<int>(0, (sum, row) => sum + row.total);
    final byId = {for (final row in students) row.member.id: row};
    final rows = onlyUnpaid.value && students.isNotEmpty
        ? students.where((row) => !row.paid).map((row) => row.member).toList()
        : members;
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
      children: [
        if (students.isNotEmpty) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$paid dari ${students.length} murid sudah bayar',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                          value: paid / students.length, minHeight: 8),
                    ),
                    const SizedBox(height: 8),
                    Text(
                        'Terkumpul ${rupiah(totalPaid)} · ${monthLabel(period)}',
                        style: TextStyle(
                            fontSize: 12, color: scheme.onSurfaceVariant)),
                  ]),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            ChoiceChip(
                key: const Key('filter_all_members'),
                label: const Text('Semua'),
                selected: !onlyUnpaid.value,
                onSelected: (_) => onlyUnpaid.value = false),
            ChoiceChip(
                key: const Key('filter_unpaid_btn'),
                label: Text('Belum bayar (${students.length - paid})'),
                selected: onlyUnpaid.value,
                onSelected: (_) => onlyUnpaid.value = true),
          ]),
          const SizedBox(height: 8),
        ],
        if (rows.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 28),
            child: Text('Semua murid sudah bayar.',
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurfaceVariant)),
          ),
        for (final member in rows) ...[
          Card(
            child: ListTile(
              onTap: editable
                  ? () => showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      showDragHandle: true,
                      builder: (_) => MemberSheet(member: member))
                  : null,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              leading: CircleAvatar(
                  backgroundColor: scheme.primaryContainer,
                  child: Text(
                      member.name.trim().isEmpty
                          ? '?'
                          : member.name.trim()[0].toUpperCase(),
                      style: TextStyle(
                          color: scheme.onPrimaryContainer,
                          fontWeight: FontWeight.w700))),
              title: Text(member.name,
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: member.active
                          ? scheme.onSurface
                          : scheme.onSurfaceVariant)),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                            color: scheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(20)),
                        child: Text(member.role.label,
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: scheme.onSurfaceVariant)),
                      ),
                      if (byId[member.id] != null)
                        _PaymentBadge(payment: byId[member.id]!),
                      if (!member.active)
                        Text('nonaktif',
                            style: TextStyle(
                                fontSize: 11, color: scheme.onSurfaceVariant)),
                    ]),
              ),
              trailing: editable && member.role == Role.siswa
                  ? FilledButton.tonalIcon(
                      key: Key('pay_${member.id}'),
                      onPressed: () => openTransactionEntry(context,
                          contributorId: member.id, initialCategory: 'Kas'),
                      icon: const Icon(Icons.payments_outlined, size: 16),
                      label: const Text('Bayar'))
                  : editable
                      ? Icon(Icons.chevron_right,
                          color: scheme.onSurfaceVariant)
                      : null,
            ),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _PaymentBadge extends StatelessWidget {
  const _PaymentBadge({required this.payment});
  final StudentPayment payment;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
          color: payment.paid
              ? scheme.primaryContainer
              : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20)),
      child: Text(
          payment.paid ? 'Lunas · ${rupiah(payment.total)}' : 'Belum bayar',
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: payment.paid
                  ? scheme.onPrimaryContainer
                  : scheme.onSurfaceVariant)),
    );
  }
}

class MemberSheet extends HookConsumerWidget {
  const MemberSheet({super.key, this.member});
  final Member? member;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final editing = member != null;
    final bulk = useState(false);
    final name = useTextEditingController(text: member?.name ?? '');
    final names = useTextEditingController();
    final role = useState(member?.role ?? Role.siswa);
    final active = useState(member?.active ?? true);
    final busy = useState(false);
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 0, 20, MediaQuery.viewInsetsOf(context).bottom + 24),
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
                editing
                    ? 'Ubah anggota'
                    : bulk.value
                        ? 'Tambah banyak murid'
                        : 'Tambah anggota',
                style: theme.textTheme.titleLarge),
            const SizedBox(height: 16),
            if (bulk.value)
              TextField(
                key: const Key('member_names_input'),
                controller: names,
                autofocus: true,
                minLines: 5,
                maxLines: 10,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                    labelText: 'Nama murid',
                    hintText: 'Satu nama per baris',
                    alignLabelWithHint: true),
              )
            else ...[
              TextField(
                key: const Key('member_name_input'),
                controller: name,
                enabled: !editing,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Nama'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<Role>(
                value: role.value,
                decoration: const InputDecoration(labelText: 'Peran'),
                items: Role.values
                    .map(
                        (r) => DropdownMenuItem(value: r, child: Text(r.label)))
                    .toList(),
                onChanged: (value) {
                  if (value != null) role.value = value;
                },
              ),
            ],
            if (editing) ...[
              const SizedBox(height: 4),
              SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Aktif'),
                  value: active.value,
                  onChanged: (value) => active.value = value),
            ],
            const SizedBox(height: 12),
            if (!editing)
              TextButton.icon(
                  key: const Key('toggle_bulk_member_btn'),
                  onPressed: () => bulk.value = !bulk.value,
                  icon: Icon(bulk.value
                      ? Icons.person_add_outlined
                      : Icons.playlist_add),
                  label: Text(bulk.value
                      ? 'Tambah satu per satu'
                      : 'Tambah banyak murid sekaligus')),
            const SizedBox(height: 4),
            FilledButton(
                key: const Key('save_member_btn'),
                onPressed: busy.value
                    ? null
                    : () async {
                        busy.value = true;
                        try {
                          final repo = ref.read(treasuryProvider).repository;
                          if (editing) {
                            await repo.changeMember(
                                member!, role.value, active.value);
                          } else if (bulk.value) {
                            await repo.addStudents(names.text
                                .split(RegExp(r'[\n,]'))
                                .map((row) => row.trim())
                                .toList());
                          } else {
                            await repo.addMember(name.text, role.value);
                          }
                          if (context.mounted) Navigator.pop(context);
                        } catch (error) {
                          if (context.mounted) await showError(context, error);
                        } finally {
                          busy.value = false;
                        }
                      },
                child: Text(busy.value ? 'Menyimpan…' : 'Simpan')),
          ]),
    );
  }
}

class SettingsScreen extends HookConsumerWidget {
  const SettingsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final model = ref.watch(treasuryProvider);
    final user = ref.watch(sessionProvider)!;
    final dark = ref.watch(darkModeProvider);
    final busy = useState(false);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    Future<void> restore() async {
      try {
        final result = await FilePicker.platform.pickFiles(type: FileType.any);
        final path = result?.files.single.path;
        if (path == null || !context.mounted) return;
        final confirmed = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
                    title: const Text('Pulihkan cadangan?'),
                    content: const Text(
                        'Pemulihan hanya untuk data kosong dan akan mengganti anggota, transaksi, laporan, serta target saat ini.'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Batal')),
                      FilledButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Pulihkan'))
                    ]));
        if (confirmed != true) return;
        busy.value = true;
        final member = await model.exports.restore(File(path));
        ref.read(sessionProvider.state).state = member;
        if (context.mounted) await showInfo(context, 'Cadangan dipulihkan.');
      } catch (error) {
        if (context.mounted) await showError(context, error);
      } finally {
        busy.value = false;
      }
    }

    Future<void> backup() async {
      try {
        busy.value = true;
        final file = await model.exports.backup();
        await Share.shareXFiles([XFile(file.path)],
            text: 'Cadangan KasKelasKu',
            sharePositionOrigin: const Rect.fromLTWH(0, 0, 1, 1));
        if (context.mounted) {
          await showInfo(context, 'Cadangan siap dibagikan.');
        }
      } catch (error) {
        if (context.mounted) await showError(context, error);
      } finally {
        busy.value = false;
      }
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 100),
      children: [
        Text('Setelan', style: theme.textTheme.headlineMedium),
        const SizedBox(height: 16),
        const _SectionTitle('Pengguna'),
        const SizedBox(height: 8),
        Card(
          child: ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            leading: CircleAvatar(
                backgroundColor: scheme.primaryContainer,
                child: Text(
                    user.name.trim().isEmpty
                        ? '?'
                        : user.name.trim()[0].toUpperCase(),
                    style: TextStyle(
                        color: scheme.onPrimaryContainer,
                        fontWeight: FontWeight.w700))),
            title: Text(user.name,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(user.role.label),
            trailing: OutlinedButton(
                onPressed: () => _showUserSheet(context, ref),
                child: const Text('Ganti')),
          ),
        ),
        const SizedBox(height: 20),
        const _SectionTitle('Tampilan'),
        const SizedBox(height: 8),
        Card(
          child: SwitchListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            secondary: Icon(dark ? Icons.dark_mode : Icons.light_mode,
                color: scheme.primary),
            title: const Text('Mode gelap'),
            value: dark,
            onChanged: (value) =>
                ref.read(darkModeProvider.state).state = value,
          ),
        ),
        const SizedBox(height: 20),
        const _SectionTitle('Data'),
        const SizedBox(height: 8),
        Card(
          child: Column(children: [
            ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
              leading:
                  Icon(Icons.cloud_download_outlined, color: scheme.primary),
              title: const Text('Cadangkan data'),
              subtitle: const Text('Berkas JSON berisi semua catatan'),
              onTap: busy.value ? null : backup,
            ),
            const Divider(indent: 56, endIndent: 16),
            ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
              leading: Icon(Icons.restore_outlined, color: scheme.primary),
              title: const Text('Pulihkan cadangan'),
              subtitle: const Text('Hanya untuk data yang masih kosong'),
              onTap: busy.value ? null : restore,
            ),
          ]),
        ),
        if (busy.value) ...[
          const SizedBox(height: 12),
          const LinearProgressIndicator(),
        ],
        const SizedBox(height: 20),
        Card(
          color: scheme.surfaceContainerHighest.withOpacity(0.5),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.info_outline,
                  size: 18, color: scheme.onSurfaceVariant),
              const SizedBox(width: 10),
              Expanded(
                  child: Text(
                      'Data disimpan di perangkat ini tanpa enkripsi. Siapa pun yang membuka aplikasi dapat melihat dan mengubah data.',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant))),
            ]),
          ),
        ),
        const SizedBox(height: 24),
        Center(
            child: Text('KasKelasKu $appVersion',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant))),
      ],
    );
  }
}

class TransactionEntry extends HookConsumerWidget {
  const TransactionEntry(
      {super.key,
      this.initialType = 'IN',
      this.initialContributor,
      this.initialCategory = ''});
  final String initialType;
  final String? initialContributor;
  final String initialCategory;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final amount = useTextEditingController();
    final category = useTextEditingController(text: initialCategory);
    final description = useTextEditingController();
    final date = useState(DateTime.now());
    final type = useState(initialType);
    final contributor = useState<String?>(initialContributor);
    final saving = useRef(false);
    final busy = useState(false);
    final membersFuture =
        useMemoized(() => ref.read(treasuryProvider).repository.members());
    final members = useFuture(membersFuture);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    const categories = ['Kas', 'Iuran', 'Kebersihan', 'Kegiatan', 'Lainnya'];

    Future<void> submit() async {
      // Guard sinkron: tap kedua tidak menunggu rebuild tombol.
      if (saving.value) return;
      saving.value = true;
      try {
        final text = category.text.trim();
        if (text.isEmpty) {
          await showError(context, const AppError('Isi kategori.'));
          return;
        }
        busy.value = true;
        final entry = CashTransaction(
            amount: int.tryParse(amount.text) ?? 0,
            type: type.value,
            category: text,
            contributorId: type.value == 'IN' ? contributor.value : null,
            date: isoDate(date.value),
            description: description.text.trim().isEmpty
                ? text
                : description.text.trim());
        try {
          final repo = ref.read(treasuryProvider).repository;
          try {
            await repo.addTransaction(entry);
          } on DuplicateTransaction {
            if (!context.mounted) return;
            final confirmed = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                        title: const Text('Transaksi serupa ditemukan'),
                        content: const Text(
                            'Pastikan pembayaran ini berbeda sebelum menyimpan.'),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('Batal')),
                          FilledButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text('Tetap simpan'))
                        ]));
            if (confirmed != true) return;
            await repo.addTransaction(entry, confirmDuplicate: true);
          }
          if (context.mounted) Navigator.pop(context);
        } catch (error) {
          if (context.mounted) await showError(context, error);
        }
      } finally {
        saving.value = false;
        busy.value = false;
      }
    }

    return Material(
      color: scheme.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SafeArea(
          top: false,
          child: Column(children: [
            const SizedBox(height: 10),
            Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                    color: scheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2))),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 12, 0),
              child: Row(children: [
                Expanded(
                    child: Text('Catat transaksi',
                        style: theme.textTheme.titleLarge)),
                IconButton(
                    tooltip: 'Tutup',
                    onPressed: busy.value ? null : () => Navigator.pop(context),
                    icon: const Icon(Icons.close)),
              ]),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SegmentedButton<String>(
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment(
                              value: 'IN',
                              label: Text('Masuk'),
                              icon: Icon(Icons.south_west, size: 18)),
                          ButtonSegment(
                              value: 'OUT',
                              label: Text('Keluar'),
                              icon: Icon(Icons.north_east, size: 18)),
                        ],
                        selected: {type.value},
                        onSelectionChanged: (value) {
                          type.value = value.first;
                          if (type.value == 'OUT') contributor.value = null;
                        },
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 4),
                        decoration: BoxDecoration(
                            color: scheme.surfaceContainerHighest
                                .withOpacity(0.55),
                            borderRadius: BorderRadius.circular(18)),
                        child: TextField(
                          key: const Key('amount_input'),
                          controller: amount,
                          autofocus: true,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly
                          ],
                          style: theme.textTheme.headlineMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                          decoration: const InputDecoration(
                              labelText: 'Nominal',
                              prefixText: 'Rp ',
                              filled: false,
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        for (final value in [5000, 10000, 20000, 50000])
                          ActionChip(
                              label: Text('+${rupiah(value)}'),
                              onPressed: () {
                                final current = int.tryParse(amount.text) ?? 0;
                                amount.text = '${current + value}';
                              }),
                      ]),
                      if (type.value == 'IN') ...[
                        const SizedBox(height: 20),
                        Text('Penyetor', style: theme.textTheme.labelLarge),
                        const SizedBox(height: 8),
                        Wrap(spacing: 8, runSpacing: 8, children: [
                          ChoiceChip(
                              label: const Text('Umum'),
                              selected: contributor.value == null,
                              onSelected: (_) => contributor.value = null),
                          for (final member in (members.data ?? <Member>[])
                              .where((m) => m.role == Role.siswa && m.active))
                            ChoiceChip(
                                key: Key('contributor_${member.id}'),
                                label: Text(member.name),
                                selected: contributor.value == member.id,
                                onSelected: (_) => contributor.value =
                                    contributor.value == member.id
                                        ? null
                                        : member.id),
                        ]),
                      ],
                      const SizedBox(height: 20),
                      TextField(
                        key: const Key('category_input'),
                        controller: category,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                            labelText: 'Kategori', hintText: 'Contoh: Kas'),
                      ),
                      const SizedBox(height: 10),
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        for (final value in categories)
                          ActionChip(
                              label: Text(value),
                              onPressed: () => category.text = value),
                      ]),
                      const SizedBox(height: 20),
                      InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () async {
                          final picked = await showDatePicker(
                              context: context,
                              initialDate: date.value,
                              firstDate: DateTime(2000),
                              lastDate: DateTime(2100));
                          if (picked != null) date.value = picked;
                        },
                        child: InputDecorator(
                          decoration: const InputDecoration(
                              labelText: 'Tanggal',
                              suffixIcon: Icon(Icons.calendar_today_outlined,
                                  size: 18)),
                          child: Text(dateLabel(isoDate(date.value))),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        key: const Key('description_input'),
                        controller: description,
                        textCapitalization: TextCapitalization.sentences,
                        maxLines: 2,
                        minLines: 1,
                        decoration: const InputDecoration(
                            labelText: 'Keterangan (opsional)',
                            hintText: 'Contoh: Iuran pekan pertama'),
                      ),
                    ]),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: FilledButton(
                  key: const Key('submit_tx_btn'),
                  onPressed: busy.value ? null : submit,
                  child: Text(busy.value ? 'Menyimpan…' : 'Simpan transaksi')),
            ),
          ]),
        ),
      ),
    );
  }
}
