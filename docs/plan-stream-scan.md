# Plan: Quét barcode liên tục có gọi API (stream scan) & QR CCCD

- Thư viện: `smart_scanner` (đang ở 0.0.3, nhánh `optimize`)
- Ứng dụng dùng: easypos
- Ngày lập: 2026-11-07 · Cập nhật vòng review 2: 2026-11-07 (xem mục 11.3)
- Thứ tự ưu tiên: **Barcode stream (0.1.0)**, sau đó **QR CCCD (0.2.0)**

---

## 1. Mục tiêu & phạm vi

**Mục tiêu**
1. **Barcode stream**: quét liên tục, mỗi lượt quét được báo realtime về easypos qua callback. easypos tự tra cache hoặc gọi API rồi tự thêm vào giỏ, sau đó trả lời lại cho thư viện. Thư viện hiển thị chip lỗi hoặc card thành công và rung phản hồi.
2. **QR CCCD**: đọc QR trên CCCD và trả dữ liệu đã parse về Flutter. Làm sau khi xong mục 1.
3. Chạy ổn trên Android yếu (từ 3GB RAM).

**Ngoài phạm vi**
- Thư viện **không** giữ giỏ hàng, không cache sản phẩm và không tự gọi API.
- Không sửa hành vi của các luồng hiện có (xem mục 2).
- Không thêm thư viện quản lý state bên thứ ba (GetX, Provider, Bloc, ...) vào package.

---

## 2. Ràng buộc bất biến: không thay đổi hành vi hiện tại

Các luồng hiện có đang được các tính năng khác của easypos dùng. **Hành vi hiện tại** gồm:

| Nhóm | Phải giữ nguyên |
|---|---|
| API public | `SmartScanner.scan / scanQR / scanBarcode / scanBasic / warmUp / hasCamera / vibrateOnScan / setVibrateOnScan`, `SmartScannerResult`. Các widget đang export: `CustomBarcodeScanner`, `BarcodeOverlayPainter`, `ScannerOverlay`, `SmartScannerScreen`, `SmartScannerVibrationSwitch`, `calculateScanWindow`. Chữ ký và **giá trị mặc định** không đổi. |
| Dependency | Không thêm dependency mới vào `pubspec.yaml` nếu không bắt buộc. Mỗi dependency mới ảnh hưởng tới việc resolve package của mọi app dùng thư viện. |
| Thông số camera/decode | 720p (`ResolutionPreset.high`); fps 24 trên iOS, 30 trên Android; NV21 kèm fallback YUV; decode 200ms khi hoạt động, 500ms khi nghỉ; ngưỡng nghỉ 1,5s; tự tạm dừng sau 60s; crop đệm 30%; dung sai lọc khung 20% |
| Multi-scan cũ | Debounce 1200ms; mã giữ trong khung vẫn +1 sau mỗi 1,2s; khóa xử lý 500ms; `incrementOnDuplicate` |
| UI | Toàn bộ giao diện, chữ, animation, rung của `SmartScannerScreen` và `CustomBarcodeScanner` |

**Quy tắc áp dụng**
1. Với code hiện có **chỉ được thêm**. Mọi tham số mới đều là optional, có giá trị mặc định bằng đúng hành vi cũ.
2. **Không sửa** các file: `smart_scanner_page.dart`, `barcode_processor_usecase.dart`, `scanner_controller.dart`, `scanner_bottom_sheet.dart`.
3. Không được đổi expectation của bất kỳ test hiện có nào. Mọi test hiện có phải pass **mà không phải chỉnh sửa gì**.
4. Mọi thay đổi trên file dùng chung (mục 6) phải có test hoặc checklist chứng minh nhánh mặc định không đổi.
5. Các tối ưu hiệu năng (Phase 2) chỉ bật cho luồng mới, hoặc khi nơi gọi chủ động truyền tham số.

---

## 3. Nguyên tắc kỹ thuật code

- **Kiến trúc & phân tầng**: Clean Architecture (`domain` / `data` / `presentation`). **Không dùng GetX** (chốt D6).
  - `domain`: entities, requests, responses, options, usecases thuần Dart (không phụ thuộc UI/Flutter widget).
  - `data`: services xử lý phần cứng/bên thứ ba (camera, ML Kit, ZXing, rung).
  - `presentation`: controllers (`ChangeNotifier`), pages, components.
- **Quy ước đặt tên, cấu trúc file, export public**:
  - Đặt tên file và class theo công thức `<tên_tính_năng>_<vai_trò>`: `..._controller`, `..._page`, `..._component`, `..._request`, `..._response`, `..._usecase`, `..._service`, `..._constants`.
  - Chỉ export ra `lib/smart_scanner.dart` các class/hàm thuộc API public của tính năng mới.
- **Quản lý state & rebuild**:
  - Chỉ dùng công cụ có sẵn của Flutter SDK: `ChangeNotifier`, `ValueNotifier`, `ValueListenableBuilder` / `ListenableBuilder`. Package hiện có (`ScannerController`, `vibrateOnScan`) cũng đang dùng các công cụ này.
  - **Tách bạch vòng đời UI và hàng đợi nền**: `StreamScanController` (`ChangeNotifier`) quản lý state hiển thị và được `dispose()` khi đóng màn hình. `StreamScanDispatcher` (điều phối lời gọi `onScan`) sống độc lập cho đến khi xử lý hết các lượt quét còn trong hàng đợi.
- **Hiệu năng**:
  - Không cấp phát đối tượng thừa trong vòng lặp xử lý frame.
  - Mỗi vùng UI động (card thành công, chip lỗi, chỉ báo mạng chậm) được tách thành `..._component` riêng, bọc trong `RepaintBoundary` + `ValueListenableBuilder`, đặt làm phần tử anh em trong `Stack`. Tuyệt đối không đặt vào `overlayBuilder` của `CustomBarcodeScanner`.
  - Tận dụng tối đa `const` constructor.
- **Test**:
  - Đặt unit test và widget test vào thư mục riêng theo từng tính năng (`test/stream_scan/`, `test/citizen_id_scan/`).
  - Dùng fake clock cho các logic phụ thuộc thời gian (`slowHintAfter`, `chipAutoHide`).
- **Tài liệu**:
  - Viết `README.md` và `CHANGELOG.md` đầy đủ, rõ ràng cho từng bản phát hành.
  - Viết dartdoc cho toàn bộ API public.
- **Syntax & Comment**:
  - **Không hardcode** (màu sắc, kích thước, thời gian, chuỗi thông báo mặc định phải đưa vào file `..._constants.dart` hoặc `..._options.dart`), trừ trường hợp bất khả kháng.
  - Khai báo `final` **bắt buộc kèm kiểu dữ liệu tường minh** (ví dụ: `final String code = req.code;`, không viết `final code = req.code;`).
  - Quy tắc comment: comment một dòng (`//`) **không quá 16 từ**; comment tài liệu (`///`) **không quá 3 dòng** (ngoại lệ cho API public chính: chờ chốt D9).

---

## 4. Chiến lược tái sử dụng

