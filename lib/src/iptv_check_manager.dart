import 'dart:io';
import 'dart:async';
import 'dart:collection';
import 'dart:isolate';
import 'package:http/http.dart' as http;
import 'package:iptv_check_manager/iptv_check_manager.dart';
import 'package:m3u/m3u.dart';

part 'types/request.dart';
part 'types/worker.dart';
part 'types/comm.dart';

class ProgressStatus {
  ProgressStatus(
      {this.progress = 0.0,
      this.taskState = TaskState.checking,
      this.channel,
      this.currentIndex = 0,
      this.totalCount = 0});
  double progress;
  int currentIndex;
  int totalCount = 0;
  M3uGenericEntry? channel;
  TaskState taskState;
}

class CheckManager {
  /// Singletone
  CheckManager._();
  static final CheckManager instance = CheckManager._();

  /// Public constructor
  CheckManager();

  /// Current initialization status
  bool initialized = false;

  /// Base directory where to save files
  String? _directory;

  /// Base client cloned for each isolate during spawning
  http.BaseClient? _client;

  /// Global [safeRange] setting, will be skipped if passed into `check()` function
  bool _safeRange = true;

  /// Initialize instance
  /// [isolates] amount of isolates to use
  /// [isolates] should be less than `Platform.numberOfProcessors - 3`
  /// [directory] where to save files, without trailing slash `/`, default to `/tmp`
  /// [safeRange] used to skip range header if bytes end not found
  Future<void> init(
      {int isolates = 3,
      String? directory,
      http.BaseClient? client,
      bool? safeRange}) async {
    if (initialized) throw Exception("Already initialized");

    // Must be set before isolates initializing, otherwise default one will be used
    _directory = directory;
    _client = client;
    if (safeRange != null) _safeRange = safeRange;

    // future.wait，等待所有future都执行成功后进入then类似js的promise.all
    await Future.wait(
            [for (var i = 0; i < isolates; i++) _initWorker(index: i)])
        .then(_workers.addAll);

    for (var i = 0; i < isolates; i++) {
      _freeWorkersIndexes.add(i);
    }

    initialized = true;
    _processQueue();
  }

  /// Clean up the isolates and clear the queue
  Future<void> dispose() async {
    _queue.clear();
    for (var worker in _workers) {
      worker.isolate.kill();
    }
    _activeWorkers.forEach((request, worker) {
      Future.delayed(const Duration(milliseconds: 50))
          .then((_) => worker.port.send(WorkerCommand.cancel));
      Future.delayed(const Duration(milliseconds: 100))
          .then((_) => worker.isolate.kill());
    });
    await Future.delayed(const Duration(milliseconds: 100));
    _workers.clear();
    _activeWorkers.clear();
    _freeWorkersIndexes.clear();

    initialized = false;
  }

  /// Queue of requests
  final _queue = Queue<CheckRequest>();

  /// Queued requests (unmodifiable)
  List<CheckRequest> get queue => _queue.toList();

  /// Isolates references
  final List<Worker> _workers = [];
  final Set<int> _freeWorkersIndexes = {};
  final Map<CheckRequest, Worker> _activeWorkers = {};

  /// Add request to the queue
  /// if [path] is empty base [_directory] used
  CheckRequest check(List<M3uGenericEntry> m3uEntryList,
      { //String? path,
      int? filesize,
      bool? safeRange}) {
    late final CheckRequest request;
    request = CheckRequest._(
        m3uEntryList: m3uEntryList,
        channelCount: filesize,
        safeRange: safeRange,
        cancel: () {
          _cancel(request);
        },
        resume: () {
          _resume(request);
        },
        pause: () {
          _pause(request);
        });
    _queue.add(request);
    request._addEvent(CheckState.queued);
    _processQueue();
    return request;
  }

