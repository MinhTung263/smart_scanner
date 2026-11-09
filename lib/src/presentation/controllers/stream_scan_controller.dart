import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';

import '../../core/constants/stream_scan_constants.dart';
import '../../data/services/stream_vibration_service.dart';
import '../../domain/entities/stream_frame_report.dart';
import '../../domain/entities/stream_scan_card_item.dart';
import '../../domain/entities/stream_scan_options.dart';
import '../../domain/entities/stream_scan_request.dart';
import '../../domain/entities/stream_scan_response.dart';
import '../../domain/entities/stream_scan_validator.dart';
import '../../domain/usecases/stream_presence_tracker_usecase.dart';
import '../../domain/usecases/stream_scan_dispatcher.dart';

/// Presentation controller managing UI state for stream scan.
class StreamScanController extends ChangeNotifier {
  final StreamScanOptions _options;
  final StreamPresenceTrackerUseCase _presenceTracker;
  final StreamScanDispatcher _dispatcher;
  final StreamVibrationService _vibrationService;

  final ValueNotifier<List<StreamScanCardItem>> _recentCards =
      ValueNotifier<List<StreamScanCardItem>>(<StreamScanCardItem>[]);
  final ValueNotifier<List<StreamScanErrorChipItem>> _errorChips =
      ValueNotifier<List<StreamScanErrorChipItem>>(<StreamScanErrorChipItem>[]);
  final ValueNotifier<bool> _isNetworkSlow = ValueNotifier<bool>(false);
  final ValueNotifier<StreamScanCounter> _counter =
      ValueNotifier<StreamScanCounter>(const StreamScanCounter());
  final ValueNotifier<StreamScanFrameFlash> _frameFlash =
      ValueNotifier<StreamScanFrameFlash>(StreamScanFrameFlash.none);
  final ValueNotifier<bool> _isContinuous = ValueNotifier<bool>(true);
  final ValueNotifier<bool> _isWaitingForTap = ValueNotifier<bool>(false);

  // Every product scanned this session; order lists codes, most recent first.
  final Map<String, StreamScanCardItem> _sessionCards =
      <String, StreamScanCardItem>{};
  final List<String> _cardOrder = <String>[];

  final Map<String, Timer> _slowTimers = <String, Timer>{};
  final Map<String, Timer> _chipTimers = <String, Timer>{};
  Timer? _flashTimer;

  // Reasons the tracker is paused; counting resumes only when none remain.
  final Set<String> _pauseReasons = <String>{};
  static const String _singleModePause = 'single';
  static const String _externalPause = 'external';
  bool _awaitingSingleResult = false;

  /// Creates a controller with scan callback and optional dependencies.
  StreamScanController({
    required Future<StreamScanResponse> Function(StreamScanRequest request)
    onScan,
    StreamScanOptions options = const StreamScanOptions(),
    bool? enableVibration,
    StreamVibrationService? vibrationService,
    StreamPresenceTrackerUseCase? presenceTracker,
    StreamScanDispatcher? dispatcher,
  }) : _options = options,
       _vibrationService =
           vibrationService ??
           StreamVibrationService(enableVibration: enableVibration),
       _presenceTracker =
           presenceTracker ?? StreamPresenceTrackerUseCase(options: options),
       _dispatcher =
           dispatcher ??
           StreamScanDispatcher(onScan: onScan, options: options) {
    _attachDispatcherListeners();
  }

  /// Most recently scanned products, newest first, at most `maxVisibleCards`.
  /// The full session list stays in the controller, so a product pushed out
  /// of view is still recognised when it is scanned again.
  ValueNotifier<List<StreamScanCardItem>> get recentCards => _recentCards;

  /// Listenable list of active toast chips (errors and info).
  ValueNotifier<List<StreamScanErrorChipItem>> get errorChips => _errorChips;

  /// Listenable boolean flag indicating slow network.
  ValueNotifier<bool> get isNetworkSlow => _isNetworkSlow;

  /// Distinct products and total quantity accepted in this session.
  ValueListenable<StreamScanCounter> get counter => _counter;

  /// Momentary green or red flash of the scan frame.
  ValueListenable<StreamScanFrameFlash> get frameFlash => _frameFlash;

  /// Whether the "Quét liên tục" toggle is on (default on).
  ValueListenable<bool> get isContinuous => _isContinuous;

  /// True while paused after one accepted code with the toggle off.
  ValueListenable<bool> get isWaitingForTap => _isWaitingForTap;

