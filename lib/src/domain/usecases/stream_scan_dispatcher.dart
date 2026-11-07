import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';

import '../../core/constants/stream_scan_constants.dart';
import '../entities/stream_scan_options.dart';
import '../entities/stream_scan_request.dart';
import '../entities/stream_scan_response.dart';

/// Orchestrates sequential, aggregated, and concurrent onScan calls.
class StreamScanDispatcher {
  /// Callback handling scan requests with cache or network.
  final Future<StreamScanResponse> Function(StreamScanRequest request) onScan;

  /// Dispatcher configuration options.
  final StreamScanOptions options;

  /// Listener invoked once per counted scan, before it is started or queued.
  void Function(StreamScanRequest request)? onDispatched;

  /// Listener invoked when a request begins processing.
  void Function(StreamScanRequest request)? onProcessing;

  /// Listener invoked when queued count updates for a code.
  void Function(String code, int queuedCount)? onQueuedCountChanged;

  /// Listener invoked when a request is accepted.
  void Function(StreamScanRequest request, StreamScanResponse response)?
  onAccept;

  /// Listener invoked when a request is rejected.
  void Function(
    StreamScanRequest request,
    StreamScanResponse response,
    int totalUnaddedQuantity,
  )?
  onReject;

  /// Reporter for exceptions occurring within onScan callback.
  final void Function(FlutterErrorDetails details)? errorReporter;

  final Map<String, _CodeState> _codeStates = <String, _CodeState>{};
  final List<String> _readyQueue = <String>[];

  final Map<String, int> _acceptedByCode = <String, int>{};

  int _activeCalls = 0;
  int _acceptedCount = 0;
  int _rejectedCount = 0;
  Completer<StreamScanSummary>? _drainCompleter;

  /// Creates a dispatcher with scan handler and optional listeners.
  StreamScanDispatcher({
    required this.onScan,
    this.options = const StreamScanOptions(),
    this.onDispatched,
    this.onProcessing,
    this.onQueuedCountChanged,
    this.onAccept,
    this.onReject,
    this.errorReporter,
  });

  /// Detaches all listeners when UI controller is disposed.
  void detachListeners() {
    onDispatched = null;
    onProcessing = null;
    onQueuedCountChanged = null;
    onAccept = null;
    onReject = null;
  }

  /// Whether dispatcher has no active calls or waiting queue.
  bool get isIdle => _activeCalls == 0 && _readyQueue.isEmpty;

  /// Number of currently executing onScan calls.
  int get activeCalls => _activeCalls;

  /// Number of codes waiting in FIFO ready queue.
  int get readyQueueLength => _readyQueue.length;

  /// Total count of accepted item quantities.
  int get acceptedCount => _acceptedCount;

  /// Total count of rejected item quantities.
  int get rejectedCount => _rejectedCount;

  /// Returns final summary of accepted and rejected counts.
  StreamScanSummary get summary => StreamScanSummary(
    acceptedQuantity: _acceptedCount,
    notAddedQuantity: _rejectedCount,
    acceptedByCode: Map<String, int>.unmodifiable(_acceptedByCode),
  );

  /// Future completing when all active and queued calls finish.
  Future<StreamScanSummary> get drained {
    if (isIdle) {
      return Future<StreamScanSummary>.value(summary);
    }
    _drainCompleter ??= Completer<StreamScanSummary>();
    return _drainCompleter!.future;
  }

  /// Session wrapping drained future.
  StreamScanSession get session => StreamScanSession(drained: drained);

  /// Dispatches a scanned barcode as a unit request.
  void dispatchBarcode(Barcode barcode) {
    final String? code = barcode.rawValue;
    if (code == null || code.isEmpty) {
      return;
    }
    dispatch(
      StreamScanRequest(
        code: code,
        format: barcode.format,
        quantity: 1,
      ),
    );
  }

  /// Dispatches a scan request for processing.
  void dispatch(StreamScanRequest request) {
    // Reset drain completer for new dispatches.
    if (_drainCompleter != null && _drainCompleter!.isCompleted) {
      _drainCompleter = null;
    }

    final _CodeState state = _codeStates.putIfAbsent(
      request.code,
      () => _CodeState(code: request.code, format: request.format),
    );
    state.format = request.format;

    // Notify first so UI can surface the layer before results arrive.
    _safeCall(() => onDispatched?.call(request), 'onDispatched');

    // Code is already processing, enqueue quantity.
    if (state.isProcessing) {
      state.queuedQuantity += request.quantity;
      _safeCall(
        () => onQueuedCountChanged?.call(request.code, state.queuedQuantity),
        'onQueuedCountChanged',
      );
      return;
    }

    // Code is already waiting, accumulate quantity.
    if (_readyQueue.contains(request.code)) {
      state.queuedQuantity += request.quantity;
      _safeCall(
        () => onQueuedCountChanged?.call(request.code, state.queuedQuantity),
        'onQueuedCountChanged',
      );
      return;
    }

    // Start immediately if slots are open.
    if (_activeCalls < options.maxConcurrent) {
      _startCall(request.code, request.format, request.quantity);
    } else {
      // Otherwise place into FIFO ready queue.
      state.queuedQuantity = request.quantity;
      _readyQueue.add(request.code);
    }
  }