| Thành phần hiện có | File | Dùng trong luồng mới | Có sửa không |
|---|---|---|---|
| `CameraService` (vòng đời, zoom, torch, focus, khóa dispose) | `data/services/camera_service.dart` | Dùng nguyên, đi kèm qua `CustomBarcodeScanner` | Không ở Phase 1. Phase 2: thêm tham số optional `fps`. Phase 4: thêm `initialZoom`. Cả hai đều có mặc định giữ nguyên hành vi cũ. |
| `BarcodeScannerService` (NV21, crop khung, rung/mờ/lóa, lọc và sắp xếp) | `data/services/barcode_scanner_service.dart` | Dùng nguyên | Không |
| `CustomBarcodeScanner` (preview, giới hạn tần suất decode, lấy nét, xử lý lỗi quyền, vòng đời, tự tạm dừng) | `presentation/widgets/custom_barcode_scanner.dart` | Dùng nguyên, với `formats` barcode 1D | **Thêm** tham số tùy chọn `onFrameProcessed` (Phase 1), `initialZoom` (Phase 4) |
| `calculateScanWindow` | `presentation/pages/smart_scanner_page.dart` | Gọi với `isQRMode: false` | Không |
| `ScannerOverlay`, `ScannerTopBar` | `presentation/widgets/*` | Dùng nguyên. `StreamScanPage` không gắn `ScannerControlsRow` vì không có nút bật/tắt multi-scan (widget này trả `SizedBox.shrink()` khi `showMultiScanToggle: false`). | Không |
| Cài đặt rung `SmartScanner.vibrateOnScan` | `smart_scanner.dart` | Đọc và tôn trọng cài đặt | Không |
| `BarcodeProcessorUseCase`, `ScannerController`, `ScannerBottomSheet` | — | **Không dùng.** Mô hình khác: số lượng do easypos quản lý, đếm theo kiểu rời khung | Không |

**Xử lý phần rung & decode ảnh thư viện mà không chạm vào `smart_scanner_page.dart` (chốt D2)**:
- Giữ nguyên `smart_scanner_page.dart` (tuân thủ tuyệt đối mục 2.2).
- Tạo mới `StreamVibrationService` (`data/services/stream_vibration_service.dart`) hỗ trợ rung 1 nhịp (thành công 70ms) và rung 2 nhịp (báo lỗi).
- Tạo mới `GalleryDecodeService` (`data/services/gallery_decode_service.dart`) ở Phase 4 hỗ trợ trả về cả `text` lẫn `rawBytes` từ ZXing/ML Kit để phục vụ giải mã tiếng Việt trên QR CCCD.

---

## 5. Thiết kế luồng Barcode Stream

### 5.1 API public (chỉ thêm mới)

```dart
final StreamScanSession session = await SmartScanner.scanStream(
  context,
  onScan: (StreamScanRequest req) async {
    // easypos tự quyết định: tra cache hay gọi API, có timeout riêng
    final Product? p = posCache[req.code] ?? await api.findByBarcode(req.code);
    if (p == null) {
      return StreamScanResponse.reject('Không tìm thấy sản phẩm');
    }
    final String? err = cart.add(p, req.quantity);
    return err != null
        ? StreamScanResponse.reject(err)
        : StreamScanResponse.accept(
            title: p.name,
            subtitle: p.price,
            totalInCart: cart.qtyOf(p),
          );
  },
  options: const StreamScanOptions(),
  enableVibration: null,
  successItemBuilder: null,
  errorChipBuilder: null,
);
// Tùy chọn: chờ hàng đợi nền xử lý xong trước khi chuyển sang bước thanh toán
final StreamScanSummary summary = await session.drained;
```

**Các model** (typedef tên ngắn `ScanRequest` / `ScanAck`: chờ chốt D8)
- `StreamScanRequest { final String code; final BarcodeFormat format; final int quantity; }`
  - `quantity` ≥ 1, là số lượt đã được gộp lại.
- `StreamScanResponse.accept({String? title, String? subtitle, int? totalInCart})`
- `StreamScanResponse.reject(String message)`: không có cờ `retryable`, vì không còn nút "Thử lại" (chốt D7).
- `StreamScanSession { final Future<StreamScanSummary> drained; }`: hoàn tất khi lời gọi `onScan` cuối cùng kết thúc.
- `StreamScanSummary { final int acceptedQuantity; final int notAddedQuantity; }`: chỉ có giá trị cuối cùng sau khi hàng đợi đã xử lý xong.
- `StreamFrameReport { final List<Barcode> barcodes; final bool isBlurry; final bool hasGlare; final bool isMoving; }`

### 5.2 Pipeline

```
CameraImage
  -> CustomBarcodeScanner (giới hạn tần suất decode, crop, ML Kit, lọc khung)    [có sẵn]
  -> onFrameProcessed(StreamFrameReport: barcodes + isBlurry/hasGlare/isMoving)  [hook mới]
  -> StreamPresenceTrackerUseCase : RescanPolicy.leaveFrame -> "đếm 1 lượt"      [mới - domain]
  -> StreamScanDispatcher         : tuần tự theo mã, gộp lượt, giới hạn song song[mới - domain]
  -> onScan(StreamScanRequest)    : callback của easypos
  -> StreamScanResponse           -> StreamScanController (ChangeNotifier/ValueNotifier) [mới - presentation]
                                  -> Component (Card / Chip) + Rung
```

### 5.3 Quy tắc đếm: `RescanPolicy.leaveFrame` (`StreamPresenceTrackerUseCase`)

Ý tưởng: một mã chỉ được đếm thêm khi nó đã thật sự rời khung rồi xuất hiện lại.

1. Chỉ xét **các frame thật sự được decode**. Frame bị bỏ qua do giới hạn tần suất thì không tính.
2. **Bước cập nhật sự hiện diện**: mọi mã **đang có mặt** mà xuất hiện trong `report.barcodes` đều được đặt `missedFrames = 0`.
3. **Bước đếm lượt mới**:
   - Từ `report.barcodes` (đã được `filterAndSortBarcodes` sắp xếp theo khoảng cách tới tâm), lấy các mã **chưa có mặt**: xuất hiện lần đầu, hoặc xuất hiện lại sau khi đã bị đánh dấu "vắng".
   - Tối đa `maxCodesPerFrame` (mặc định `1`) mã mới gần tâm nhất được đánh dấu "có mặt" và phát sự kiện **đếm 1 lượt**.
   - **Các mã mới còn lại trong cùng frame cũng được đánh dấu "có mặt" nhưng KHÔNG đếm.** Muốn được đếm, chúng phải rời khung rồi vào lại.
     - Ví dụ bao bì có cả EAN lẫn mã nội bộ nằm sát nhau: frame 1 đếm mã A, mã B được đánh dấu có mặt luôn. Sang frame 2, dù B đứng gần tâm hơn thì B cũng không bị đếm.
   - Mã đang ở trạng thái "có mặt": không đếm thêm, dù giữ trong khung bao lâu.
4. **Bước đánh dấu "vắng"**:
   - Mã đang có mặt nhưng không xuất hiện trong `report.barcodes` thì `missedFrames++`. Khi `missedFrames >= N` thì mã bị đánh dấu "vắng".
   - Tùy chọn `ignoreBlurryOrGlareMisses` (**mặc định `false`**):
     - Khi bật, frame rỗng có `isBlurry || hasGlare` không làm tăng `missedFrames`.
     - Nhưng chỉ được bỏ qua **tối đa `maxIgnoredMisses` (K = 2) frame liên tiếp**. Từ frame thứ K+1 trở đi vẫn tính là vắng.
     - Chỉ bật sau khi số liệu Phase 0 chứng minh là cần (lý do ở mục 11.3, điểm 1).
5. Mặc định tạm thời **N = 2**, tương đương khoảng 400ms trên máy khỏe và khoảng 600ms trên máy yếu. Giá trị cuối cùng chốt sau phép đo ở Phase 0.
6. Trạng thái "có mặt/vắng" được **giữ nguyên qua pause/resume và tự tạm dừng**. Nhờ vậy mã đang nằm sẵn trong khung lúc resume không bị đếm thêm.

