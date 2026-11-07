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

  // Every product scanned this session; order lists codes, most recent first.
  final Map<String, StreamScanCardItem> _sessionCards =
      <String, StreamScanCardItem>{};
  final List<String> _cardOrder = <String>[];

  final Map<String, Timer> _slowTimers = <String, Timer>{};
  final Map<String, Timer> _chipTimers = <String, Timer>{};

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
           dispatcher ?? StreamScanDispatcher(onScan: onScan, options: options) {
    _attachDispatcherListeners();
  }

  /// Front layers, most recently scanned first, at most `maxVisibleCards`.
  /// The full session list stays in the controller, so a product pushed out
  /// of view is still recognised when it is scanned again.
  ValueNotifier<List<StreamScanCardItem>> get recentCards => _recentCards;

  /// Listenable list of active error chips.
  ValueNotifier<List<StreamScanErrorChipItem>> get errorChips => _errorChips;

  /// Listenable boolean flag indicating slow network.
  ValueNotifier<bool> get isNetworkSlow => _isNetworkSlow;

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
  void onFrameProcessed(StreamFrameReport report) {
    final List<Barcode> barcodesToCount = _presenceTracker.processFrame(report);
    for (final Barcode barcode in barcodesToCount) {
      _dispatcher.dispatchBarcode(barcode);
    }
  }

  /// Manually dismisses an error chip by unique identifier.
  void dismissErrorChip(String id) {
    _cancelChipTimer(id);
    final List<StreamScanErrorChipItem> updated = _errorChips.value
        .where((StreamScanErrorChipItem c) => c.id != id)
        .toList();
    _errorChips.value = updated;
  }

  /// Pauses presence tracking while keeping internal state.
  void pause() => _presenceTracker.pause();

  /// Resumes presence tracking with existing states intact.
  void resume() => _presenceTracker.resume();

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

    // Detach UI listeners without cancelling background queue.
    _dispatcher.detachListeners();

    _recentCards.dispose();
    _errorChips.dispose();
    _isNetworkSlow.dispose();

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

    // Every counted scan brings its product layer to the front.
    _cardOrder.remove(request.code);
    _cardOrder.insert(0, request.code);
    _publishCards();
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
      pendingQuantity: math.max(0, base.pendingQuantity - request.quantity),
      acceptedQuantity: base.acceptedQuantity + request.quantity,
      timestamp: DateTime.now(),
    );

    // Layer order was set at scan time; only add if it was never shown.
    if (existing == null) {
      _cardOrder.insert(0, request.code);
    }
    _publishCards();
  }

  void _handleReject(
    StreamScanRequest request,
    StreamScanResponse response,
    int totalUnaddedQuantity,
  ) {
    _vibrationService.vibrateError();

    // Stop slow network timer for completed request.
    _clearSlowTimer(request.code);

    final StreamScanCardItem? existing = _sessionCards[request.code];
    if (existing != null) {
      final int remaining = math.max(
        0,
        existing.pendingQuantity - totalUnaddedQuantity,
      );
      if (existing.hasBeenAccepted || remaining > 0) {
        // Product already in cart: keep its layer at the previous quantity.
        _sessionCards[request.code] = existing.copyWith(
          pendingQuantity: remaining,
        );
      } else {
        // Never added to cart: drop the layer, the chip explains why.
        _sessionCards.remove(request.code);
        _cardOrder.remove(request.code);
      }
      _publishCards();
    }

    final String message =
        response.errorMessage ?? StreamScanConstants.defaultErrorMessage;

    final List<StreamScanErrorChipItem> chips =
        List<StreamScanErrorChipItem>.from(_errorChips.value);
    final int existingIndex = chips.indexWhere(
      (StreamScanErrorChipItem item) =>
          item.code == request.code && item.message == message,
    );

    if (existingIndex >= 0) {
      final StreamScanErrorChipItem existing = chips[existingIndex];
      final int updatedQuantity =
          existing.unaddedQuantity + totalUnaddedQuantity;
      final StreamScanErrorChipItem updatedChip = existing.copyWith(
        unaddedQuantity: updatedQuantity,
        timestamp: DateTime.now(),
      );
      chips[existingIndex] = updatedChip;
      _errorChips.value = chips;
      _scheduleChipAutoHide(updatedChip.id);
    } else {
      final String chipId =
          '${request.code}_${DateTime.now().microsecondsSinceEpoch}';
      final StreamScanErrorChipItem newChip = StreamScanErrorChipItem(
        id: chipId,
        code: request.code,
        message: message,
        unaddedQuantity: totalUnaddedQuantity,
        timestamp: DateTime.now(),
      );
      chips.insert(0, newChip);
      _trimChipsList(chips);
      _errorChips.value = chips;
      _scheduleChipAutoHide(newChip.id);
    }
  }

  void _scheduleChipAutoHide(String chipId) {
    _cancelChipTimer(chipId);
    _chipTimers[chipId] = Timer(_options.chipAutoHide, () {
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