  void _startCall(
    String code,
    BarcodeFormat format,
    int quantity,
  ) async {
    final _CodeState state = _codeStates[code]!;
    state.isProcessing = true;
    _activeCalls++;

    final StreamScanRequest req = StreamScanRequest(
      code: code,
      format: format,
      quantity: quantity,
    );

    _safeCall(() => onProcessing?.call(req), 'onProcessing');

    try {
      StreamScanResponse response;
      try {
        response = await onScan(req);
      } catch (error, stackTrace) {
        // Handle exception by reporting and rejecting.
        _reportError(
          error,
          stackTrace,
          'while executing onScan callback',
        );
        response = const StreamScanResponse.reject(
          StreamScanConstants.defaultErrorMessage,
        );
      }

      if (response.isAccepted) {
        _handleAccept(req, response, state);
      } else {
        _handleReject(req, response, state);
      }
    } finally {
      _activeCalls--;
      state.isProcessing = false;
      _pumpQueue();
    }
  }

  void _handleAccept(
    StreamScanRequest req,
    StreamScanResponse response,
    _CodeState state,
  ) {
    _acceptedCount += req.quantity;
    _acceptedByCode[req.code] = (_acceptedByCode[req.code] ?? 0) + req.quantity;

    _safeCall(
      () => onAccept?.call(req, response),
      'onAccept',
    );

    // Enqueue remaining items for next round.
    if (state.queuedQuantity > 0) {
      final int nextQty = state.queuedQuantity;
      state.queuedQuantity = 0;

      if (!_readyQueue.contains(state.code)) {
        state.queuedQuantity = nextQty;
        _readyQueue.add(state.code);
      }
    }
  }

  void _handleReject(
    StreamScanRequest req,
    StreamScanResponse response,
    _CodeState state,
  ) {
    // Clear queued items and update reject count.
    final int queued = state.queuedQuantity;
    state.queuedQuantity = 0;
    _readyQueue.remove(state.code);

    final int unaddedQuantity = req.quantity + queued;
    _rejectedCount += unaddedQuantity;

    _safeCall(
      () => onReject?.call(req, response, unaddedQuantity),
      'onReject',
    );
    _safeCall(
      () => onQueuedCountChanged?.call(req.code, 0),
      'onQueuedCountChanged',
    );
  }

  void _pumpQueue() {
    // Pump waiting codes from FIFO queue.
    while (_activeCalls < options.maxConcurrent && _readyQueue.isNotEmpty) {
      final String nextCode = _readyQueue.removeAt(0);
      final _CodeState state = _codeStates[nextCode]!;
      final int qty = state.queuedQuantity;
      state.queuedQuantity = 0;
      _startCall(nextCode, state.format, qty);
    }

    _checkDrain();
  }

  void _checkDrain() {
    // Complete drain completer when all calls finish.
    if (isIdle) {
      if (_drainCompleter != null && !_drainCompleter!.isCompleted) {
        _drainCompleter!.complete(summary);
      }
    }
  }

  void _safeCall(VoidCallback action, String contextDesc) {
    try {
      action();
    } catch (error, stackTrace) {
      _reportError(
        error,
        stackTrace,
        'while invoking $contextDesc listener',
      );
    }
  }

  void _reportError(
    Object error,
    StackTrace stackTrace,
    String contextDesc,
  ) {
    final FlutterErrorDetails details = FlutterErrorDetails(
      exception: error,
      stack: stackTrace,
      library: 'smart_scanner',
      context: ErrorDescription(contextDesc),
    );
    if (errorReporter != null) {
      errorReporter!(details);
    } else {
      FlutterError.reportError(details);
    }
  }
}

/// Internal execution tracking state for a barcode.
class _CodeState {
  final String code;
  BarcodeFormat format;
  int queuedQuantity = 0;
  bool isProcessing = false;

  _CodeState({required this.code, required this.format});
}
