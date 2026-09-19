import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Persistence failures are visible to callers without printing message content.
class AiStoreException implements Exception {
  const AiStoreException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => 'AiStoreException: $message';
}

/// One local store for AI conversations, separate from shared CAD documents.
///
/// The controller owns one instance per directory. Operations on that instance
/// are serialized, and save captures its input before any asynchronous work.
/// A flushed sibling is renamed over the destination; there is deliberately no
/// direct-write fallback that could truncate a good save. The previous valid
/// save remains in a backup. This also works when Windows refuses replacement:
/// the error reaches the caller and the existing files remain recoverable.
///
/// This is not a credential vault. Recognizable credential fields are rejected,
/// not silently removed. Callers must keep credentials out of message payloads.
class AiStore {
  AiStore(this.directory, {this.maxBytes = 32 * 1024 * 1024}) {
    if (maxBytes <= 0) throw ArgumentError.value(maxBytes, 'maxBytes');
  }

  final Directory directory;
  final int maxBytes;

  static const fileName = 'ai_sessions.json';
  File get _file => File('${directory.path}/$fileName');
  File get _backup => File('${directory.path}/$fileName.bak');
  File get _temporary => File('${directory.path}/$fileName.tmp');
  File get _backupTemporary => File('${directory.path}/$fileName.bak.tmp');

  Future<void> _queue = Future<void>.value();
  Object? _lastSaveError;
  StackTrace? _lastSaveStack;

  /// A successful [load] can recover a previous save. Surface this to the user
  /// rather than presenting an older conversation as if no recovery occurred.
  bool recoveredFromBackup = false;
  String? recoveryReason;

