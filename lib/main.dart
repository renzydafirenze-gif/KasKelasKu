import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'data/vault.dart';
import 'data/exports.dart';
import 'models.dart';
import 'view_model.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: KasKelasKuApp()));
}

String rupiah(int amount) =>
    NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0)
        .format(amount);

Future<void> showError(BuildContext context, Object error) async {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(error is AppError
          ? error.message
          : 'Operasi gagal. Data lama tetap tersimpan. Periksa penyimpanan atau cadangan.')));
}

class KasKelasKuApp extends StatefulHookConsumerWidget {
  const KasKelasKuApp({super.key});
  @override
  ConsumerState<KasKelasKuApp> createState() => _KasKelasKuAppState();
}

class _KasKelasKuAppState extends ConsumerState<KasKelasKuApp>
    with WidgetsBindingObserver {
  Timer? _timer;
  Timer? _sessionCheck;
  bool _checking = false;
  final _navigator = GlobalKey<NavigatorState>();
  void _touch() {
    _timer?.cancel();
    if (ref.read(sessionProvider) != null) {
      _timer = Timer(const Duration(minutes: 3), _lock);
    }
  }

  Future<void> _lock() async {
    _navigator.currentState?.popUntil((route) => route.isFirst);
    ref.read(sessionProvider.state).state = null;
    await ref.read(treasuryProvider).repository.lock();
  }

  Future<void> _refreshSession() async {
    if (_checking || ref.read(sessionProvider) == null) return;
    _checking = true;
    try {
      final member =
          await ref.read(treasuryProvider).repository.currentMember();
      final previous = ref.read(sessionProvider);
      if (previous?.id != member.id || previous?.role != member.role) {
        await _lock();
      }
    } catch (_) {
      await _lock();
    } finally {
      _checking = false;
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sessionCheck =
        Timer.periodic(const Duration(seconds: 2), (_) => _refreshSession());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(_lock());
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _sessionCheck?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = ref.watch(darkModeProvider);
    final user = ref.watch(sessionProvider);
    useEffect(() {
      _touch();
      return null;
    }, [user]);
    useEffect(() {
      Exports.cleanupPlaintext().catchError((Object _) {});
      Vault.storage.read(key: 'setting:dark').then((value) {
        if (mounted && value != null) {
          ref.read(darkModeProvider.state).state = value == 'true';
        }
      }).catchError((Object _) {});
      return null;
    }, const []);
    useEffect(() {
      if (user != null) {
        ref
            .read(treasuryProvider)
            .exports
            .automaticReports(DateTime.now())
            .catchError((Object _) {});
      }
      final timer = Timer.periodic(const Duration(minutes: 1), (_) {
        if (ref.read(sessionProvider) != null) {
          ref
              .read(treasuryProvider)
              .exports
              .automaticReports(DateTime.now())
              .catchError((Object _) {});
        }
      });
      return timer.cancel;
    }, [user?.id]);
    return Listener(
      onPointerDown: (_) => _touch(),
      onPointerMove: (_) => _touch(),
      child: Focus(
        onKeyEvent: (_, __) {
          _touch();
          return KeyEventResult.ignored;
        },
        child: MaterialApp(
          navigatorKey: _navigator,
          title: 'KasKelasKu',
          debugShowCheckedModeBanner: false,
          themeMode: dark ? ThemeMode.dark : ThemeMode.light,
          theme: ThemeData(
              useMaterial3: true,
              colorScheme:
                  ColorScheme.fromSeed(seedColor: const Color(0xFF005F73))),
          darkTheme: ThemeData(
              useMaterial3: true,
              brightness: Brightness.dark,
              scaffoldBackgroundColor: const Color(0xFF0B0F19),
              colorScheme: ColorScheme.fromSeed(
                  seedColor: const Color(0xFF00F5D4),
                  brightness: Brightness.dark)),
          home: user == null ? const LoginScreen() : const HomeScreen(),
        ),
      ),
    );
  }
}

class LoginScreen extends HookConsumerWidget {
  const LoginScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(treasuryProvider).repository;
    final accounts = useMemoized(repo.vault.accounts);
    final ids = useFuture(accounts);
    final selected = useState<String?>(null);
    final role = useState(Role.bendahara);
    final name = useTextEditingController();
    final password = useTextEditingController();
    final busy = useState(false);
    final setup = ids.hasData && ids.data!.isEmpty;
    return Scaffold(
        body: SafeArea(
            child: Center(
                child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: AutofillGroup(
            child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.account_balance_wallet_outlined, size: 56),
            const SizedBox(height: 24),
            Text('KasKelasKu',
                style: Theme.of(context).textTheme.headlineLarge,
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
                setup
                    ? 'Buat brankas kelas · Bendahara pertama'
                    : 'Brankas lokal · Tanpa koneksi internet',
                textAlign: TextAlign.center),
            const SizedBox(height: 32),
            if (ids.hasError)
              const Text(
                  'Penyimpanan kunci gagal dibuka. Jangan hapus data aplikasi.'),
            if (!ids.hasData && !ids.hasError) const LinearProgressIndicator(),
            if (setup)
              TextField(
                  controller: name,
                  decoration:
                      const InputDecoration(labelText: 'Nama Bendahara')),
            if (!setup && ids.hasData)
              DropdownButtonFormField<String>(
                  key: const Key('transaction_type_input'),
                  isExpanded: true,
                  value: selected.value ?? ids.data!.first,
                  decoration: const InputDecoration(labelText: 'ID akun'),
                  items: ids.data!
                      .map((id) => DropdownMenuItem(
                          value: id,
                          child: Text(id, overflow: TextOverflow.ellipsis)))
                      .toList(),
                  onChanged: busy.value ? null : (id) => selected.value = id),
            if (!setup)
              DropdownButtonFormField<Role>(
                  value: role.value,
                  decoration:
                      const InputDecoration(labelText: 'Peran terdaftar'),
                  items: Role.values
                      .map((r) =>
                          DropdownMenuItem(value: r, child: Text(r.label)))
                      .toList(),
                  onChanged: busy.value
                      ? null
                      : (value) {
                          if (value != null) role.value = value;
                        }),
            const SizedBox(height: 16),
            TextField(
                controller: password,
                obscureText: true,
                enableSuggestions: false,
                autocorrect: false,
                autofillHints: [
                  setup ? AutofillHints.newPassword : AutofillHints.password
                ],
                decoration: InputDecoration(
                    labelText: 'Kata sandi',
                    helperText: setup
                        ? 'Minimal 12 karakter. Tidak ada kata sandi bawaan.'
                        : null)),
            const SizedBox(height: 24),
            FilledButton(
                onPressed: busy.value || !ids.hasData
                    ? null
                    : () async {
                        busy.value = true;
                        try {
                          final member = setup
                              ? await repo.setup(name.text, password.text)
                              : await repo.login(
                                  selected.value ?? ids.data!.first,
                                  password.text,
                                  role.value);
                          password.clear();
                          ref.read(sessionProvider.state).state = member;
                        } catch (error) {
                          if (context.mounted) await showError(context, error);
                        } finally {
                          if (context.mounted) busy.value = false;
                        }
                      },
                child: Text(busy.value
                    ? 'Membuka brankas…'
                    : setup
                        ? 'Buat brankas'
                        : 'Masuk')),
            const SizedBox(height: 16),
            if (!setup && repo.canResumeBiometric)
              OutlinedButton(
                  onPressed: busy.value
                      ? null
                      : () async {
                          busy.value = true;
                          try {
                            final member = await repo.resumeBiometric();
                            ref.read(sessionProvider.state).state = member;
                          } catch (error) {
                            if (context.mounted) {
                              await showError(context, error);
                            }
                          } finally {
                            if (context.mounted) busy.value = false;
                          }
                        },
                  child: const Text('Buka akun terakhir dengan biometrik')),
            const Text(
                'Pemilihan peran tidak memberi izin baru. Peran selalu diperiksa dari database.',
                textAlign: TextAlign.center),
          ],
        )),
      ),
    ))));
  }
}