### 5.4 Điều phối lời gọi `onScan` (`StreamScanDispatcher`)

| Sự kiện | Trạng thái của mã X | Hành động |
|---|---|---|
| Đếm 1 lượt | Rảnh | Gọi `onScan(X, quantity: 1)`. Layer của X **lên đầu ngay lúc quét** (mã mới thì thêm layer), hiện "+1 đang xử lý" |
| Đếm 1 lượt | Đang có lời gọi chạy | `queued++`, **không gọi song song**. Layer của X lên đầu, hiện "+n đang xử lý" |
| `accept` trả về | — | Layer cập nhật title và số lượng (`totalInCart`, nếu không có thì dùng số lượt đã accept trong phiên), rung 1 nhịp. Nếu `queued > 0` thì lấy `q = queued`, đặt `queued = 0` và gọi tiếp `onScan(X, quantity: q)` |
| `reject` trả về | — | Rung 2 nhịp. Các lượt đang chờ của X bị **huỷ** (không gửi). Hiện chip: **"⚠ {message} · {req.quantity + queued} SP {X/title} chưa thêm vào giỏ, hãy quét lại"**. Layer: X **đã từng được accept** thì giữ nguyên ở số lượng cũ; X chưa từng được accept thì xoá layer (chốt D11) |
| `reject` trùng mã và trùng message với một chip đang hiển thị | — | Cộng dồn số lượng vào chip đó và đặt lại thời gian ẩn, không tạo chip mới |
| `onScan` ném exception | — | Coi như `reject('Có lỗi xảy ra')` và gọi `FlutterError.reportError` |
| Thu ngân quét lại X sau khi bị reject | — | Xử lý như một lượt bình thường. **Không có cooldown**, vì chip đang yêu cầu quét lại |
| Nhiều mã khác nhau | — | Tối đa `maxConcurrent` lời gọi chạy song song, phần còn lại xếp hàng FIFO |

**Nguyên tắc nhất quán dữ liệu & vòng đời**
- **Không có nút "Thử lại"** (chốt D7).
  - Quy tắc duy nhất: mỗi lần quét thành công là +1; chip lỗi nghĩa là các sản phẩm đó chưa vào giỏ.
  - Nếu có nút "Thử lại", thư viện không phân biệt được thu ngân đang quét lại đúng sản phẩm bị lỗi hay một sản phẩm khác cùng mã, nên dễ đếm thừa hoặc thiếu (mục 11.3, điểm 4).
- **Thư viện không tự đặt timeout cho `onScan`.**
  - Nếu thư viện báo lỗi trong khi easypos vẫn thêm hàng vào giỏ, UI và giỏ sẽ lệch nhau. Vì vậy timeout là trách nhiệm của easypos.
  - Thư viện chỉ hiện chỉ báo "mạng chậm" khi một lời gọi quá `slowHintAfter`, nhưng vẫn chờ kết quả thật.
- **Đóng màn hình** (Hoàn tất hoặc Back) lúc vẫn còn lời gọi đang chạy hay đang xếp hàng:
  - `StreamScanController.dispose()` huỷ các timer hiển thị UI (`chipAutoHide`, `slowHintAfter`) và ngắt kết nối UI khỏi dispatcher.
  - `StreamScanDispatcher` **vẫn xử lý hết hàng đợi** ở nền rồi hoàn tất `session.drained`. Không mất lượt quét nào và không có lần cập nhật nào vào notifier đã dispose.
  - Hợp đồng ghi trong dartdoc: `onScan` không được phụ thuộc vào `BuildContext` của màn hình quét.

### 5.5 `StreamScanOptions`: giá trị mặc định đề xuất

| Tham số | Mặc định | Ghi chú |
|---|---|---|
| `rescanPolicy` | `RescanPolicy.leaveFrame(missedFrames: 2, ignoreBlurryOrGlareMisses: false, maxIgnoredMisses: 2)` | Chốt sau Phase 0 |
| `maxCodesPerFrame` | 1 | Đã chốt D1 |
| `maxConcurrent` | 2 | |
| `slowHintAfter` | 3s | Chỉ để hiển thị chỉ báo mạng chậm |
| `maxVisibleCards` | 3 | Số card thành công/đang xử lý hiển thị gần nhất |
| `maxVisibleChips` | 3 | Số chip lỗi hiển thị tối đa cùng lúc |
| `chipAutoHide` | 5s | Để thu ngân kịp đọc chip "chưa thêm vào giỏ" |

### 5.6 UI & hiệu năng render (ValueNotifier + RepaintBoundary)

- Layout dùng `ScannerOverlay` và `ScannerTopBar` có sẵn. Chip lỗi và các layer sản phẩm đặt phía trên khu vực đáy, không che khung quét.
- **Layer sản phẩm** (chốt D11, cùng kiểu xếp với multi-scan cũ):
  - Tối đa `maxVisibleCards` (mặc định 3) layer. Layer **mới quét nhất ở trước** và cố định ở đáy; các layer cũ hơn ló lên phía trên (`layerOffsetY`) và thu hẹp dần (`layerInsetX`).
  - `AnimatedPositioned` có key theo mã, nên khi quét lại thì layer trượt lên trước.
  - Controller giữ **toàn bộ** sản phẩm đã quét trong phiên, chỉ vẽ các layer trên cùng. Sản phẩm đã bị đẩy khỏi phần hiển thị khi quét lại vẫn được nhận là "đã có" và hiện đúng số lượng.
  - Thư viện **không tự cộng số lượng vào giỏ**; số trên layer lấy từ `totalInCart` của easypos.
  - Mỗi layer có chiều cao cố định (`layerCardHeight`). `cardBuilder` chỉ vẽ nội dung bên trong một layer.
- **Không** đưa danh sách card/chip vào `overlayBuilder` của `CustomBarcodeScanner`. Chúng nằm thành các phần tử anh em trong `Stack`, mỗi vùng là một component riêng bọc `RepaintBoundary` + `ValueListenableBuilder`:
  - `StreamScanResultCardComponent`: lắng nghe `controller.recentCards` (`ValueListenable<List<StreamScanCardItem>>`, xếp theo thứ tự mới quét nhất trước).
  - `StreamScanErrorChipComponent`: lắng nghe `controller.errorChips` (`ValueListenable<List<StreamScanErrorChipItem>>`).
  - `StreamScanSlowNetworkComponent`: lắng nghe `controller.isNetworkSlow` (`ValueListenable<bool>`).
- Không dùng `AnimatedBuilder` hay builder nào bọc cả màn hình. Hạn chế `BoxShadow` có `blurRadius` lớn.
- Rung (`StreamVibrationService`):
  - Thành công: 1 nhịp (70ms trên Android).
  - Lỗi: 2 nhịp (70ms - nghỉ 80ms - 70ms trên Android, hoặc double heavyImpact trên iOS).
  - Theo `enableVibration`, nếu `null` thì theo `SmartScanner.vibrateOnScan`.

---

## 6. Danh sách thay đổi trên file hiện có & cấu trúc file mới

### 6.1 Thay đổi trên file hiện có (chỉ thêm)

