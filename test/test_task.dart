import 'package:m3u/m3u.dart';
import 'package:test/test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'dart:io' show File, Directory;
import 'package:iptv_check_manager/iptv_check_manager.dart';

final List<Uri> links = [
  Uri.parse("https://iptv-org.github.io/iptv/countries/hk.m3u"),
];
String rootDirectory = "${Directory.current.path}/test";
final String downloadDirectory = "$rootDirectory/temp";
void main() {
  print('$rootDirectory');
  final client = MockClient.streaming((request, bodyStream) {
    if (request.url == links[0]) {
      return streamFile("hk.m3u");
    }
    throw UnimplementedError();
  });

  group("check iptv", () async {
    late CheckTask task;
    final dataFile = File("$downloadDirectory/example/data/cn.m3u");
    final content = await dataFile.readAsString();
    final entryList = await M3uParser.parse(content);
    final file = File("$downloadDirectory/hk.m3u");

    setUp(() async {
      task = await CheckTask.check(entryList,
          //file: file,
          client: client);
    });

    tearDown(() async {
      deleteFile(file);
    });

    test("Downloaded", () async {
      final first = await task.events.listen((event) {
        switch (event.state) {
          case TaskState.success:
            expect(78, equals(event.totalChannel));
            break;
        }
      });
      // first.currentChannel
      // expect(first.state, equals(TaskState.success));

      // expect(file.existsSync(), equals(true));
    });
  });
}

Future<void> deleteFile(File file) async {
  if (await file.exists()) {
    await file.delete();
  }
}

Future<http.StreamedResponse> streamFile(String filename) {
  final file = File("$downloadDirectory/$filename");
  final stream = file.openRead();
  final response = http.StreamedResponse(stream, 200);
  return Future.value(response);
}
