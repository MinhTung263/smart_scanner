# Báo cáo Review Kế hoạch: Barcode Stream Scan & QR CCCD

- **File kế hoạch được review**: [plan-stream-scan.md](file:///d:/code/smart_scanner/docs/plan-stream-scan.md)
- **Ngày review**: 2026-11-07
- **Trạng thái**: Đã cập nhật trực tiếp toàn bộ nội dung hiệu chỉnh vào [plan-stream-scan.md](file:///d:/code/smart_scanner/docs/plan-stream-scan.md)

---

## 1. Đánh giá tổng quan

Bản kế hoạch gốc có định hướng rất tốt ở 3 điểm:
1. **Ranh giới trách nhiệm rõ ràng**: `smart_scanner` chỉ đảm nhiệm camera, nhận diện, chống trùng theo khung, điều phối hàng đợi và phản hồi UI/rung; `easypos` giữ toàn quyền về cache, gọi API, timeout và giỏ hàng.
2. **Bảo toàn hành vi cũ (Backward Compatibility)**: Quy định rõ các file không được sửa và yêu cầu giữ nguyên chữ ký + giá trị mặc định của API hiện có.
3. **Đo lường thực nghiệm (Phase 0)**: Có bước đo baseline trên thiết bị 3GB RAM trước khi chốt tham số `missedFrames` (`N`) và trước khi can thiệp tối ưu sâu.

Tuy nhiên, khi đối chiếu giữa **Mục 3 (Nguyên tắc kỹ thuật mới điền)**, **Mục 5–7 của Plan** và **source code hiện tại của thư viện**, có các mâu thuẫn kiến trúc và lỗ hổng logic cần giải quyết.

---

## 2. Xung đột giữa Mục 3 (Nguyên tắc kỹ thuật) và Phần còn lại của Plan

### 2.1. GetX vs. `ValueNotifier` và bài toán vòng đời khi đóng màn hình
- **Hiện trạng trước khi sửa**:
  - [Mục 3](file:///d:/code/smart_scanner/docs/plan-stream-scan.md#L45-L54) quy định dùng **Clean Architecture + GetX**, nhưng Mục 5.2, 5.6 và 6 vẫn thiết kế bằng `ValueNotifier` / `ValueListenableBuilder`.
  - [pubspec.yaml](file:///d:/code/smart_scanner/pubspec.yaml) chưa có dependency `get`.
- **Rủi ro vòng đời (Lifecycle Trap)**:
  - Theo [Mục 5.4](file:///d:/code/smart_scanner/docs/plan-stream-scan.md#L178-L180), khi người dùng bấm Hoàn tất hoặc Back, màn hình đóng ngay nhưng `StreamScanDispatcher` **vẫn phải chạy ngầm cho hết hàng đợi**.
  - Nếu đặt logic hàng đợi nằm trong `GetxController` gắn với route, ngay khi `Navigator.pop` chạy, GetX sẽ gọi `onClose()` và huỷ controller, làm đứt các lời gọi `onScan` đang xếp hàng hoặc gây crash khi cập nhật `.obs` đã đóng.
- **Giải pháp đã cập nhật vào Plan**:
  - Bổ sung `get` vào `pubspec.yaml`.
  - Tách biệt 2 lớp: `StreamScanController` (`GetxController`) chỉ quản lý các biến `.obs` phục vụ UI và ngắt kết nối khi `onClose()`; còn `StreamScanDispatcher` sống độc lập cho tới khi xử lý xong toàn bộ hàng đợi và hoàn tất `StreamScanSessionResult.pendingDrain`.

### 2.2. Cấu trúc thư mục Clean Architecture & Quy ước đặt tên
- **Hiện trạng trước khi sửa**:
  - Mục 3 yêu cầu đặt tên theo công thức `<tên_tính_năng> + controller/page/component/request/response` và chia unit test theo từng tính năng.
  - Mục 6 cũ lại đặt `lib/src/controllers/` nằm ngoài `presentation/`, đặt tên model là `ScanAck`, widget là `scan_result_cards.dart` và để test phẳng trong `test/`.
- **Giải pháp đã cập nhật vào Plan ([Mục 6.2](file:///d:/code/smart_scanner/docs/plan-stream-scan.md#L224-L259))**:
  - Đưa controller vào đúng tầng `lib/src/presentation/controllers/stream_scan_controller.dart`.
  - Chuẩn hoá tên file & class:
    - `StreamScanRequest`, `StreamScanResponse` (kèm `typedef ScanRequest` / `ScanAck` để giữ sự ngắn gọn nếu cần).
    - `StreamPresenceTrackerUseCase`, `StreamScanDispatcher`.
    - `StreamScanPage`, `StreamScanResultCardComponent`, `StreamScanErrorChipComponent`, `StreamScanSlowNetworkComponent`.
    - `stream_scan_constants.dart` chứa toàn bộ hằng số mặc định (không hardcode).
  - Gom test theo tính năng: `test/stream_scan/...` và `test/citizen_id_scan/...`.

### 2.3. Quy tắc Syntax & Comment ([Mục 3](file:///d:/code/smart_scanner/docs/plan-stream-scan.md#L65-L68))
- **Khai báo kiểu tường minh cho `final`**: Đã sửa lại đoạn code mẫu ở [Mục 5.1](file:///d:/code/smart_scanner/docs/plan-stream-scan.md#L95-L120) (`final Product? p = ...`, `final String? err = ...`).
- **Quy tắc comment (`//` ≤ 16 từ, `///` ≤ 3 dòng)**: Đã ghi rõ vào tiêu chí Phase 1a & 1d để đảm bảo khi viết dartdoc không vượt quá 3 dòng `///`.

---

## 3. Các lỗ hổng logic & Edge Cases kỹ thuật đã phát hiện và khắc phục

### 3.1. Bug đếm lặp vô tận khi bao bì có 2 mã vạch cạnh nhau (`maxCodesPerFrame = 1`)
- **Phân tích lỗi**:
  - Giả sử trên cùng một sản phẩm có 2 mã `A` và `B` nằm gần nhau trong khung quét, và `maxCodesPerFrame = 1`.
  - Nếu lọc lấy 1 mã gần tâm nhất **trước khi** cập nhật trạng thái hiện diện (`PresenceTracker`):
    - Frame 1: `A` gần tâm hơn $\rightarrow$ đếm `A` (1), `B` không được ghi nhận.
    - Frame 2 & 3: Tay thu ngân dịch nhẹ 2mm, `B` gần tâm hơn $\rightarrow$ đếm `B` (1); lúc này `A` bị tính là vắng 2 frame liên tiếp (`missedFrames = 2` $\rightarrow$ đánh dấu **vắng**!).
    - Frame 4: Tay dịch nhẹ lại, `A` gần tâm hơn $\rightarrow$ **`A` bị đếm lặp lần 2** dù sản phẩm chưa từng rời khung!
- **Giải pháp ([Mục 5.3](file:///d:/code/smart_scanner/docs/plan-stream-scan.md#L149-L155))**:
  - **Bước 1**: Đặt `missedFrames = 0` cho **mọi** mã xuất hiện trong `report.barcodes` của frame đó.
  - **Bước 2**: Chỉ áp dụng `maxCodesPerFrame = 1` trên danh sách **các mã mới xuất hiện (hoặc xuất hiện lại sau khi đã thật sự rời khung)**.

### 3.2. Tận dụng cờ mờ/lóa (`isBlurry`, `hasGlare`) có sẵn trong [`BarcodeScannerService`](file:///d:/code/smart_scanner/lib/src/data/services/barcode_scanner_service.dart#L625-L647)
- **Phân tích**:
  - Rủi ro lớn nhất ở Mục 9 là ML Kit bỏ sót 2 frame liên tiếp do lóa sáng hoặc mờ ảnh khi thu ngân đang cầm sản phẩm, gây đếm thừa.
  - Thực tế [`CustomBarcodeScannerState._processCameraImage`](file:///d:/code/smart_scanner/lib/src/presentation/widgets/custom_barcode_scanner.dart#L422-L436) đã nhận về `(barcodes, justSettled, isMoving, isBlurry, hasGlare)` từ `BarcodeScannerService`, nhưng hook `onFrameProcessed(List<Barcode>)` cũ lại làm rơi mất `isBlurry`, `hasGlare`, `isMoving`.
- **Giải pháp ([Mục 5.2, 5.3](file:///d:/code/smart_scanner/docs/plan-stream-scan.md#L136-L159))**:
  - Đổi tham số của `onFrameProcessed` thành `StreamFrameReport(barcodes, isBlurry, hasGlare, isMoving)`.
  - Khi một frame decode ra rỗng (`barcodes.isEmpty`) nhưng `isBlurry || hasGlare` là `true`, `StreamPresenceTrackerUseCase` không tăng `missedFrames`.

### 3.3. Số lượng (`quantity`) khi bấm "Thử lại" và tương tác với `errorCooldown`
- **Phân tích**:
  - Khi mã `X` đang gọi `onScan(quantity: 1)` mà thu ngân quét tiếp 2 lượt nữa (`queued = 2`), nếu lời gọi đầu trả về `reject(retryable: true)` do lỗi mạng thì 2 lượt chờ bị huỷ. Nếu bấm "Thử lại" mà chỉ gửi `quantity: 1` thì thu ngân bị mất 2 lượt đã quét; ngoài ra nếu bấm "Thử lại" ngay trong vòng 2s đầu thì không được bị chặn bởi `errorCooldown`.
- **Giải pháp ([Mục 5.4](file:///d:/code/smart_scanner/docs/plan-stream-scan.md#L170-L171))**:
  - Lưu `failedQty = req.quantity + queued` vào chip lỗi để khi bấm "Thử lại" sẽ gửi đủ tổng số lượng kèm `attempt + 1`.
  - Thao tác bấm "Thử lại" thủ công bỏ qua `errorCooldown`.

### 3.4. Kiểu trả về của `SmartScanner.scanStream` khi đóng màn hình sớm
- **Phân tích**:
  - Nếu `scanStream` chỉ trả về `Future<void>` ngay lúc pop màn hình trong khi `StreamScanDispatcher` vẫn đang chạy ngầm 1–2 request cuối, nếu thu ngân bấm "Thanh toán" ngay lập tức trên `easypos` thì giỏ hàng có thể chưa kịp cộng món cuối.
- **Giải pháp ([Mục 5.1, 5.4](file:///d:/code/smart_scanner/docs/plan-stream-scan.md#L96-L120))**:
  - `SmartScanner.scanStream` trả về `Future<StreamScanSessionResult>` có trường `Future<void> pendingDrain` để `easypos` có thể chủ động `await session.pendingDrain` trước khi chuyển sang bước thanh toán.

### 3.5. Tối ưu Phase 4 (QR CCCD) & Quyết định D2
- **Giữ nguyên [`smart_scanner_page.dart`](file:///d:/code/smart_scanner/lib/src/presentation/pages/smart_scanner_page.dart)**: Thay vì sửa file cũ để tách `_vibrateAndroid` và `_decodeGalleryBarcodes` (vi phạm quy tắc Mục 2.2), tạo mới `StreamVibrationService` và `GalleryDecodeService` trong `data/services/`. Đặc biệt, `GalleryDecodeService` hỗ trợ trả về cả `rawBytes` (mà hàm cũ đang bỏ qua) để xử lý lỗi bảng mã tiếng Việt của CCCD ở Phase 4.
- **Zoom mặc định 2x cho CCCD**: Thay vì gọi `setZoom(2.0)` trong callback `onZoomChanged` lần đầu (dễ gây vòng lặp callback và làm tính năng double-tap zoom trả nhầm về `1.0x`), thêm tham số optional `initialZoom` vào [`CustomBarcodeScanner`](file:///d:/code/smart_scanner/lib/src/presentation/widgets/custom_barcode_scanner.dart#L14-L53).
- **Loại bỏ `ScannerControlsRow` khỏi màn Stream**: Trong [`ScannerControlsRow.build`](file:///d:/code/smart_scanner/lib/src/presentation/widgets/scanner_controls.dart#L221), khi `showMultiScanToggle: false` thì widget trả về `const SizedBox.shrink()`, do đó `StreamScanPage` chỉ cần dùng `ScannerOverlay` và `ScannerTopBar`.