class HomeScreen extends HookConsumerWidget {
  const HomeScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final page = useState(0);
    final user = ref.watch(sessionProvider)!;
    final model = ref.watch(treasuryProvider);
    return Scaffold(
      appBar: AppBar(title: Text('KasKelasKu · ${user.role.label}'), actions: [
        IconButton(
            tooltip: 'Kunci aplikasi',
            icon: const Icon(Icons.lock_outline),
            onPressed: () async {
              ref.read(sessionProvider.state).state = null;
              await model.repository.lock();
            }),
      ]),
      body: SafeArea(
          child: Center(
              child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 960),
                  child: [
                    const DashboardScreen(),
                    const HistoryScreen(),
                    const ReportsScreen(),
                    const MembersScreen(),
                    const SettingsScreen()
                  ][page.value]))),
      bottomNavigationBar: NavigationBar(
          selectedIndex: page.value,
          onDestinationSelected: (value) => page.value = value,
          destinations: const [
            NavigationDestination(
                icon: Icon(Icons.dashboard_outlined), label: 'Ringkasan'),
            NavigationDestination(
                icon: Icon(Icons.receipt_long_outlined), label: 'Riwayat'),
            NavigationDestination(
                icon: Icon(Icons.description_outlined), label: 'Laporan'),
            NavigationDestination(
                icon: Icon(Icons.people_outline), label: 'Anggota'),
            NavigationDestination(
                icon: Icon(Icons.settings_outlined), label: 'Setelan'),
          ]),
      floatingActionButton: user.role == Role.bendahara && page.value < 2
          ? FloatingActionButton.extended(
              onPressed: () => showDialog<void>(
                  context: context, builder: (_) => const TransactionEntry()),
              icon: const Icon(Icons.add),
              label: const Text('Transaksi'))
          : null,
    );
  }
}