| File | Thay đổi | Đảm bảo không đổi hành vi |
|---|---|---|
| `pubspec.yaml` | Chỉ nâng version lên `0.1.0`. **Không thêm dependency.** | — |
| `lib/src/presentation/widgets/custom_barcode_scanner.dart` | Phase 1: thêm `final void Function(StreamFrameReport report)? onFrameProcessed;` (mặc định `null`). Hook này được gọi sau bước `filterAndSortBarcodes` cho **mọi** frame đã decode, kể cả frame rỗng, và đặt sau logic hiện có. | Khi `null` thì không có lệnh nào chạy thêm; thứ tự gọi `onDetect` và `setState` giữ nguyên |
| `lib/src/smart_scanner.dart` | Thêm `static Future<StreamScanSession> scanStream(...)` | Không động vào các method cũ |
| `lib/smart_scanner.dart` | Thêm export cho API mới (`StreamScanRequest`, `StreamScanResponse`, `StreamScanOptions`, `RescanPolicy`, `StreamScanSession`, `StreamScanSummary`, `StreamScanPage`) | Giữ nguyên các export cũ |
| `CHANGELOG.md`, `README.md` | 0.1.0, bổ sung hướng dẫn đầy đủ cho `scanStream` | — |
| *(Phase 2, chỉ khi cần)* `custom_barcode_scanner.dart`, `camera_service.dart` | Tham số tùy chọn: `autoPauseAfter` (mặc định 60s), `activeDecodeInterval` / `idleDecodeInterval` (mặc định 200/500ms), `fps` (mặc định 24 iOS / 30 Android) | Mặc định bằng đúng hằng số hiện tại |
| *(Phase 4)* `custom_barcode_scanner.dart`, `camera_service.dart` | Thêm `initialZoom` (mặc định `null`), chi tiết ở 7/Phase 4. | `null` thì dùng `CameraService.defaultZoomLevel` như hiện tại |

### 6.2 File mới (theo Clean Architecture & quy ước đặt tên Mục 3)

```text
lib/src/
  core/
    constants/
      stream_scan_constants.dart                         // Toàn bộ hằng số thời gian, kích thước, màu sắc, text mặc định
  domain/
    entities/
      stream_frame_report.dart                           // StreamFrameReport (barcodes, isBlurry, hasGlare, isMoving)
      stream_scan_request.dart                           // StreamScanRequest
      stream_scan_response.dart                          // StreamScanResponse, StreamScanSession, StreamScanSummary
      stream_scan_options.dart                           // StreamScanOptions, RescanPolicy
    usecases/
      stream_presence_tracker_usecase.dart               // Logic leaveFrame, thuần Dart
      stream_scan_dispatcher.dart                        // Tuần tự theo mã, gộp lượt, giới hạn song song, drain nền (tên: chờ chốt D10)
  data/
    services/
      stream_vibration_service.dart                      // Rung 1 nhịp (accept) & 2 nhịp (reject)
  presentation/
    controllers/
      stream_scan_controller.dart                        // ChangeNotifier + các ValueNotifier cho UI (vị trí thư mục: chờ chốt D10)
    pages/
      stream_scan_page.dart                              // Màn hình quét barcode stream
    components/
      stream_scan_result_card_component.dart             // Card hiển thị các mã đang xử lý / thành công
      stream_scan_error_chip_component.dart              // Chip "chưa thêm vào giỏ, hãy quét lại"
      stream_scan_slow_network_component.dart            // Chỉ báo mạng chậm

test/
  stream_scan/
    stream_presence_tracker_usecase_test.dart
    stream_scan_dispatcher_test.dart
    stream_scan_controller_test.dart
    stream_scan_components_test.dart
```

---

## 7. Các phase

### Phase 0: Đo baseline (1–1,5 ngày)
- [ ] Ghi lại checklist hồi quy (mục 8.3) trên các luồng hiện có của easypos để làm mốc so sánh.
- [ ] Viết công cụ đo **chỉ cho luồng mới / debug**, móc qua `onFrameProcessed`, không chạm đường code cũ. Các chỉ số: chu kỳ decode thực tế, số lần decode mỗi giây, tỉ lệ frame bật `isBlurry` / `hasGlare`.
- [ ] Đo trên máy tham chiếu 3GB:
  - Tỉ lệ ML Kit bỏ sót khi giữ yên và khi di chuyển sản phẩm.
  - Khoảng thời gian mã biến mất khi thu ngân đổi giữa hai sản phẩm cùng mã.
  - **Tỉ lệ bật `isBlurry`/`hasGlare` trong 3 tình huống**: khung chỉ có mặt quầy (nhiều loại mặt quầy), đang đổi hàng, và sản phẩm giữ yên dưới đèn. Số liệu này dùng để quyết định có bật `ignoreBlurryOrGlareMisses` hay không.
  - Bộ nhớ (PSS), độ giật (`gfxinfo`), nhiệt độ sau 10 phút quét.
- **Kết quả cần có:** chốt N (`missedFrames`), có bật `ignoreBlurryOrGlareMisses` hay không, `maxConcurrent`, cùng bộ số liệu baseline.

### Phase 1: Barcode stream lõi (5–7 ngày)
- [ ] 1a. Viết `stream_scan_constants.dart`, các entity/request/response, `RescanPolicy`, `StreamPresenceTrackerUseCase`, `StreamScanDispatcher` thuần Dart (tuân thủ khai báo kiểu tường minh cho `final` và quy tắc comment), kèm unit test trong `test/stream_scan/`. (2 ngày)
- [ ] 1b. Thêm hook `onFrameProcessed` vào `CustomBarcodeScanner` và viết test đảm bảo nhánh mặc định không đổi. (0,5 ngày)
- [ ] 1c. Viết `StreamVibrationService`, `StreamScanController` (`ChangeNotifier`), `StreamScanPage`, các `..._component.dart` và `SmartScanner.scanStream`. (2–3 ngày)
- [ ] 1d. Thêm màn demo vào app ví dụ, viết widget test cho các component, viết dartdoc và cập nhật `README.md`. (1 ngày)
- **Tiêu chí hoàn thành:**
  - Không có lời gọi `onScan` song song cho cùng một mã.
  - Giữ mã yên 10s (kể cả trên bao bì có 2 mã cạnh nhau) chỉ đếm 1 lượt.
  - Đổi 5 sản phẩm cùng mã thì đếm đủ 5, kể cả khi mặt quầy trơn một màu.
  - Không có frame trễ >32ms khi đang hiện chip.
  - `pubspec.yaml` không thêm dependency mới.
  - Toàn bộ test cũ pass mà không phải sửa.

### Phase 2: Tối ưu cho máy yếu (3–4 ngày, chỉ áp dụng cho luồng mới)
- [ ] Tự chọn cấu hình theo RAM máy (`isLowRamDevice` / totalMem). Package hiện chưa có thư mục `android/`. Ưu tiên thêm plugin class Kotlin nhỏ, vì cách này không cần thêm dependency (mục 2).
- [ ] Thử 20fps với fallback về 30; tần suất decode theo profile; tắt tự tạm dừng ở luồng stream (quầy POS).
- [ ] Đo lại và so với baseline.
- **Tiêu chí hoàn thành:** thời gian từ lúc mã vào khung đến khi gọi `onScan` có p90 ≤500ms; PSS ổn định trong 10 phút; không bị hạ xung vì nhiệt.

### Phase 3: Tích hợp easypos & phát hành 0.1.0 (3–5 ngày)
- [ ] easypos tích hợp `scanStream`, tự viết `onScan` dùng cache hoặc API (có timeout riêng), `await session.drained` trước khi thanh toán.
- [ ] Chạy thử 1 ca bán hàng thực tế; thu log timestamp lúc mã rời khung và xuất hiện lại để tinh chỉnh N.
- [ ] Chạy lại toàn bộ checklist hồi quy (8.3) trên easypos.
- [ ] Hoàn thiện `README.md`, `CHANGELOG.md`, tag `0.1.0`.

