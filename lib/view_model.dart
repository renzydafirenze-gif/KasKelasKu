import 'dart:async';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'data/exports.dart';
import 'data/repository.dart';
import 'data/vault.dart';
import 'models.dart';

final treasuryProvider = Provider<TreasuryViewModel>((ref) {
  final model = TreasuryViewModel(TreasuryRepository(Vault()));
  ref.onDispose(model.dispose);
  return model;
});
final sessionProvider = StateProvider<Member?>((ref) => null);
final darkModeProvider = StateProvider<bool>((ref) => true);
final revisionProvider =
    StreamProvider<int>((ref) => ref.watch(treasuryProvider).revisions);

class TreasuryViewModel {
  TreasuryViewModel(this.repository) {
    _subscription = repository.changes.listen((_) {
      _revisions.add(++_revision);
    });
  }
  final TreasuryRepository repository;
  late final StreamSubscription<void> _subscription;
  final _revisions = StreamController<int>.broadcast();
  var _revision = 0;
  Stream<int> get revisions => _revisions.stream;
  late final Exports exports = Exports(repository);
  Future<void> dispose() async {
    await _subscription.cancel();
    await repository.lock(forgetBiometric: true);
    await _revisions.close();
  }
}