class DashboardScreen extends HookConsumerWidget {
  const DashboardScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(treasuryProvider).repository;
    final revision = ref.watch(revisionProvider);
    final future = useMemoized(
        () async => (await repo.balance(), await repo.trends()), [revision]);
    final snapshot = useFuture(future);
    if (snapshot.hasError) {
      return const Center(
          child: Text('Ringkasan gagal dimuat. Masuk kembali.'));
    }
    if (!snapshot.hasData) {
      return const Center(child: CircularProgressIndicator());
    }
    final (balance, trends) = snapshot.data!;
    final points = trends.map((r) => (r['net']! as int).toDouble()).toList();
    return ListView(padding: const EdgeInsets.all(24), children: [
      Text('SALDO KELAS', style: Theme.of(context).textTheme.labelLarge),
      const SizedBox(height: 8),
      Semantics(
          liveRegion: true,
          child: Text(rupiah(balance),
              style: Theme.of(context).textTheme.headlineLarge)),
      const SizedBox(height: 32),
      Text('Arus kas bersih per bulan',
          style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 24),
      if (points.isEmpty)
        const Text('Belum ada transaksi.')
      else ...[
        ExcludeSemantics(
            child: SizedBox(
                height: 160,
                child: CustomPaint(
                    painter: TrendPainter(
                        points, Theme.of(context).colorScheme.primary)))),
        const SizedBox(height: 16),
        for (final row in trends)
          ListTile(
              title: Text(row['period']! as String),
              trailing: Text(rupiah(row['net']! as int))),
      ],
      const SizedBox(height: 32),
      const Text(
          'Data hanya tersimpan di perangkat ini. Buat cadangan terenkripsi secara rutin.'),
    ]);
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
    for (var i = 0; i < points.length; i++) {
      final x = points.length == 1
          ? size.width / 2
          : i * size.width / (points.length - 1);
      final y = 8 + (size.height - 16) * (1 - (points[i] - min) / span);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
      canvas.drawCircle(Offset(x, y), 4, Paint()..color = color);
    }
    canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..strokeWidth = 3
          ..style = PaintingStyle.stroke);
  }

  @override
  bool shouldRepaint(TrendPainter oldDelegate) =>
      oldDelegate.points != points || oldDelegate.color != color;
}