### Phase 4: QR CCCD, phát hành 0.2.0 (4–5 ngày)
- [ ] Spike:
  - `rawBytes` của ML Kit trên Android/iOS trả về payload hay toàn bộ codewords.
  - Lỗi bảng mã tiếng Việt (UTF-8 / Windows-1258 / TCVN3).
  - Định dạng QR trên thẻ CCCD gắn chip 2021 (7 trường ngăn bởi `|`) và thẻ Căn cước 2024 (cần thẻ thật).
- [ ] `CitizenIdParserUseCase` thuần Dart, có unit test trong `test/citizen_id_scan/`; model `CitizenIdResponse`.
- [ ] `CitizenIdScanPage` + `CitizenIdScanController` (`ChangeNotifier`) dùng lại `CustomBarcodeScanner` với `formats: const [BarcodeFormat.qrCode]` và `initialZoom: 2.0`.
  - `initialZoom` phải được truyền xuống tận `CameraService` (`initializeCamera` → `_applyDefaultZoom`).
  - Áp dụng lại **mỗi lần camera khởi tạo lại** (resume, tự tạm dừng, quay về từ nền).
  - Khi `initialZoom` khác `null`, mốc zoom của thao tác chạm đúp đổi từ `defaultZoomLevel` sang `initialZoom`. Khi `null` thì giữ nguyên như hiện tại.
  - Gặp QR không phải CCCD: hiện chip lỗi (`CitizenIdErrorChipComponent`) và không đóng màn hình.
  - Thành công: dừng camera ngay và trả kết quả.
- [ ] Chọn ảnh từ thư viện: dùng `GalleryDecodeService` (trả về cả `text` và `rawBytes` từ ZXing/ML Kit).
- [ ] Bảo mật dữ liệu cá nhân: tuyệt đối không `debugPrint`/log giá trị CCCD, không lưu xuống bộ nhớ máy.

### Phase 5 (tùy chọn): chỉ làm nếu Phase 2 chưa đạt mục tiêu
- Chuyển phần phân tích ảnh xuống native Android (CameraX `ImageAnalysis` + ML Kit viết bằng Kotlin, chỉ gửi kết quả lên Dart), hoặc làm widget nhúng `SmartScannerView`. Ước tính 2–3 tuần.

---

## 8. Kiểm thử

### 8.1 Unit test & Widget test (bắt buộc cho logic mới, đặt tại `test/stream_scan/`)
- `StreamPresenceTrackerUseCase`:
  - Lần xuất hiện đầu được đếm.
  - Giữ yên thì không đếm thêm.
  - **2 mã mới cùng xuất hiện trong một frame**: chỉ mã gần tâm được đếm; mã còn lại được đánh dấu có mặt và không bị đếm ở các frame sau, kể cả khi nó trở thành mã gần tâm nhất.
  - Bỏ sót N−1 frame không làm đếm thêm; vắng ≥ N frame rồi xuất hiện lại thì đếm.
  - `ignoreBlurryOrGlareMisses = false` (mặc định): frame rỗng bị mờ/lóa vẫn tính là vắng.
  - `ignoreBlurryOrGlareMisses = true`: bỏ qua tối đa K frame mờ/lóa liên tiếp, từ frame thứ K+1 vẫn tính là vắng (không bao giờ kẹt ở trạng thái "có mặt").
  - Trạng thái giữ nguyên qua pause/resume.
- `StreamScanDispatcher`:
  - Tuần tự theo từng mã và gộp `quantity`.
  - Giới hạn `maxConcurrent` và thứ tự FIFO.
  - `reject` huỷ các lượt đang chờ; chip ghi đúng tổng số lượng chưa thêm (`req.quantity + queued`).
  - Reject trùng mã và trùng message thì cộng dồn vào chip đang hiển thị.
  - Quét lại ngay sau `reject` được xử lý như một lượt bình thường (không có cooldown).
  - Exception trong `onScan` được chuyển thành `reject`.
  - `StreamScanController.dispose()` không làm đứt hàng đợi; `drained` hoàn tất sau khi mọi lời gọi kết thúc, và `StreamScanSummary` có số liệu đúng.

### 8.2 Test cũ
Toàn bộ test hiện có trong `test/` phải pass mà **không phải sửa gì**: `barcode_orientation`, `barcode_processor_usecase`, `nv21`, `scan_window_geometry`, `scanner_controller`, `scanner_controls`.

### 8.3 Checklist hồi quy thủ công cho luồng cũ (chạy ở Phase 0 và Phase 3)
- [ ] `scanBarcode` single: quét được, overlay hoàn tất, trả `SmartScannerResult.single`
- [ ] `scanQR` single + chọn ảnh từ thư viện (ZXing, fallback ML Kit)
- [ ] Multi-scan: +1 khi giữ mã quá 1,2s; `incrementOnDuplicate=false`; trả kết quả khi bấm Hoàn tất
- [ ] `scanBasic` với các builder tùy biến
- [ ] Torch, zoom (nút bấm, chụm hai ngón, chạm đúp), chạm để lấy nét
- [ ] Tự tạm dừng sau 60s và chạm để tiếp tục
- [ ] Từ chối quyền camera, mở Cài đặt rồi quay lại
- [ ] Đưa app xuống nền rồi mở lại, đóng/mở màn hình quét liên tục
- [ ] Bật/tắt rung (`SmartScannerVibrationSwitch`)

### 8.4 Thiết bị test
1 máy Android tham chiếu 3GB · 1 máy Android tầm trung · 1 iPhone.

---

## 9. Rủi ro

| Rủi ro | Giảm thiểu |
|---|---|
| ML Kit bỏ sót nhiều frame liên tiếp (lóa, mờ) dẫn tới đếm thừa | Đo ở Phase 0; tăng N nếu cần; chỉ bật `ignoreBlurryOrGlareMisses` (có giới hạn K) khi số liệu chứng minh |
| **Đếm thiếu**: mã kẹt ở trạng thái "có mặt" khi mặt quầy trơn, đang đổi hàng hoặc có đèn chiếu | Mặc định không bỏ qua frame mờ/lóa; khi bật thì có giới hạn K; tiêu chí Phase 1 có test trên mặt quầy trơn |
| Bao bì có 2 mã vạch cạnh nhau gây đếm thêm mã phụ | Mã mới không được đếm vẫn được đánh dấu "có mặt" ngay trong frame đó (5.3 bước 3) |
| Thu ngân đổi hàng nhanh hơn ngưỡng dẫn tới sót lượt | Rung báo mỗi lượt được đếm; thu log khi test thực tế để tinh chỉnh N |
| Thu ngân bỏ qua chip lỗi, không quét lại, làm thiếu hàng trong giỏ | Rung 2 nhịp khác hẳn rung thành công; chip ghi rõ số lượng chưa thêm; chip giữ 5s |
| `onScan` của easypos treo do không có timeout | Ghi rõ trong hợp đồng dartdoc; hiện chỉ báo "mạng chậm" (`StreamScanSlowNetworkComponent`) |
| Đóng màn hình sớm làm mất lượt quét đang chờ | Vòng đời `StreamScanDispatcher` tách khỏi `StreamScanController`; easypos `await session.drained` |
| Hook mới trong `CustomBarcodeScanner` vô tình đổi thứ tự xử lý | Đặt hook sau logic cũ; nhánh `null` không chạy gì thêm; review riêng diff của file này |

---

## 10. Quyết định cần chốt