  /// Whether anything was scanned this session (accepted or in flight).
  bool get hasScannedItems => _sessionCards.isNotEmpty;

  /// Active options configured for this stream scan session.
  StreamScanOptions get options => _options;

  /// Underlying dispatcher managing background scan calls.
  StreamScanDispatcher get dispatcher => _dispatcher;

  /// Tracker determining when barcodes enter or leave frame.
  StreamPresenceTrackerUseCase get presenceTracker => _presenceTracker;

  /// Vibration service emitting haptic pulses.
  StreamVibrationService get vibrationService => _vibrationService;

  /// Session tracking background processing drain status.
  StreamScanSession get session => _dispatcher.session;

  /// Processes camera frame report and dispatches detected codes.
  /// Codes failing `options.validator` are reported and never dispatched.
  void onFrameProcessed(StreamFrameReport report) {
    final List<Barcode> barcodesToCount = _presenceTracker.processFrame(report);
    for (final Barcode barcode in barcodesToCount) {
      final String? error = _validate(barcode);
      if (error != null) {
        _handleInvalid(barcode.rawValue ?? '', error);
        continue;
      }
      _dispatcher.dispatchBarcode(barcode);
    }
  }

  /// Turns continuous scanning on or off and shows an info toast.
  /// Off: after one accepted code, counting pauses until [continueScanning].
  void setContinuousMode(bool value) {
    if (_isContinuous.value == value) {
      return;
    }
    _isContinuous.value = value;
    if (value) {
      _awaitingSingleResult = false;
      _isWaitingForTap.value = false;
      _removePauseReason(_singleModePause);
    }
    _showToast(
      value
          ? StreamScanConstants.continuousOnMessage
          : StreamScanConstants.continuousOffMessage,
      kind: StreamScanChipKind.info,
      autoHide: StreamScanConstants.infoChipAutoHide,
    );
  }

  /// Resumes counting after the single-mode pause ("Chạm để quét tiếp").
  void continueScanning() {
    _isWaitingForTap.value = false;
    _removePauseReason(_singleModePause);
  }

  /// Manually dismisses an error chip by unique identifier.
  void dismissErrorChip(String id) {
    _cancelChipTimer(id);
    final List<StreamScanErrorChipItem> updated = _errorChips.value
        .where((StreamScanErrorChipItem c) => c.id != id)
        .toList();
    _errorChips.value = updated;
  }

  /// Pauses counting (e.g. while a dialog is open), keeping presence state.
  void pause() => _addPauseReason(_externalPause);

  /// Resumes counting paused by [pause].
  void resume() => _removePauseReason(_externalPause);

  @override
  void dispose() {
    // Cancel all slow network indicator timers.
    for (final Timer timer in _slowTimers.values) {
      timer.cancel();
    }
    _slowTimers.clear();

    // Cancel all error chip auto-hide timers.
    for (final Timer timer in _chipTimers.values) {
      timer.cancel();
    }
    _chipTimers.clear();
    _flashTimer?.cancel();

    // Detach UI listeners without cancelling background queue.
    _dispatcher.detachListeners();

    _recentCards.dispose();
    _errorChips.dispose();
    _isNetworkSlow.dispose();
    _counter.dispose();
    _frameFlash.dispose();
    _isContinuous.dispose();
    _isWaitingForTap.dispose();

    super.dispose();
  }

  void _attachDispatcherListeners() {
    _dispatcher.onDispatched = (StreamScanRequest request) {
      _handleDispatched(request);
    };

    _dispatcher.onProcessing = (StreamScanRequest request) {
      _handleProcessing(request);
    };

    _dispatcher.onAccept =
        (StreamScanRequest request, StreamScanResponse response) {
          _handleAccept(request, response);
        };

    _dispatcher.onReject =
        (
          StreamScanRequest request,
          StreamScanResponse response,
          int totalUnaddedQuantity,
        ) {
          _handleReject(request, response, totalUnaddedQuantity);
        };
  }