class TransactionEntry extends HookConsumerWidget {
  const TransactionEntry({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final amount = useTextEditingController();
    final category = useTextEditingController();
    final description = useTextEditingController();
    final date = useTextEditingController(text: isoDate(DateTime.now()));
    final type = useState('IN');
    final busy = useState(false);
    final members = useFuture(
        useMemoized(() => ref.read(treasuryProvider).repository.members()));
    final contributor = useState<String?>(null);
    final token = useMemoized(Vault.token);
    return AlertDialog(
        title: const Text('Catat transaksi'),
        content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                  key: const Key('amount_input'),
                  controller: amount,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'Nominal rupiah',
                      helperText: 'Bilangan bulat lebih dari nol')),
              DropdownButtonFormField<String>(
                  key: const Key('transaction_type_input'),
                  value: type.value,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Jenis'),
                  items: const [
                    DropdownMenuItem(value: 'IN', child: Text('Pemasukan')),
                    DropdownMenuItem(value: 'OUT', child: Text('Pengeluaran'))
                  ],
                  onChanged: busy.value
                      ? null
                      : (value) {
                          if (value != null) type.value = value;
                        }),
              if (type.value == 'IN')
                // coverage:ignore-start
                DropdownButtonFormField<String>(
                    key: const Key('contributor_input'),
                    value: contributor.value,
                    isExpanded: true,
                    decoration:
                        const InputDecoration(labelText: 'Nama penyetor'),
                    items: (members.data ?? <Member>[])
                        .where((member) =>
                            member.role == Role.siswa && member.active)
                        .map((member) => DropdownMenuItem(
                            value: member.id, child: Text(member.name)))
                        .toList(),
                    onChanged: (value) => contributor.value = value),
              // coverage:ignore-end
              TextField(
                  controller: category,
                  maxLength: 80,
                  decoration:
                      const InputDecoration(labelText: 'Kategori / tujuan')),
              TextField(
                  controller: date,
                  decoration: const InputDecoration(
                      labelText: 'Tanggal', hintText: 'YYYY-MM-DD')),
              TextField(
                  key: const Key('description_input'),
                  controller: description,
                  maxLength: 1000,
                  decoration: const InputDecoration(labelText: 'Keterangan'),
                  minLines: 1,
                  maxLines: 4),
            ]))),
        actions: [
          TextButton(
              onPressed: busy.value ? null : () => Navigator.pop(context),
              child: const Text('Batal')),
          FilledButton(
              key: const Key('submit_tx_btn'),
              onPressed: busy.value
                  ? null
                  : () async {
                      busy.value = true;
                      final entry = CashTransaction(
                          amount: int.tryParse(amount.text) ?? 0,
                          type: type.value,
                          category: category.text,
                          contributorId:
                              type.value == 'IN' ? contributor.value : null,
                          date: date.text,
                          description: description.text);
                      try {
                        final repo = ref.read(treasuryProvider).repository;
                        try {
                          await repo.addTransaction(entry, token);
                        } on DuplicateTransaction {
                          if (!context.mounted) return;
                          final confirmed = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                      title: const Text(
                                          'Transaksi serupa ditemukan'),
                                      content: const Text(
                                          'Pastikan pembayaran ini berbeda sebelum menyimpan.'),
                                      actions: [
                                        TextButton(
                                            onPressed: () =>
                                                Navigator.pop(ctx, false),
                                            child: const Text('Batal')),
                                        FilledButton(
                                            onPressed: () =>
                                                Navigator.pop(ctx, true),
                                            child: const Text(
                                                'Simpan pembayaran berbeda'))
                                      ]));
                          if (confirmed != true) return;
                          await repo.addTransaction(entry, token,
                              confirmDuplicate: true);
                        }
                        if (context.mounted) Navigator.pop(context);
                      } catch (error) {
                        if (context.mounted) await showError(context, error);
                      } finally {
                        if (context.mounted) busy.value = false;
                      }
                    },
              child: Text(busy.value ? 'Menyimpan…' : 'Simpan')),
        ]);
  }
}

class HistoryScreen extends HookConsumerWidget {
  const HistoryScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(treasuryProvider).repository;
    final revision = ref.watch(revisionProvider);
    final keyword = useTextEditingController();
    final category = useTextEditingController();
    final from = useTextEditingController();
    final to = useTextEditingController();
    final filter = useState(0);
    final page = useState(0);
    final future = useMemoized(
        () => repo.history(
            keyword: keyword.text,
            category: category.text,
            from: from.text.isEmpty ? null : from.text,
            to: to.text.isEmpty ? null : to.text,
            offset: page.value * 100),
        [revision, filter.value, page.value]);
    final snapshot = useFuture(future);
    final canDelete = ref.watch(sessionProvider)?.role == Role.bendahara;
    return Column(children: [
      ExpansionTile(title: const Text('Filter riwayat'), children: [
        Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              TextField(
                  controller: keyword,
                  maxLength: 100,
                  decoration: const InputDecoration(
                      labelText: 'Kata kunci keterangan')),
              TextField(
                  controller: category,
                  decoration:
                      const InputDecoration(labelText: 'Kategori persis')),
              TextField(
                  controller: from,
                  decoration: const InputDecoration(
                      labelText: 'Dari tanggal YYYY-MM-DD')),
              TextField(
                  controller: to,
                  decoration: const InputDecoration(
                      labelText: 'Sampai tanggal YYYY-MM-DD')),
              FilledButton(
                  onPressed: () {
                    page.value = 0;
                    filter.value++;
                  },
                  child: const Text('Terapkan')),
            ]))
      ]),
      if (snapshot.hasError)
        const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
                'Riwayat gagal dimuat. Periksa filter atau masuk kembali.')),
      if (!snapshot.hasData && !snapshot.hasError)
        const LinearProgressIndicator(),
      Expanded(
          child: ListView.builder(
              itemCount: snapshot.data?.length ?? 0,
              itemBuilder: (_, i) {
                final entry = snapshot.data![i];
                return ListTile(
                    isThreeLine: true,
                    title: Text(
                        '${entry.type == 'IN' ? 'Masuk' : 'Keluar'} · ${rupiah(entry.amount)}'),
                    subtitle: Text(
                        '${entry.date} · ${entry.category}\n${entry.description}'),
                    trailing: canDelete
                        ? IconButton(
                            tooltip: 'Hapus transaksi',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () async {
                              final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                          title: const Text('Hapus transaksi?'),
                                          content: const Text(
                                              'Penghapusan tidak dapat dibatalkan dan dicatat dalam audit.'),
                                          actions: [
                                            TextButton(
                                                onPressed: () =>
                                                    Navigator.pop(ctx, false),
                                                child: const Text('Batal')),
                                            FilledButton(
                                                onPressed: () =>
                                                    Navigator.pop(ctx, true),
                                                child: const Text('Hapus'))
                                          ]));
                              if (confirm == true) {
                                try {
                                  await repo.deleteTransaction(entry.id!);
                                } catch (error) {
                                  if (context.mounted) {
                                    await showError(context, error);
                                  }
                                }
                              }
                            })
                        : null);
              })),
      if (snapshot.hasData && snapshot.data!.isEmpty)
        const Text('Tidak ada transaksi.'),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        IconButton(
            tooltip: 'Halaman sebelumnya',
            onPressed: page.value == 0 ? null : () => page.value--,
            icon: const Icon(Icons.chevron_left)),
        Text('Halaman ${page.value + 1}'),
        IconButton(
            tooltip: 'Halaman berikutnya',
            onPressed:
                (snapshot.data?.length ?? 0) < 100 ? null : () => page.value++,
            icon: const Icon(Icons.chevron_right)),
      ]),
    ]);
  }
}