| # | Câu hỏi | Đề xuất | Chốt |
|---|---|---|---|
| D1 | Mỗi frame đếm tối đa bao nhiêu mã (`maxCodesPerFrame`)? | 1 (mã mới không được đếm vẫn được đánh dấu "có mặt") | **Đã chốt: 1** |
| D2 | Có sửa `smart_scanner_page.dart` để tách `_vibrateAndroid` / `_decodeGalleryBarcodes` không? | Không sửa; tạo `StreamVibrationService` và `GalleryDecodeService` riêng ở `data/services/` | **Đã chốt: Tạo service riêng, giữ nguyên file cũ** |
| D3 | `missedFrames` (N) | 2 tạm thời, chốt sau Phase 0 | **Đã chốt: 2 (tinh chỉnh sau Phase 0)** |
| D4 | Bấm Hoàn tất khi còn lời gọi đang chạy: đóng ngay hay chờ? | Đóng ngay, xử lý tiếp ở nền, trả `session.drained` | **Đã chốt: Đóng ngay + `drained`** |
| D5 | Máy Android tham chiếu 3GB cụ thể là máy nào? | Cần xác định model thiết bị thật để chạy Phase 0 | **Đã chốt: Redmi Note 15** (`2510DRA23E`, Android 15 / API 35, MediaTek MT6789 8 nhân, RAM ~5,5GB). Máy này mạnh hơn mức mục tiêu 3GB nên: kết quả kiểm thử chức năng và các phép đo hành vi ở Phase 0 (N, tỉ lệ ML Kit bỏ sót, cờ mờ/lóa, thời gian đổi hàng) dùng được; còn số liệu hiệu năng (thời gian decode, PSS, nhiệt) sẽ **lạc quan hơn** so với máy 3GB thật. Swan 2 (`I24D02`) không có camera nên không dùng. |
| D6 | Dùng GetX trong thư viện? | Không: dùng `ChangeNotifier`/`ValueNotifier` của Flutter SDK | **Đã chốt: Không dùng GetX** |
| D7 | Có nút "Thử lại" trên chip lỗi không? | Không: chip báo số lượng chưa thêm vào giỏ, thu ngân quét lại | **Đã chốt: Bỏ nút Thử lại** |
| D8 | Có giữ typedef tên ngắn `ScanRequest` / `ScanAck` song song với `StreamScanRequest` / `StreamScanResponse` không? | Không: mỗi kiểu chỉ một tên trong API public | |
| D9 | Có cho phép dartdoc `///` dài hơn 3 dòng với API public chính (`scanStream`, `onScan`, `StreamScanSession`) để ghi hợp đồng không? | Có (chỉ cho các API này) | |
| D10 | Cấu trúc thư mục: `presentation/controllers/` mới tồn tại song song với `lib/src/controllers/` cũ; `stream_scan_dispatcher.dart` nằm trong `usecases/` nhưng không có hậu tố `_usecase` | Đặt tên `stream_scan_dispatcher_usecase.dart`; chấp nhận hai thư mục controllers (không di chuyển file cũ theo mục 2.2) | |
| D11 | Hiển thị sản phẩm đã quét như thế nào? | Xếp layer như multi-scan cũ: mã mới thì thêm layer; mã đã có thì layer lên đầu và số lượng lấy từ easypos; quét lỗi hiện chip như cũ. Mã **đã có trong giỏ** bị reject thì giữ layer ở số lượng cũ; mã chưa từng accept thì xoá layer. | **Đã chốt** (đã làm, xem báo cáo mục 5.5) |

---

## 11. Báo cáo Review & Nhật ký hiệu chỉnh Plan

### 11.1 Đồng bộ giữa Mục 3 (Nguyên tắc kỹ thuật) và Thiết kế hệ thống (Mục 5, 6)
> Điểm 1 (GetX) **đã được thay thế ở 11.3**.

1. **GetX vs. `ValueNotifier` và quản lý vòng đời (`onClose`)**:
   - **Vấn đề cũ**: Mục 3 chọn `Clean Architecture + GetX`, nhưng Mục 5.2, 5.6 và 6 vẫn thiết kế theo `ValueNotifier` / `ValueListenableBuilder`, và `pubspec.yaml` chưa khai báo `get`. Ngoài ra, nếu đặt `ScanDispatcher` nằm trong `GetxController` gắn theo route, khi đóng màn hình GetX gọi `onClose()` sẽ huỷ luôn hàng đợi đang chạy ngầm.
   - **Đã hiệu chỉnh**: Bổ sung `get` vào `pubspec.yaml`; chuyển state UI sang `StreamScanController` (`GetxController` + `.obs` + `Obx`); tách độc lập vòng đời của `StreamScanDispatcher` khỏi `StreamScanController.onClose()` để hàng đợi nền chạy tới khi hoàn tất.
2. **Cấu trúc Clean Architecture & Quy ước đặt tên**:
   - **Vấn đề cũ**: `controllers/` đặt ngoài `presentation/`; tên model/widget (`ScanAck`, `scan_result_cards.dart`) và thư mục `test/` phẳng chưa khớp quy ước `<tên_tính_năng>_<vai_trò>` (`controller`, `page`, `component`, `request`, `response`, `usecase`, `constants`).
   - **Đã hiệu chỉnh**: Chuẩn hoá toàn bộ cây thư mục ở Mục 6.2 (`domain/entities`, `domain/usecases`, `data/services`, `presentation/controllers`, `presentation/pages`, `presentation/components`) và gom test theo tính năng (`test/stream_scan/`, `test/citizen_id_scan/`).
3. **Quy tắc Syntax & Comment**:
   - **Vấn đề cũ**: Code mẫu ở Mục 5.1 chưa khai báo kiểu dữ liệu tường minh cho biến `final`.
   - **Đã hiệu chỉnh**: Cập nhật code mẫu dùng kiểu tường minh (`final Product? p = ...`, `final String? err = ...`), gom hằng số vào `stream_scan_constants.dart`, và quy định rõ giới hạn comment (`//` ≤ 16 từ, `///` ≤ 3 dòng).

### 11.2 Các lỗ hổng logic & Edge Cases kỹ thuật đã khắc phục
> Các điểm 1, 2, 3, 4 **đã được hiệu chỉnh tiếp ở 11.3**.

1. **Lỗi đếm lặp vô tận khi bao bì có 2 mã vạch đứng cạnh nhau (`maxCodesPerFrame = 1`)**:
   - **Nguyên nhân**: Nếu cắt danh sách theo `maxCodesPerFrame = 1` trước khi cập nhật trạng thái có mặt, khi 2 mã `A` và `B` cùng nằm trong khung và thay nhau đứng gần tâm qua từng frame, mã kia sẽ bị tính là vắng (`missedFrames >= 2`) rồi ngay lập tức bị đếm lặp khi gần tâm trở lại.
   - **Giải pháp (Mục 5.3)**: Cập nhật `missedFrames = 0` cho **toàn bộ** mã phát hiện được trong khung trước; chỉ áp dụng `maxCodesPerFrame = 1` khi lọc lấy mã **mới xuất hiện** để phát sự kiện đếm lượt.
2. **Tận dụng cờ mờ/lóa (`isBlurry`, `hasGlare`) có sẵn trong `BarcodeScannerService`**:
   - **Nguyên nhân**: `BarcodeScannerService.processCameraImage` đã tính sẵn `(barcodes, justSettled, isMoving, isBlurry, hasGlare)`, nhưng hook `onFrameProcessed` cũ chỉ truyền `List<Barcode>`, bỏ lỡ dữ liệu giúp chống đếm thừa khi ML Kit đọc trượt vài frame do lóa đèn hoặc rung tay.
   - **Giải pháp (Mục 5.2, 5.3)**: Hook `onFrameProcessed` truyền `StreamFrameReport` (gồm `barcodes`, `isBlurry`, `hasGlare`, `isMoving`). Khi frame rỗng do mờ hoặc lóa (`isBlurry || hasGlare`), không tăng `missedFrames`.
