import 'dart:async' show StreamController, StreamSubscription;
import 'dart:io' show File, FileMode;
import 'package:http/http.dart' as http;
import 'package:http/http.dart';
import 'package:iptv_check_manager/src/util.dart';
import 'package:m3u/m3u.dart';

enum TaskState {
  checking,
  resume,
  paused,
  success,
  canceled,
  error,
  errorStatusCode,
  timeout,
  done
}

class TaskEvent {
  const TaskEvent(
      {required this.state,
      this.currentChannel,
      this.currentIndex,
      this.totalChannel,
      this.error});

  final TaskState state;
  final M3uGenericEntry? currentChannel;
  final int? currentIndex;
  final int? totalChannel;
  final Object? error;

  @override
  String toString() => "TaskEvent ($state)";
}

class CheckTask {
  CheckTask._({
    required this.m3uEntryList,
    // required this.file,
    required this.headers,
    required this.client,
    required this.deleteOnCancel,
    required this.deleteOnError,
    this.size,
    this.safeRange = false,
  });

  // final Uri url;
  final List<M3uGenericEntry> m3uEntryList;
  // final File file;
  final Map<String, String> headers;
  final http.Client client;
  final bool deleteOnCancel;
  final bool deleteOnError;
  final int? size;
  final bool safeRange;

  /// Events stream, used to listen for checking state changes
  Stream<TaskEvent> get events => _events.stream;

  /// Latest event
  TaskEvent? get event => _event;

  /// Static method to fire file checking returns future of [CheckTask] which may be used to control the request
  ///
  /// * [headers] are custom HTTP headers for client, may be used for request authentication
  /// * if [client] is pas null the default one will be used
  /// * [file] is check path, file will be created while checking
  /// * [deleteOnCancel] specify if file should be deleted after check is cancelled
  /// * [deleteOnError] specify if file should be deleted when error is raised
  /// * [size] used to specify bytes end for range header
  /// * [safeRange] used to skip range header if bytes end not found
  ///
  static Future<CheckTask> check(
    List<M3uGenericEntry> m3uEntryList, {
    Map<String, String> headers = const {},
    http.Client? client,
    // required File file,
    bool deleteOnCancel = true,
    bool deleteOnError = false,
    int? size,
    bool safeRange = false,
  }) async {
    // print('start check========');
    final task = CheckTask._(
        m3uEntryList: m3uEntryList,
        headers: headers,
        client: client ?? http.Client(),
        // file: file,
        deleteOnCancel: deleteOnCancel,
        deleteOnError: deleteOnError,
        size: size,
        safeRange: safeRange);
    await task.resume();
    return task;
  }

  /// Pause file checking, file will be stored on defined location
  /// checking may be continued from the paused point if file exists
  Future<bool> pause() async {
    if (_doneOrCancelled || !_checking) return false;
    await _subscription?.cancel();
    _addEvent(TaskEvent(state: TaskState.paused));
    return true;
  }

  /// Resume file checking, if file exists checking will continue from file size
  /// will return `false` if checking is in progress, finished or cancelled
  Future<bool> resume() async {
    if (_doneOrCancelled || _checking) return false;
    // _subscription = await _check();
    _check().then((value) => _subscription = value);
    _addEvent(TaskEvent(state: TaskState.resume));
    return true;
  }

  /// Cancel the checking, if [deleteOnCancel] is `true` then file will be deleted
  /// will return `false` if checking was already finished or cancelled
  Future<bool> cancel() async {
    if (_doneOrCancelled) return false;
    await _subscription?.cancel();
    _addEvent(TaskEvent(state: TaskState.canceled));
    _dispose(TaskState.canceled);
    return true;
  }

  // Events stream
  StreamSubscription? _subscription;
  final StreamController<TaskEvent> _events = StreamController<TaskEvent>();
  TaskEvent? _event;

  late M3uGenericEntry _currentChannel;
  int _totalChannel = -1;
  int _currentChannelIndex = 0;

  // Internal shortcuts
  bool get _cancelled => event?.state == TaskState.canceled;
  bool get _checking => event?.state == TaskState.checking;
  bool get _done => event?.state == TaskState.success;
  bool get _doneOrCancelled => _done || _cancelled;

  /// Add new event to stream
  void _addEvent(TaskEvent event) {
    _event = event;
    if (!_events.isClosed) {
      _events.add(event);
    }
  }

  /// Clean up
  Future<void> _dispose(TaskState state) async {
    if (state == TaskState.canceled) {
      if (deleteOnCancel) {
        // await file.delete();
      }
      _events.close();
    } else if (state == TaskState.error) {
      if (deleteOnError) {
        // await file.delete();
      }
      _events.close();
    } else if (state == TaskState.success) {
      _events.close();
    }
  }

  /// Check function
  /// returns future of [StreamSubscription] which used to receive updates internally
  /// returns `null` on error
  Future<StreamSubscription?> _check() async {
    late final StreamSubscription subscription;
    final totalChannel = m3uEntryList.length;
    Future<void> onError(Object error) async {
      // print('onError');
      _addEvent(TaskEvent(
          state: TaskState.error,
          error: error,
          currentIndex: _currentChannelIndex,
          totalChannel: totalChannel));
      _dispose(TaskState.error);
    }

    try {
      // print('totalChannel = $totalChannel');
      // final waitingList = m3uEntryList.skip(_currentChannelIndex);
      // String genContent = "#EXTM3U\n";
      subscription = Stream.fromIterable(m3uEntryList).listen((entry) async {
        subscription.pause();
        _currentChannelIndex += 1;
        _currentChannel = entry;
        try {
          Response channelResponse = await client
              .get(Uri.parse(entry.link))
              .timeout(Duration(seconds: 2));
          // print('response ${channelResponse.body}');
          // client.close();
          // .then((channelResponse) async {
          if (channelResponse.statusCode == 200) {
            // genContent += createM3uContent(entry);
            _addEvent(TaskEvent(
                state: TaskState.success,
                currentChannel: entry,
                currentIndex: _currentChannelIndex,
                totalChannel: totalChannel));
            subscription.resume();
          } else {
            _addEvent(TaskEvent(
                state: TaskState.errorStatusCode,
                currentChannel: entry,
                currentIndex: _currentChannelIndex,
                totalChannel: totalChannel));
            subscription.resume();
          }
        } catch (e) {
          _addEvent(TaskEvent(
              state: TaskState.timeout,
              currentChannel: entry,
              currentIndex: _currentChannelIndex,
              totalChannel: totalChannel));
          subscription.resume();
        }
        // }).onError((error, stackTrace) {
        //   _addEvent(TaskEvent(
        //       state: TaskState.timeout,
        //       currentChannel: entry,
        //       currentIndex: _currentChannelIndex,
        //       totalChannel: totalChannel));
        //   subscription.resume();
        // });
      }, onDone: () async {
        // print('onDone');

        // if (await file.exists()) {
        //   await file.delete(recursive: false);
        // }
        // await file.create(recursive: true);
        // final sink = await file.open(mode: FileMode.write);
        // // await sink.writeString("#EXTM3U\n");
        // await sink.writeString(genContent);
        // await sink.close();
        _addEvent(const TaskEvent(state: TaskState.done));
        // client.close();
        _dispose(TaskState.done);
      }, onError: onError);
      // }
      return subscription;
    } catch (error) {
      // print('catch error');
      await onError(error);
      return null;
    }
  }
}