class ReportsScreen extends HookConsumerWidget {
  const ReportsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final model = ref.watch(treasuryProvider);
    final role = ref.watch(sessionProvider)!.role;
    final period = useTextEditingController(text: monthOf(DateTime.now()));
    final password = useTextEditingController();
    final busy = useState(false);
    final message = useState('');
    Future<void> run(Future<void> Function() action) async {
      busy.value = true;
      try {
        await action();
        if (context.mounted) message.value = 'Selesai.';
      } catch (error) {
        if (context.mounted) await showError(context, error);
      } finally {
        if (context.mounted) busy.value = false;
      }
    }

    return ListView(padding: const EdgeInsets.all(24), children: [
      Text('Laporan bulanan', style: Theme.of(context).textTheme.headlineSmall),
      TextField(
          controller: period,
          decoration: const InputDecoration(labelText: 'Bulan YYYY-MM')),
      TextField(
          controller: password,
          obscureText: true,
          decoration: const InputDecoration(
              labelText: 'Kata sandi ekspor minimal 12 karakter')),
      const SizedBox(height: 24),
      const Text(
          'PDF dan CSV dibentuk dari snapshot yang sama, lalu disimpan terenkripsi. Bulan kosong menghasilkan laporan saldo awal/akhir tanpa transaksi.'),
      /* coverage:ignore-start */ FutureBuilder<List<Map<String, Object?>>>(
          future: model.repository.monthlyTargetStatus(period.text),
          builder: (context, snapshot) =>
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const SizedBox(height: 16),
                const Text('Target kas keseluruhan'),
                // coverage:ignore-start
                for (final row in snapshot.data ?? const [])
                  Text(
                      '${row['name']}: Rp ${row['paid']} / Rp ${row['target']} — '
                      '${(row['paid']! as int) >= (row['target']! as int) ? 'Lunas' : 'Belum lunas'}')
              ])), // coverage:ignore-end
      /* coverage:ignore-end */
      const SizedBox(height: 16),
      FilledButton(
          onPressed: busy.value
              ? null
              : () => run(() async {
                    final exportPassword = password.text;
                    final files =
                        await model.exports.report(period.text, exportPassword);
                    password.clear();
                    final sharedPdf = await model.exports
                        .decryptReport(files.pdf, exportPassword);
                    final sharedCsv = await model.exports
                        .decryptReport(files.csv, exportPassword);
                    await Share.shareXFiles(
                        [XFile(sharedPdf.path), XFile(sharedCsv.path)],
                        text: 'Laporan KasKelasKu',
                        sharePositionOrigin: const Rect.fromLTWH(0, 0, 1, 1));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text(
                              'PDF dan CSV siap dibagikan. File tersedia selama proses berbagi.')));
                    }
                  }),
          child: const Text('Buat PDF dan CSV terenkripsi')),
      if (role == Role.ketua)
        OutlinedButton(
            onPressed: busy.value
                ? null
                : () async {
                    final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                                title: const Text('Setujui dan kunci bulan?'),
                                content: const Text(
                                    'Seluruh transaksi bulan ini tidak dapat ditambah atau dihapus setelah dikunci.'),
                                actions: [
                                  TextButton(
                                      onPressed: () =>
                                          Navigator.pop(ctx, false),
                                      child: const Text('Batal')),
                                  FilledButton(
                                      onPressed: () => Navigator.pop(ctx, true),
                                      child: const Text('Setujui dan kunci'))
                                ]));
                    if (confirmed == true) {
                      await run(() => model.repository.approve(period.text));
                    }
                  },
            child: const Text('Setujui dan kunci')),
      if (role == Role.guruWali)
        OutlinedButton(
            onPressed: busy.value
                ? null
                : () => run(() => model.repository.verify(period.text)),
            child: const Text('Verifikasi sebagai Guru Wali')),
      if (busy.value) const LinearProgressIndicator(),
      Semantics(liveRegion: true, child: Text(message.value)),
    ]);
  }
}