  void _handleDispatched(StreamScanRequest request) {
    final StreamScanCardItem? existing = _sessionCards[request.code];
    final DateTime now = DateTime.now();
    _sessionCards[request.code] = existing == null
        ? StreamScanCardItem(
            code: request.code,
            format: request.format,
            pendingQuantity: request.quantity,
            timestamp: now,
          )
        : existing.copyWith(
            pendingQuantity: existing.pendingQuantity + request.quantity,
            timestamp: now,
          );

    // Every counted scan brings its product card to the front.
    _cardOrder.remove(request.code);
    _cardOrder.insert(0, request.code);
    _publishCards();

    // Single mode: stop counting until this scan's result is known.
    if (!_isContinuous.value) {
      _awaitingSingleResult = true;
      _addPauseReason(_singleModePause);
    }
  }

  void _handleProcessing(StreamScanRequest request) {
    // Start slow hint timer for this request.
    _slowTimers[request.code]?.cancel();
    _slowTimers[request.code] = Timer(_options.slowHintAfter, () {
      _isNetworkSlow.value = true;
    });
  }

  void _handleAccept(StreamScanRequest request, StreamScanResponse response) {
    _vibrationService.vibrateSuccess();
    _flash(StreamScanFrameFlash.success);

    // Stop slow network timer for completed request.
    _clearSlowTimer(request.code);

    final StreamScanCardItem? existing = _sessionCards[request.code];
    final StreamScanCardItem base =
        existing ??
        StreamScanCardItem(
          code: request.code,
          format: request.format,
          timestamp: DateTime.now(),
        );
    _sessionCards[request.code] = base.copyWith(
      title: response.title,
      subtitle: response.subtitle,
      totalInCart: response.totalInCart,
      imageUrl: response.imageUrl,
      pendingQuantity: math.max(0, base.pendingQuantity - request.quantity),
      acceptedQuantity: base.acceptedQuantity + request.quantity,
      timestamp: DateTime.now(),
    );

    // Card order was set at scan time; only add if it was never shown.
    if (existing == null) {
      _cardOrder.insert(0, request.code);
    }
    _publishCards();
    _showToast(
      StreamScanConstants.successToastMessage,
      kind: StreamScanChipKind.success,
      autoHide: StreamScanConstants.successChipAutoHide,
    );

    // Single mode: one code counted, wait for "Chạm để quét tiếp".
    if (_awaitingSingleResult) {
      _awaitingSingleResult = false;
      _isWaitingForTap.value = true;
    }
  }

  void _handleReject(
    StreamScanRequest request,
    StreamScanResponse response,
    int totalUnaddedQuantity,
  ) {
    _vibrationService.vibrateError();
    _flash(StreamScanFrameFlash.error);

    // Stop slow network timer for completed request.
    _clearSlowTimer(request.code);

    final StreamScanCardItem? existing = _sessionCards[request.code];
    if (existing != null) {
      final int remaining = math.max(
        0,
        existing.pendingQuantity - totalUnaddedQuantity,
      );
      if (existing.hasBeenAccepted || remaining > 0) {
        // Product already in cart: keep its card at the previous quantity.
        _sessionCards[request.code] = existing.copyWith(
          pendingQuantity: remaining,
        );
      } else {
        // Never added to cart: drop the card, the toast explains why.
        _sessionCards.remove(request.code);
        _cardOrder.remove(request.code);
      }
      _publishCards();
    }

    // Rejected codes never pause single mode.
    if (_awaitingSingleResult) {
      _awaitingSingleResult = false;
      _removePauseReason(_singleModePause);
    }

    _showErrorChip(
      code: request.code,
      message: response.errorMessage ?? StreamScanConstants.defaultErrorMessage,
      quantity: totalUnaddedQuantity,
    );
  }