3. **Làm rõ số lượng (`quantity`) khi bấm "Thử lại" và tương tác với `errorCooldown`**:
   - **Nguyên nhân**: Chưa quy định rõ khi 1 lượt đang gọi API và `n` lượt đang xếp hàng bị huỷ do `reject(retryable: true)`, bấm "Thử lại" sẽ gửi `quantity` bằng bao nhiêu và có bị chặn bởi `errorCooldown` (2s) không.
   - **Giải pháp (Mục 5.4)**: Gộp tổng số lượng chưa thành công (`failedQty = req.quantity + queued`) vào chip lỗi để khi bấm "Thử lại" sẽ gửi đủ số lượng kèm `attempt + 1`, đồng thời bỏ qua `errorCooldown` cho thao tác bấm thủ công.
4. **Kiểu trả về của `SmartScanner.scanStream` khi đóng màn hình sớm**:
   - **Nguyên nhân**: Nếu trả về `Future<void>` ngay khi đóng màn hình trong lúc hàng đợi nền chưa xong, easypos chuyển sang màn Thanh toán ngay có thể bị thiếu sản phẩm vừa quét cuối cùng.
   - **Giải pháp (Mục 5.1, 5.4)**: Trả về `Future<StreamScanSessionResult>` chứa `Future<void> pendingDrain` để easypos có thể `await` trước khi chốt đơn nếu cần.
5. **Tối ưu Phase 4 (QR CCCD) & Quyết định D2**:
   - **Không sửa `smart_scanner_page.dart`**: Tách `StreamVibrationService` và `GalleryDecodeService` riêng ở `data/services/`, trong đó `GalleryDecodeService` trả về cả `rawBytes` để xử lý lỗi bảng mã tiếng Việt trên CCCD.
   - **Zoom 2x mặc định cho CCCD**: Dùng tham số optional `initialZoom` trên `CustomBarcodeScanner` thay vì gọi `setZoom(2.0)` trong callback `onZoomChanged` (tránh vòng lặp callback và lỗi double-tap trả về 1.0x).
   - **Bỏ `ScannerControlsRow` ở màn Stream**: Khi `showMultiScanToggle: false`, widget này trả về `SizedBox.shrink()` nên không cần gắn vào cây widget của `StreamScanPage`.

### 11.3 Vòng review 2: phản biện & quyết định (2026-11-07)

1. **Bỏ qua frame mờ/lóa khi đếm "vắng" (thay thế 11.2.2)**:
   - **Vấn đề**: Cờ `isBlurry` / `hasGlare` được tính trên **toàn khung hình**, không phải vùng quét (`barcode_scanner_service.dart` → `_estimateIsBlurry` / `_estimateHasGlare`). `isBlurry` chỉ là độ chênh sáng trung bình < 5, thiết kế cho gợi ý "lùi ra xa" vốn chỉ hiện khi tình trạng kéo dài 2,5s, không dùng được để đánh giá từng frame. Nếu bỏ qua vô điều kiện:
     - Lúc đổi hàng, tay chuyển động nên các frame đều mờ. Mã A không bao giờ bị đánh dấu "vắng", nên sản phẩm B cùng mã **không được đếm**.
     - Mặt quầy trơn một màu làm `isBlurry` luôn bằng true; đèn chiếu vào khung làm `hasGlare` luôn bằng true. Mã kẹt ở trạng thái "có mặt", dẫn tới **đếm thiếu**.
     - Đếm thiếu làm mất doanh thu một cách lặng lẽ, trong khi đếm thừa thu ngân còn nhìn thấy được. Vì vậy đếm thiếu là lỗi tệ hơn.
   - **Hiệu chỉnh (5.3 bước 4, 5.5)**: Mặc định `ignoreBlurryOrGlareMisses: false`. Khi bật thì chỉ bỏ qua tối đa K = 2 frame liên tiếp. Phase 0 đo tỉ lệ bật cờ trong 3 tình huống rồi mới quyết định. `StreamFrameReport` vẫn giữ các cờ này để đo đạc.
2. **Hai mã cạnh nhau: bản sửa ở 11.2.1 mới xử lý được một nửa**:
   - **Vấn đề**: Bản 11.2.1 chỉ đánh dấu "có mặt" cho mã được đếm. Mã mới thứ hai (B) không được đếm và cũng không được đánh dấu, nên ở frame sau khi B đứng gần tâm hơn thì B là mã mới và **bị đếm**. Với bao bì có EAN kèm mã nội bộ, mỗi lần quét sẽ hiện thêm một chip "Không tìm thấy sản phẩm".
   - **Hiệu chỉnh (5.3 bước 3)**: Các mã mới còn lại trong cùng frame được đánh dấu "có mặt" nhưng không đếm.
3. **Bỏ GetX (thay thế 11.1.1, chốt D6)**:
   - **Lý do**:
     - (a) Thêm `get` vào `pubspec.yaml` ảnh hưởng tới việc resolve dependency của mọi app dùng thư viện, và dễ xung đột version với easypos.
     - (b) Thư viện mở màn hình bằng `Navigator.push` + `MaterialPageRoute`, nên GetX không tự gọi `onClose`. Controller tạo bằng `Get.put` không được giải phóng, và `Get.find` có thể trả về instance cũ đã đóng.
     - (c) Container quản lý dependency của Get dùng chung toàn cục, dễ trùng tên với app.
     - (d) Package hiện đã dùng `ChangeNotifier`/`ValueNotifier`.
   - **Hiệu chỉnh**: Mục 3, 5.2, 5.4, 5.6, 6 dùng `ChangeNotifier`/`ValueNotifier` + `ValueListenableBuilder`. `pubspec.yaml` không thêm dependency. GetX (nếu cần) dùng ở phía easypos.
4. **Bỏ nút "Thử lại" (thay thế 11.2.3, chốt D7)**:
   - **Vấn đề**: Thư viện không phân biệt được thu ngân đang quét lại **đúng sản phẩm bị lỗi** hay **một sản phẩm khác cùng mã**:
     - Nếu tự đóng chip khi quét lại, kịch bản "bán 5 chai, chai đầu lỗi" chỉ được 4.
     - Nếu giữ chip, kịch bản "quét lại đúng chai bị lỗi rồi bấm Thử lại" thành 2.
   - **Hiệu chỉnh (5.1, 5.4, 5.5)**:
     - Bỏ nút "Thử lại", `retryable`, `attempt`, `failedQty`.
     - Chip ghi rõ "{n} SP chưa thêm vào giỏ, hãy quét lại". Quy tắc duy nhất: mỗi lần quét thành công là +1.
     - **Bỏ luôn `errorCooldown`**: chip yêu cầu quét lại, nên cooldown sẽ âm thầm bỏ qua lần quét lại hợp lệ. Việc chống chip lặp do mã chập chờn đã có `leaveFrame` lo.
     - Reject trùng mã và trùng message thì cộng dồn vào chip đang hiển thị.
     - `chipAutoHide` tăng lên 5s.
