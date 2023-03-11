import 'dart:convert';
import 'dart:io';

extension FileExtensions on File {
  Stream<String> readLineByLine() {
    if (!existsSync()) {
      return const Stream<String>.empty();
    }

    return openRead()
      .transform(utf8.decoder)
      .transform(const LineSplitter());
  }
}

extension UriExtensions on Uri {
  Stream<String> readLineByLine() {
    return File(toFilePath())
      .readLineByLine();
  }
}