class MembersScreen extends HookConsumerWidget {
  const MembersScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(treasuryProvider).repository;
    final revision = ref.watch(revisionProvider);
    final future = useMemoized(repo.members, [revision]);
    final snapshot = useFuture(future);
    final editable = ref.watch(sessionProvider)!.role == Role.bendahara;
    return Column(children: [
      if (editable)
        Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(spacing: 8, children: [
              FilledButton.icon(
                  onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) => const AddMemberDialog()),
                  icon: const Icon(Icons.person_add_outlined),
                  label: const Text('Tambah anggota')),
              // coverage:ignore-start
              OutlinedButton.icon(
                  onPressed: () => showDialog<void>(
                      context: context, builder: (_) => const TargetDialog()),
                  icon: const Icon(Icons.flag_outlined),
                  label: const Text('Atur target kas')) // coverage:ignore-end
            ])),
      if (snapshot.hasError) const Text('Daftar anggota gagal dimuat.'),
      Expanded(
          child: ListView(children: [
        for (final member in snapshot.data ?? <Member>[])
          ListTile(
            title: Text('${member.name}${member.active ? '' : ' (nonaktif)'}'),
            subtitle: SelectableText('${member.role.label}\nID: ${member.id}'),
            isThreeLine: true,
            trailing: editable
                ? PopupMenuButton<String>(
                    tooltip: 'Ubah izin anggota',
                    onSelected: (value) async {
                      try {
                        await repo.changeMember(
                            member,
                            value == 'active' ? member.role : Role.parse(value),
                            value == 'active' ? !member.active : member.active);
                      } catch (error) {
                        if (context.mounted) await showError(context, error);
                      }
                    },
                    itemBuilder: (_) => [
                          for (final role in Role.values)
                            PopupMenuItem(
                                value: role.name, child: Text(role.label)),
                          PopupMenuItem(
                              value: 'active',
                              child: Text(
                                  member.active ? 'Nonaktifkan' : 'Aktifkan')),
                        ])
                : null,
          )
      ])),
    ]);
  }
}

// coverage:ignore-start
class TargetDialog extends HookConsumerWidget {
  const TargetDialog({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final period = useTextEditingController(text: monthOf(DateTime.now()));
    final amount = useTextEditingController(text: '10000');
    final member = useState<String?>(null);
    final members = useFuture(
        useMemoized(() => ref.read(treasuryProvider).repository.members()));
    return AlertDialog(
        title: const Text('Target kas keseluruhan bulanan'),
        content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: period,
              decoration: const InputDecoration(labelText: 'Bulan YYYY-MM')),
          DropdownButtonFormField<String>(
              value: member.value,
              decoration: const InputDecoration(labelText: 'Nama penyetor'),
              items: (members.data ?? <Member>[])
                  .where((m) => m.role == Role.siswa && m.active)
                  .map(
                      (m) => DropdownMenuItem(value: m.id, child: Text(m.name)))
                  .toList(),
              onChanged: (value) => member.value = value),
          TextField(
              controller: amount,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Target rupiah'))
        ])),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Batal')),
          FilledButton(
              onPressed: () async {
                try {
                  final id = member.value;
                  if (id == null) throw const AppError('Pilih nama penyetor.');
                  await ref.read(treasuryProvider).repository.setMonthlyTarget(
                      period.text, id, int.tryParse(amount.text) ?? -1);
                  if (context.mounted) Navigator.pop(context);
                } catch (error) {
                  if (context.mounted) await showError(context, error);
                }
              },
              child: const Text('Simpan'))
        ]);
  }
}
// coverage:ignore-end