5. **Kết quả trả về sau khi hàng đợi xử lý xong (hiệu chỉnh 11.2.4)**:
   - **Vấn đề**: `acceptedCount` / `rejectedCount` trả về lúc đóng màn hình, trong khi `pendingDrain` vẫn đang chạy, nên chưa phải số cuối cùng.
   - **Hiệu chỉnh (5.1)**: `StreamScanSession { Future<StreamScanSummary> drained }`, trong đó `StreamScanSummary` (`acceptedQuantity`, `notAddedQuantity`) chỉ có giá trị sau khi hàng đợi đã xử lý xong.
6. **`initialZoom` (bổ sung cho 11.2.5)**:
   - Phải truyền xuống tận `CameraService._applyDefaultZoom`, nghĩa là có sửa `camera_service.dart` (đã thêm vào 4 và 6.1).
   - Phải áp dụng lại mỗi lần camera khởi tạo lại.
   - Mốc zoom của thao tác chạm đúp đổi theo `initialZoom` chỉ khi tham số này khác `null`.
7. **Điểm nhỏ đưa vào mục 10 chờ chốt**: typedef hai tên (D8), ngoại lệ độ dài dartdoc cho API public chính (D9), cấu trúc/tên thư mục (D10).

---

## 11. Báo cáo Review & Nhật ký hiệu chỉnh Plan

### 11.1 Đồng bộ giữa Mục 3 (Nguyên tắc kỹ thuật) và Thiết kế hệ thống (Mục 5, 6)
1. **GetX vs. `ValueNotifier` và quản lý vòng đời (`onClose`)**:
   - **Vấn đề cũ**: Mục 3 chọn `Clean Architecture + GetX`, nhưng Mục 5.2, 5.6 và 6 vẫn thiết kế theo `ValueNotifier` / `ValueListenableBuilder`, và `pubspec.yaml` chưa khai báo `get`. Ngoài ra, nếu đặt `ScanDispatcher` nằm trong `GetxController` gắn theo route, khi đóng màn hình GetX gọi `onClose()` sẽ huỷ luôn hàng đợi đang chạy ngầm.
   - **Đã hiệu chỉnh**: Bổ sung `get` vào `pubspec.yaml`; chuyển state UI sang `StreamScanController` (`GetxController` + `.obs` + `Obx`); tách độc lập vòng đời của `StreamScanDispatcher` khỏi `StreamScanController.onClose()` để hàng đợi nền chạy tới khi hoàn tất.
2. **Cấu trúc Clean Architecture & Quy ước đặt tên**:
   - **Vấn đề cũ**: `controllers/` đặt ngoài `presentation/`; tên model/widget (`ScanAck`, `scan_result_cards.dart`) và thư mục `test/` phẳng chưa khớp quy ước `<tên_tính_năng>_<vai_trò>` (`controller`, `page`, `component`, `request`, `response`, `usecase`, `constants`).
   - **Đã hiệu chỉnh**: Chuẩn hoá toàn bộ cây thư mục ở Mục 6.2 (`domain/entities`, `domain/usecases`, `data/services`, `presentation/controllers`, `presentation/pages`, `presentation/components`) và gom test theo tính năng (`test/stream_scan/`, `test/citizen_id_scan/`).
3. **Quy tắc Syntax & Comment**:
   - **Vấn đề cũ**: Code mẫu ở Mục 5.1 chưa khai báo kiểu dữ liệu tường minh cho biến `final`.
   - **Đã hiệu chỉnh**: Cập nhật code mẫu dùng kiểu tường minh (`final Product? p = ...`, `final String? err = ...`), gom hằng số vào `stream_scan_constants.dart`, và quy định rõ giới hạn comment (`//` ≤ 16 từ, `///` ≤ 3 dòng).

### 11.2 Các lỗ hổng logic & Edge Cases kỹ thuật đã khắc phục
1. **Lỗi đếm lặp vô tận khi bao bì có 2 mã vạch đứng cạnh nhau (`maxCodesPerFrame = 1`)**:
   - **Nguyên nhân**: Nếu cắt danh sách theo `maxCodesPerFrame = 1` trước khi cập nhật trạng thái có mặt, khi 2 mã `A` và `B` cùng nằm trong khung và thay nhau đứng gần tâm qua từng frame, mã kia sẽ bị tính là vắng (`missedFrames >= 2`) rồi ngay lập tức bị đếm lặp khi gần tâm trở lại.
   - **Giải pháp (Mục 5.3)**: Cập nhật `missedFrames = 0` cho **toàn bộ** mã phát hiện được trong khung trước; chỉ áp dụng `maxCodesPerFrame = 1` khi lọc lấy mã **mới xuất hiện** để phát sự kiện đếm lượt.
2. **Tận dụng cờ mờ/lóa (`isBlurry`, `hasGlare`) có sẵn trong `BarcodeScannerService`**:
   - **Nguyên nhân**: `BarcodeScannerService.processCameraImage` đã tính sẵn `(barcodes, justSettled, isMoving, isBlurry, hasGlare)`, nhưng hook `onFrameProcessed` cũ chỉ truyền `List<Barcode>`, bỏ lỡ dữ liệu giúp chống đếm thừa khi ML Kit đọc trượt vài frame do lóa đèn hoặc rung tay.
   - **Giải pháp (Mục 5.2, 5.3)**: Hook `onFrameProcessed` truyền `StreamFrameReport` (gồm `barcodes`, `isBlurry`, `hasGlare`, `isMoving`). Khi frame rỗng do mờ hoặc lóa (`isBlurry || hasGlare`), không tăng `missedFrames`.
3. **Làm rõ số lượng (`quantity`) khi bấm "Thử lại" và tương tác với `errorCooldown`**:
   - **Nguyên nhân**: Chưa quy định rõ khi 1 lượt đang gọi API và `n` lượt đang xếp hàng bị huỷ do `reject(retryable: true)`, bấm "Thử lại" sẽ gửi `quantity` bằng bao nhiêu và có bị chặn bởi `errorCooldown` (2s) không.
   - **Giải pháp (Mục 5.4)**: Gộp tổng số lượng chưa thành công (`failedQty = req.quantity + queued`) vào chip lỗi để khi bấm "Thử lại" sẽ gửi đủ số lượng kèm `attempt + 1`, đồng thời bỏ qua `errorCooldown` cho thao tác bấm thủ công.
4. **Kiểu trả về của `SmartScanner.scanStream` khi đóng màn hình sớm**:
   - **Nguyên nhân**: Nếu trả về `Future<void>` ngay khi đóng màn hình trong lúc hàng đợi nền chưa xong, easypos chuyển sang màn Thanh toán ngay có thể bị thiếu sản phẩm vừa quét cuối cùng.
   - **Giải pháp (Mục 5.1, 5.4)**: Trả về `Future<StreamScanSessionResult>` chứa `Future<void> pendingDrain` để easypos có thể `await` trước khi chốt đơn nếu cần.
5. **Tối ưu Phase 4 (QR CCCD) & Quyết định D2**:
   - **Không sửa `smart_scanner_page.dart`**: Tách `StreamVibrationService` và `GalleryDecodeService` riêng ở `data/services/`, trong đó `GalleryDecodeService` trả về cả `rawBytes` để xử lý lỗi bảng mã tiếng Việt trên CCCD.
   - **Zoom 2x mặc định cho CCCD**: Dùng tham số optional `initialZoom` trên `CustomBarcodeScanner` thay vì gọi `setZoom(2.0)` trong callback `onZoomChanged` (tránh vòng lặp callback và lỗi double-tap trả về 1.0x).
   - **Bỏ `ScannerControlsRow` ở màn Stream**: Khi `showMultiScanToggle: false`, widget này trả về `SizedBox.shrink()` nên không cần gắn vào cây widget của `StreamScanPage`.

