import 'dart:io' show File, Directory;

import 'package:iptv_check_manager/iptv_check_manager.dart';
import 'package:m3u/m3u.dart';
import 'package:http/http.dart' as http;

void main() async {
  final tag = 'aq';
  // final tag = 'hk';
  // final tag = 'cn';
  // specify url and destionation
  final url =
      Uri.parse("https://github.com/iptv-org/iptv/blob/master/streams/cn.m3u");
  final projPath = "${Directory.current.path}/example";
  print('start $projPath');
  final file = File("$projPath/data/$tag.m3u");
  final content = await file.readAsString();
  final entryList = await M3uParser.parse(content);
  print("entryList ${entryList.length}");
  // initialize download request
  final task = await CheckTask.check(
    entryList,
    // file: File("$projPath/gendata/$tag.m3u")
  );

  task.events.listen((event) {
    print('start listen ${event}');
    switch (event.state) {
      case TaskState.error:
        print("error: ${event.error!}");
        break;
      case TaskState.success:
        final currentChannel = event.currentChannel;
        final totalChannel = event.totalChannel;
        final currentIndex = event.currentIndex;
        // print(
        // 'title = ${currentIndex}/${totalChannel} ${currentChannel!.title} is ok');
        break;
      case TaskState.paused:
        print("paused");
        break;
      case TaskState.canceled:
        print("canceled");
        break;
      case TaskState.checking:
        print("checking");
        break;
      case TaskState.resume:
        print("resume");
        break;
      case TaskState.errorStatusCode:
        final currentChannel = event.currentChannel;
        final totalChannel = event.totalChannel;
        final currentIndex = event.currentIndex;
        // print(
        //     'title = ${currentChannel!.title} ${currentIndex}/${totalChannel} is errorStatusCode');
        break;
      case TaskState.timeout:
        final currentChannel = event.currentChannel;
        final totalChannel = event.totalChannel;
        final currentIndex = event.currentIndex;
        // print(
        //     'title = ${currentChannel!.title} ${currentIndex}/${totalChannel} is timeout');
        break;
      case TaskState.done:
        print("all done");
        break;
    }
  });
}
