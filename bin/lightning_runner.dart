import 'package:lightning_runner/lightning/lightning_runner.dart';

Future<void> main (List<String> arguments) async {
  final lightning = LightningRunner(
    watchDependencies: arguments.contains('--watch-dependencies'),
    debounceInterval: Duration(seconds: 1)
  );

  await lightning.watch();
}