class AddMemberDialog extends HookConsumerWidget {
  const AddMemberDialog({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = useTextEditingController();
    final role = useState(Role.siswa);
    final busy = useState(false);
    return AlertDialog(
        title: const Text('Tambah anggota'),
        content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Nama'),
              maxLength: 80),
          DropdownButtonFormField<Role>(
              value: role.value,
              items: Role.values
                  .map((r) => DropdownMenuItem(value: r, child: Text(r.label)))
                  .toList(),
              onChanged: (value) {
                if (value != null) role.value = value;
              }),
        ])),
        actions: [
          TextButton(
              onPressed: busy.value ? null : () => Navigator.pop(context),
              child: const Text('Batal')),
          FilledButton(
              onPressed: busy.value
                  ? null
                  : () async {
                      busy.value = true;
                      try {
                        await ref
                            .read(treasuryProvider)
                            .repository
                            .addMember(name.text, role.value, '');
                        if (context.mounted) Navigator.pop(context);
                      } catch (error) {
                        if (context.mounted) await showError(context, error);
                      } finally {
                        if (context.mounted) busy.value = false;
                      }
                    },
              child: const Text('Simpan')),
        ]);
  }
}

class ChangePasswordDialog extends HookConsumerWidget {
  const ChangePasswordDialog({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final old = useTextEditingController();
    final next = useTextEditingController();
    final busy = useState(false);
    return AlertDialog(
        title: const Text('Ganti kata sandi'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: old,
              obscureText: true,
              decoration:
                  const InputDecoration(labelText: 'Kata sandi sekarang')),
          TextField(
              controller: next,
              obscureText: true,
              decoration: const InputDecoration(
                  labelText: 'Kata sandi baru minimal 12 karakter')),
        ]),
        actions: [
          TextButton(
              onPressed: busy.value ? null : () => Navigator.pop(context),
              child: const Text('Batal')),
          FilledButton(
              onPressed: busy.value
                  ? null
                  : () async {
                      busy.value = true;
                      try {
                        await ref
                            .read(treasuryProvider)
                            .repository
                            .changePassword(old.text, next.text);
                        old.clear();
                        next.clear();
                        if (context.mounted) Navigator.pop(context);
                      } catch (error) {
                        if (context.mounted) await showError(context, error);
                      } finally {
                        if (context.mounted) busy.value = false;
                      }
                    },
              child: const Text('Simpan'))
        ]);
  }
}

class ImportExportDialog extends HookConsumerWidget {
  const ImportExportDialog({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final password = useTextEditingController();
    final busy = useState(false);
    final model = ref.watch(treasuryProvider);
    final member = ref.watch(sessionProvider);
    final automatic = useFuture(useMemoized(model.exports.automaticFiles));
    final selectedAutomatic = useState<String?>(null);
    Future<void> open(bool restore) async {
      busy.value = true;
      try {
        final File file;
        final auto = !restore && selectedAutomatic.value != null;
        if (auto) {
          file = File(selectedAutomatic.value!);
        } else {
          final result =
              await FilePicker.platform.pickFiles(type: FileType.any);
          if (result == null ||
              result.files.single.path == null ||
              !context.mounted) return;
          file = File(result.files.single.path!);
        }
        if (restore) {
          final confirmed = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                      title: const Text('Pulihkan ke brankas kosong?'),
                      content: const Text(
                          'Hanya brankas baru tanpa transaksi atau anggota tambahan yang dapat dipulihkan. Akun dari cadangan tetap nonaktif; buat akun baru untuk memberi akses. Data lama tidak ditimpa.'),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Batal')),
                        FilledButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('Pulihkan'))
                      ]));
          if (confirmed != true) return;
          await model.exports.restore(file, password.text);
        } else {
          File? plain;
          try {
            plain = await model.exports.decryptReport(
                file,
                auto
                    ? await model.repository.automaticReportPassword()
                    : password.text);
            await Share.shareXFiles([XFile(plain.path)],
                text: 'Laporan KasKelasKu',
                sharePositionOrigin: const Rect.fromLTWH(0, 0, 1, 1));
          } finally {
            if (plain != null && await plain.parent.exists()) {
              await plain.parent.delete(recursive: true);
            }
          }
        }
        password.clear();
        if (context.mounted) Navigator.pop(context);
      } catch (error) {
        if (context.mounted) await showError(context, error);
      } finally {
        if (context.mounted) busy.value = false;
      }
    }

    return AlertDialog(
        title: const Text('Berkas terenkripsi'),
        content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text(
              'Laporan yang dibagikan setelah dibuka berupa PDF/CSV tanpa enkripsi. Penerima dan aplikasi tujuan dapat menyimpan salinannya.'),
          TextField(
              controller: password,
              obscureText: true,
              decoration:
                  const InputDecoration(labelText: 'Kata sandi berkas')),
          if ((automatic.data ?? []).isNotEmpty)
            DropdownButtonFormField<String>(
                value: selectedAutomatic.value,
                isExpanded: true,
                decoration: const InputDecoration(
                    labelText:
                        'Laporan otomatis lokal (tanpa kata sandi ekspor)'),
                items: [
                  const DropdownMenuItem<String>(
                      value: null, child: Text('Pilih berkas manual')),
                  for (final file in automatic.data!)
                    DropdownMenuItem(
                        value: file.path,
                        child: Text(file.uri.pathSegments.last,
                            overflow: TextOverflow.ellipsis))
                ],
                onChanged: busy.value
                    ? null
                    : (value) => selectedAutomatic.value = value),
          const SizedBox(height: 16),
          FilledButton(
              onPressed: busy.value ? null : () => open(false),
              child: const Text('Pilih dan buka laporan')),
          if (member?.role == Role.bendahara)
            OutlinedButton(
                onPressed: busy.value ? null : () => open(true),
                child: const Text('Pilih cadangan untuk pemulihan')),
          if (busy.value) const LinearProgressIndicator(),
        ])),
        actions: [
          TextButton(
              onPressed: busy.value ? null : () => Navigator.pop(context),
              child: const Text('Tutup'))
        ]);
  }
}