  /// Clear the queue and cancel all active requests
  void cancelAll() async {
    final requests = _queue.toList();
    _queue.clear();
    for (var request in requests) {
      request._addEvent(CheckState.cancelled);
      request.isCancelled = true;
    }
    _activeWorkers.forEach((request, worker) {
      worker.port.send(WorkerCommand.cancel);
      // ensure if wasn't cancelled due to pre-started checking state
      for (final delay in [500, 1000, 1500]) {
        Future.delayed(Duration(milliseconds: delay)).then((_) {
          if (worker.request == request) {
            worker.port.send(WorkerCommand.cancel);
          }
        });
      }
    });
  }

  /// Removes request from the queue or sending cancellation request to isolate
  void _cancel(CheckRequest request) {
    if (_queue.remove(request)) {
      // removed
      request._addEvent(CheckState.cancelled);
      request.isCancelled = true;
    } else {
      // wasn't removed, already in progress
      _activeWorkers[request]?.port.send(WorkerCommand.cancel);
    }
  }

  /// Send pause request to isolate if exists
  void _pause(CheckRequest request) =>
      _activeWorkers[request]?.port.send(WorkerCommand.pause);

  /// Send resume request to isolate if exists
  void _resume(CheckRequest request) =>
      _activeWorkers[request]?.port.send(WorkerCommand.resume);

  /// Process queued requests
  void _processQueue() {
    if (_queue.isNotEmpty && _freeWorkersIndexes.isNotEmpty) {
      // request
      final request = _queue.removeFirst();
      final entryList = request.m3uEntryList;
      // final path = request.path;
      final safeRange = request.safeRange;

      // data
      final Map<String, dynamic> data = {
        "m3uEntryList": entryList,
        // if (path != null) "path": path,
        "size": request.channelCount.toString(),
        if (safeRange != null) "safeRange": safeRange.toString(),
      };

      // worker
      final index = _freeWorkersIndexes.first;
      _freeWorkersIndexes.remove(index);
      final worker = _workers[index];
      worker.request = request;

      // proceed
      worker.port.send(data);
      _activeWorkers[request] = worker;
    }
  }

  /// Prepare isolate for the next request
  Future<void> _cleanWorker(int index, {Worker? process}) async {
    await Future.delayed(Duration.zero);

    final worker = _workers[index];
    /*if (worker.request?._controller.hasListener == true) {
      // worker.event(CheckEvents.finished);
      worker.request?._controller.close();
    } */
    _activeWorkers.remove(worker.request);
    if (queue.isEmpty && _activeWorkers.isEmpty) {
      process?.event(CheckState.allFinished);
    }
    worker.request = null;
    _freeWorkersIndexes.add(index);
    _processQueue();
  }

  /// Initialize long running isolate with two-way communication channel
  Future<Worker> _initWorker({required int index}) async {
    final completer = Completer<Worker>();
    final mainPort = ReceivePort();
    late final Isolate isolate;

    Worker? process;
    mainPort.listen((event) {
      if (event is SendPort) {
        // port received after isolate is ready (once)
        process = Worker(isolate: isolate, port: event);
        completer.complete(process);
      } else if (event is Exception) {
        // errors
        process?.error(event);
        _cleanWorker(index);
      } else if (event is CheckState) {
        // other incoming messages from isolate
        switch (event) {
          case CheckState.cancelled:
            process?.event(event);
            _cleanWorker(index);
            process?.request?.isCancelled = true;
            break;
          case CheckState.finished:
            process?.event(event);
            _cleanWorker(index, process: process);
            break;
          case CheckState.started:
            process?.event(event);
            break;
          case CheckState.resumed:
            process?.event(event);
            process?.request?.isPaused = false;
            break;
          case CheckState.paused:
            process?.event(event);
            process?.request?.isPaused = true;
            break;
          default:
            break;
        }
      } else if (event is ProgressStatus) {
        // states
        process?.event(event);
        process?.request?.progressStatus = event;
      }
    });

    isolate = await Isolate.spawn(_isolatedWork, mainPort.sendPort);

    return completer.future;
  }

