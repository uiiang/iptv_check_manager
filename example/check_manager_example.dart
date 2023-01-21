import 'dart:io';
import 'package:iptv_check_manager/iptv_check_manager.dart';
import 'package:iptv_check_manager/src/iptv_check_manager.dart';
import 'package:m3u/m3u.dart';

final directory = "${Directory.current.path}";

void main() async {
  print('directory $directory');
  // final tag = 'aq';
  // final tag = 'hk';
  // final tag = 'cn';
  final tags = ['aq', 'hk', 'cn'];
  final projPath = "$directory/example";
  print('start $projPath');
  // Initialize
  final manager = CheckManager.instance;
  // Here we create `n` amount of long running isolates available for downloader
  await manager.init(isolates: 2, directory: directory);
  await Future.delayed(const Duration(seconds: 1));

  void dispose() async {
    // Clean-up isolates
    manager.dispose().then((_) => exit(0));

    // Optionally delete file
    /*final path = request.path;
    if (!request.isCancelled && path != null) {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    }*/
  }

  tags.forEach((tag) async {
    final file = File("$projPath/data/$tag.m3u");
    final content = await file.readAsString();
    final entryList = await M3uParser.parse(content);
    print("$tag entryList ${entryList.length}");

    final request = manager.check(entryList //, path: "$directory/$tag.m3u"
        );

    var start = DateTime.now();
    // Progress
    request.events.listen((event) async {
      // print("event: $event");
      if (event is CheckState) {
        switch (event) {
          case CheckState.finished:
            final diff = getDiff(start);
            print('$tag 完成检测1 用时:$diff');
            // dispose();
            break;
          case CheckState.allFinished:
            final diff = getDiff(start);
            print('全部项目完成检测1 用时:$diff');
            await Future.delayed(const Duration(milliseconds: 1500));
            dispose();
            break;
        }
      } else if (event is ProgressStatus) {
        print(
            "$tag-${event.channel!.title} ${event.currentIndex}/${event.totalCount} status: ${event.taskState} progress: ${(event.progress * 100.0).toStringAsFixed(0)}%");
      }
    }, onError: (error) {
      print("$tag error $error");
      dispose();
    }, onDone: () async {
      final diff = getDiff(start);
      print('$tag 完成检测2 用时:$diff');
      await Future.delayed(const Duration(milliseconds: 1500));
      dispose();
    });
  });

  // // Methods
  // await Future.delayed(const Duration(milliseconds: 2000));
  // request.pause();
  await Future.delayed(const Duration(milliseconds: 2000));
  // request.resume();
}

int getDiff(DateTime start) {
  var end = DateTime.now().millisecondsSinceEpoch;
  var s = DateTime.fromMillisecondsSinceEpoch(end);
  return s.difference(start).inMilliseconds;
}
