part of '../iptv_check_manager.dart';

/// Communication types
/// User <-> CheckManager <-> Isolate

/// Isolate commands
enum WorkerCommand { cancel, pause, resume }

/// Stream return types
/// Errors will be send as throw
/// progress send as double [0.0, 1.0]
/// other events are part of [CheckState]
enum CheckState {
  queued,
  started,
  paused,
  resumed,
  cancelled,
  finished,
  allFinished
}