  /// Isolate's body. After two-way binding isolate receives urls and proceed checkings
  void _isolatedWork(SendPort sendPort) {
    final isolatePort = ReceivePort();
    // clone the client
    final client = _client ?? http.Client();

    CheckTask? task;
    double previousProgress = -1.0;
    isolatePort.listen((event) {
      if (event is Map<String, dynamic>) {
        // check info
        // print(
        // '_isolatedWork queue ${queue.length} worker ${_workers.length} _activeWorkers ${_activeWorkers.length}');
        try {
          final List<M3uGenericEntry> m3uEntryList = event["m3uEntryList"];
          // final String? path = event["path"];
          final String? sizeString = event["size"];
          final int? size =
              sizeString != null ? int.tryParse(sizeString) : null;

          bool safeRange = _safeRange;
          final String? safe = event["safeRange"];
          if (safe != null) {
            safeRange = safe == "true" ? true : false;
          }

          // final File file = File(path!);
          // if (file.existsSync()) {
          //   file.deleteSync(recursive: true);
          // } else {
          //   file.createSync(recursive: true);
          // }
          // if (path == null) {
          //   // use base directory, extract name from url
          //   final lastSegment = url.pathSegments.last;
          //   final filename =
          //       lastSegment.substring(lastSegment.lastIndexOf("/") + 1);
          //   file = File("$directory/$filename");
          // } else {
          //   // custom location
          //   file = File(path);
          //   // final filename = file.uri.pathSegments.last;
          // }
          previousProgress = -1.0;

          // run zoned to catch async check excaptions without breaking isolate
          runZonedGuarded(() async {
            await CheckTask.check(m3uEntryList,
                    // file: file,
                    client: client,
                    deleteOnCancel: true,
                    size: size,
                    safeRange: safeRange)
                .then((t) {
              task = t;
              task!.events.listen((event) {
                switch (event.state) {
                  case TaskState.success:
                    previousProgress =
                        checkProgress(event, previousProgress, sendPort);
                    break;
                  case TaskState.paused:
                    sendPort.send(CheckState.paused);
                    break;
                  case TaskState.canceled:
                    sendPort.send(CheckState.cancelled);
                    break;
                  case TaskState.error:
                    sendPort.send(event.error!);
                    break;
                  case TaskState.checking:
                    break;
                  case TaskState.resume:
                    break;
                  case TaskState.errorStatusCode:
                    // print('errorStatusCode');
                    previousProgress =
                        checkProgress(event, previousProgress, sendPort);
                    break;
                  case TaskState.timeout:
                    // print('timeout');
                    previousProgress =
                        checkProgress(event, previousProgress, sendPort);
                    break;
                  case TaskState.done:
                    // print('TaskState.done');
                    // print(
                    // 'success queue ${queue.length} worker ${_workers.length} _activeWorkers ${_activeWorkers.length}');
                    sendPort.send(CheckState.finished);
                    break;
                }
              });
              sendPort.send(CheckState.started);
            });
          }, (e, s) => sendPort.send(e));
        } catch (error) {
          // catch sync exception
          sendPort.send(error);
        }
      } else if (event is WorkerCommand) {
        // control events
        switch (event) {
          case WorkerCommand.pause:
            task?.pause();
            break;
          case WorkerCommand.resume:
            task?.resume().then((status) {
              if (status) sendPort.send(CheckState.resumed);
            });
            break;
          case WorkerCommand.cancel:
            task?.cancel();
            break;
        }
      }
    });

    sendPort.send(isolatePort.sendPort);
  }

  double checkProgress(
      TaskEvent event, double previousProgress, SendPort sendPort) {
    final currentChannel = event.currentChannel;
    final totalChannel = event.totalChannel!;
    final currentIndex = event.currentIndex!;
    // event.state.
    double progress;
    if (totalChannel <= 0) {
      // total is undefined
      progress = 0.0;
    } else {
      progress = (currentIndex / totalChannel * 100).floorToDouble() / 100;
    }
    ProgressStatus ps = ProgressStatus(
        progress: progress,
        taskState: event.state,
        channel: event.currentChannel,
        totalCount: event.totalChannel!,
        currentIndex: event.currentIndex!);
    // print('ProgressStatus $ps');
    sendPort.send(ps);
    // // skip duplicates
    // if (previousProgress != progress) {
    //   sendPort.send(progress);
    //   previousProgress = progress;
    // }
    return previousProgress;
  }
}