  /// Runs the host validator; a throwing validator lets the code through.
  String? _validate(Barcode barcode) {
    final StreamScanValidator? validator = _options.validator;
    final String? code = barcode.rawValue;
    if (validator == null || code == null || code.isEmpty) {
      return null;
    }
    try {
      return validator(code, barcode.format);
    } catch (error, stack) {
      // A broken rule must not block selling; onScan still decides.
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'smart_scanner',
          context: ErrorDescription(
            'while running StreamScanOptions.validator',
          ),
        ),
      );
      return null;
    }
  }

  /// Invalid code: red flash and toast only; no card, counter or onScan.
  void _handleInvalid(String code, String message) {
    _vibrationService.vibrateError();
    _flash(StreamScanFrameFlash.error);
    _showErrorChip(code: code, message: message, quantity: 1);
  }

  /// Shows an error toast, merging repeats of the same code and message.
  void _showErrorChip({
    required String code,
    required String message,
    required int quantity,
  }) {
    final List<StreamScanErrorChipItem> chips =
        List<StreamScanErrorChipItem>.from(_errorChips.value);
    final int existingIndex = chips.indexWhere(
      (StreamScanErrorChipItem item) =>
          item.isError && item.code == code && item.message == message,
    );

    if (existingIndex >= 0) {
      final StreamScanErrorChipItem existingChip = chips[existingIndex];
      final StreamScanErrorChipItem updatedChip = existingChip.copyWith(
        unaddedQuantity: existingChip.unaddedQuantity + quantity,
        timestamp: DateTime.now(),
      );
      chips[existingIndex] = updatedChip;
      _errorChips.value = chips;
      _scheduleChipAutoHide(updatedChip.id, _options.chipAutoHide);
    } else {
      final StreamScanErrorChipItem newChip = StreamScanErrorChipItem(
        id: '${code}_${DateTime.now().microsecondsSinceEpoch}',
        code: code,
        message: message,
        unaddedQuantity: quantity,
        timestamp: DateTime.now(),
      );
      chips.insert(0, newChip);
      _trimChipsList(chips);
      _errorChips.value = chips;
      _scheduleChipAutoHide(newChip.id, _options.chipAutoHide);
    }
  }

  /// Shows a non-error toast (info or success) as the newest chip.
  void _showToast(
    String message, {
    required StreamScanChipKind kind,
    required Duration autoHide,
  }) {
    final List<StreamScanErrorChipItem> chips =
        List<StreamScanErrorChipItem>.from(_errorChips.value);
    final StreamScanErrorChipItem chip = StreamScanErrorChipItem(
      id: '${kind.name}_${DateTime.now().microsecondsSinceEpoch}',
      code: '',
      message: message,
      unaddedQuantity: 0,
      kind: kind,
      timestamp: DateTime.now(),
    );
    chips.insert(0, chip);
    _trimChipsList(chips);
    _errorChips.value = chips;
    _scheduleChipAutoHide(chip.id, autoHide);
  }

  void _flash(StreamScanFrameFlash kind) {
    _flashTimer?.cancel();
    _frameFlash.value = kind;
    _flashTimer = Timer(StreamScanConstants.frameFlashDuration, () {
      _frameFlash.value = StreamScanFrameFlash.none;
    });
  }

  void _addPauseReason(String reason) {
    _pauseReasons.add(reason);
    _presenceTracker.pause();
  }

  void _removePauseReason(String reason) {
    _pauseReasons.remove(reason);
    if (_pauseReasons.isEmpty) {
      _presenceTracker.resume();
    }
  }

  void _scheduleChipAutoHide(String chipId, Duration duration) {
    _cancelChipTimer(chipId);
    _chipTimers[chipId] = Timer(duration, () {
      _chipTimers.remove(chipId);
      final List<StreamScanErrorChipItem> updated = _errorChips.value
          .where((StreamScanErrorChipItem item) => item.id != chipId)
          .toList();
      _errorChips.value = updated;
    });
  }

  void _cancelChipTimer(String chipId) {
    _chipTimers[chipId]?.cancel();
    _chipTimers.remove(chipId);
  }

  void _clearSlowTimer(String code) {
    _slowTimers[code]?.cancel();
    _slowTimers.remove(code);
    if (_slowTimers.isEmpty) {
      _isNetworkSlow.value = false;
    }
  }

  void _publishCards() {
    final int visible = math.min(_options.maxVisibleCards, _cardOrder.length);
    _recentCards.value = <StreamScanCardItem>[
      for (int i = 0; i < visible; i++) _sessionCards[_cardOrder[i]]!,
    ];

    int itemCount = 0;
    int totalQuantity = 0;
    for (final StreamScanCardItem card in _sessionCards.values) {
      if (card.hasBeenAccepted) {
        itemCount++;
        totalQuantity += card.acceptedQuantity;
      }
    }
    _counter.value = StreamScanCounter(
      itemCount: itemCount,
      totalQuantity: totalQuantity,
    );
  }

  void _trimChipsList(List<StreamScanErrorChipItem> list) {
    if (list.length > _options.maxVisibleChips) {
      final List<StreamScanErrorChipItem> dropped = list.sublist(
        _options.maxVisibleChips,
      );
      for (final StreamScanErrorChipItem chip in dropped) {
        _cancelChipTimer(chip.id);
      }
      list.removeRange(_options.maxVisibleChips, list.length);
    }
  }
}