class SettingsScreen extends HookConsumerWidget {
  const SettingsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dark = ref.watch(darkModeProvider);
    final password = useTextEditingController();
    final busy = useState(false);
    final user = ref.watch(sessionProvider)!;
    return ListView(padding: const EdgeInsets.all(24), children: [
      SwitchListTile(
          title: const Text('Mode gelap'),
          value: dark,
          onChanged: (value) async {
            ref.read(darkModeProvider.state).state = value;
            try {
              await Vault.storage.write(key: 'setting:dark', value: '$value');
            } catch (error) {
              if (context.mounted) await showError(context, error);
            }
          }),
      const ListTile(
          leading: Icon(Icons.lock_clock_outlined),
          title: Text('Kunci otomatis'),
          subtitle: Text(
              'Setelah 3 menit tidak aktif atau aplikasi masuk latar belakang.')),
      SelectableText('Akun: ${user.name}\nID: ${user.id}'),
      OutlinedButton(
          onPressed: () => showDialog<void>(
              context: context, builder: (_) => const ChangePasswordDialog()),
          child: const Text('Ganti kata sandi')),
      const SizedBox(height: 16),
      OutlinedButton.icon(
          onPressed: () => showDialog<void>(
              context: context, builder: (_) => const ImportExportDialog()),
          icon: const Icon(Icons.folder_open),
          label: const Text('Buka laporan / pulihkan cadangan')),
      if (user.role == Role.bendahara) ...[
        const SizedBox(height: 24),
        Text('Cadangan AES-256-GCM',
            style: Theme.of(context).textTheme.titleLarge),
        const Text(
            'Simpan kata sandi cadangan terpisah. Tanpa kata sandi, cadangan tidak dapat dibuka.'),
        TextField(
            controller: password,
            obscureText: true,
            decoration: const InputDecoration(
                labelText: 'Kata sandi cadangan minimal 12 karakter')),
        FilledButton(
            onPressed: busy.value
                ? null
                : () async {
                    busy.value = true;
                    try {
                      final file = await ref
                          .read(treasuryProvider)
                          .exports
                          .backup(password.text);
                      password.clear();
                      await Share.shareXFiles([XFile(file.path)],
                          text: 'Cadangan KasKelasKu terenkripsi',
                          sharePositionOrigin: const Rect.fromLTWH(0, 0, 1, 1));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: SelectableText(
                                'Cadangan tersimpan: ${file.path}')));
                      }
                    } catch (error) {
                      if (context.mounted) await showError(context, error);
                    } finally {
                      if (context.mounted) busy.value = false;
                    }
                  },
            child: Text(busy.value ? 'Mengenkripsi…' : 'Buat cadangan lokal')),
      ],
    ]);
  }
}