  Future<T> _enqueue<T>(Future<T> Function() action) {
    final result = _queue.then((_) => action());
    // Only the internal scheduling tail consumes errors. The returned Future
    // still fails, and a failed save is also reported by flush().
    _queue = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  /// Returns null only when no committed save or backup exists. Corrupt files
  /// are never interpreted as an empty history.
  Future<Map<String, dynamic>?> load() => _enqueue(() async {
        recoveredFromBackup = false;
        recoveryReason = null;
        final hasPrimary = await _file.exists();
        final hasBackup = await _backup.exists();
        if (!hasPrimary && !hasBackup) return null;

        Object? primaryError;
        if (hasPrimary) {
          try {
            return (await _read(_file)).value;
          } catch (error) {
            primaryError = error;
          }
        }
        if (hasBackup) {
          try {
            final saved = await _read(_backup);
            recoveredFromBackup = true;
            recoveryReason = hasPrimary
                ? 'The latest AI save could not be read. The previous save was recovered.'
                : 'The latest AI save was missing. The previous save was recovered.';
            return saved.value;
          } catch (error) {
            throw AiStoreException(
              'AI conversations could not be read from the save or its backup. '
              'The files were kept for recovery.',
              cause: primaryError ?? error,
            );
          }
        }
        throw AiStoreException(
          'AI conversations could not be read and no backup is available. '
          'The saved file was kept for recovery.',
          cause: primaryError,
        );
      });

  Future<void> save(Map<String, dynamic> value) {
    // Capture immediately: callers may continue editing the model while an
    // earlier save is waiting for I/O.
    Uint8List? encoded;
    Object? encodingError;
    StackTrace? encodingStack;
    try {
      _validate(value);
      encoded = Uint8List.fromList(utf8.encode(jsonEncode(value)));
      if (encoded.length > maxBytes) {
        throw AiStoreException(
          'AI conversations exceed the $maxBytes byte storage limit.',
        );
      }
    } catch (error, stack) {
      encodingError = error is AiStoreException
          ? error
          : AiStoreException(
              'AI conversations could not be encoded.',
              cause: error,
            );
      encodingStack = stack;
    }

    return _enqueue(() async {
      try {
        if (encodingError != null) {
          Error.throwWithStackTrace(encodingError, encodingStack!);
        }
        await directory.create(recursive: true);
        await _temporary.writeAsBytes(encoded!, flush: true);

        Uint8List? previous;
        if (await _file.exists()) {
          try {
            previous = (await _read(_file)).bytes;
          } on AiStoreException {
            // Never replace a valid backup with a corrupt primary. A recovered
            // controller may now be saving its repaired or continued history.
          }
        }
        if (previous != null) {
          await _backupTemporary.writeAsBytes(previous, flush: true);
          await _backupTemporary.rename(_backup.path);
        }
        await _temporary.rename(_file.path);
        _lastSaveError = null;
        _lastSaveStack = null;
      } catch (error, stack) {
        final failure = error is AiStoreException
            ? error
            : AiStoreException(
                'AI conversations could not be saved. The last valid save was retained.',
                cause: error,
              );
        _lastSaveError = failure;
        _lastSaveStack = stack;
        Error.throwWithStackTrace(failure, stack);
      } finally {
        // Cleanup must not obscure the actual write failure. Uncommitted temp
        // files are ignored by load even if an OS lock prevents their removal.
        for (final file in [_temporary, _backupTemporary]) {
          try {
            if (await file.exists()) await file.delete();
          } on FileSystemException {
            // Best effort only; accepted data never depends on these files.
          }
        }
      }
    });
  }

  /// Waits for operations queued before this call and reports the most recent
  /// failed save until a subsequent save succeeds. Save callers should also
  /// handle the Future returned by save().
  Future<void> flush() async {
    await _queue;
    if (_lastSaveError != null) {
      Error.throwWithStackTrace(_lastSaveError!, _lastSaveStack!);
    }
  }

  Future<_SavedJson> _read(File file) async {
    if (await file.length() > maxBytes) {
      throw const AiStoreException(
        'The saved AI conversations exceed the storage limit.',
      );
    }
    final bytes = await file.readAsBytes();
    // Check again in case the file changed between stat and read.
    if (bytes.length > maxBytes) {
      throw const AiStoreException(
        'The saved AI conversations exceed the storage limit.',
      );
    }
    try {
      final value = jsonDecode(utf8.decode(bytes));
      if (value is! Map<String, dynamic>) {
        throw const AiStoreException(
          'The saved AI conversations are not a JSON object.',
        );
      }
      _validate(value);
      return _SavedJson(bytes, value);
    } on AiStoreException {
      rethrow;
    } catch (error) {
      throw AiStoreException(
        'The saved AI conversations are invalid.',
        cause: error,
      );
    }
  }

  static void _validate(Object? value) {
    final ancestors = HashSet<Object>.identity();
    void visit(Object? node, int depth) {
      if (depth > 128) {
        throw const AiStoreException(
          'AI conversation data is nested too deeply.',
        );
      }
      if (node == null || node is String || node is bool || node is num) return;
      if (node is! Map && node is! List) {
        // Do not allow an arbitrary object's toJson() to introduce unchecked
        // credential fields after this validation has finished.
        throw const AiStoreException(
          'AI conversation data contains an unsupported value.',
        );
      }
      if (!ancestors.add(node)) {
        throw const AiStoreException('AI conversation data contains a cycle.');
      }
      if (node is Map) {
        for (final entry in node.entries) {
          if (entry.key is! String) {
            throw const AiStoreException(
              'AI conversation data contains a non-text field name.',
            );
          }
          final key = (entry.key as String)
              .replaceAll(RegExp(r'[-_\s]'), '')
              .toLowerCase();
          if (const {
            'apikey',
            'authorization',
            'accesstoken',
            'refreshtoken',
            'clientsecret',
            'password',
          }.contains(key)) {
            throw const AiStoreException(
              'Credentials must not be saved with AI conversations.',
            );
          }
          visit(entry.value, depth + 1);
        }
      } else if (node is List) {
        for (final child in node) {
          visit(child, depth + 1);
        }
      }
      ancestors.remove(node);
    }

    visit(value, 0);
  }
}

class _SavedJson {
  const _SavedJson(this.bytes, this.value);
  final Uint8List bytes;
  final Map<String, dynamic> value;
}
