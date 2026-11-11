# Báo Cáo Triển Khai Chi Tiết Từng Phase: Barcode Stream Scan (smart_scanner 0.1.0)

- **Dự án**: `smart_scanner` (nhánh `optimize`)
- **Phiên bản hiện tại**: `0.1.0`
- **Ngày thực hiện**: 2026-11-07
- **Tài liệu căn cứ**: [plan-stream-scan.md](file:///d:/code/smart_scanner/docs/plan-stream-scan.md) & [review-report-stream-scan.md](file:///d:/code/smart_scanner/docs/review-report-stream-scan.md)
- **Thiết bị kiểm thử kết nối**: Redmi Note 15 (`2510DRA23E`, serial `CIPRWWJJL7MZWSYL`, Android 15 / API 35, MediaTek MT6789 8 nhân, RAM ~5.5 GB)

---

## 1. Tổng Quan Tiến Độ Các Phase

Quá trình triển khai tính năng **Barcode Stream Scan (0.1.0)** được chia nhỏ và giao quyền cho từng **Subagent** chuyên trách theo nguyên tắc Clean Architecture + Flutter Native (`ChangeNotifier` / `ValueNotifier` + `RepaintBoundary`, không dùng GetX theo Quyết định D6) và các ràng buộc kỹ thuật tại Mục 3 của Kế hoạch.

| Phase | Subagent Phụ Trách | Trạng Thái | Số Test Mới | Tổng Test Toàn Bộ |
|---|---|:---:|:---:|:---:|
| **Phase 1A** | Domain Logic Engineer | **Hoàn thành** | 17 tests | 39 / 39 |
| **Phase 1B** | Camera Pipeline Engineer | **Hoàn thành** | 6 tests | 45 / 45 |
| **Phase 1C** | Presentation & UI Engineer | **Hoàn thành** | 23 tests | 68 / 68 |
| **Phase 1D** | QA & Documentation Engineer | **Hoàn thành** | App Demo & Doc | 68 / 68 |
| **Phase 0 & 2**| Device Performance Engineer | Sẵn sàng đo trên Redmi Note 15 | — | — |
| **Phase 3** | Integration & Release Engineer | Chờ tích hợp easypos | — | — |
| **Phase 4** | CCCD Parser Engineer | Kế tiếp (QR CCCD 0.2.0) | — | — |

---

## 2. Báo Cáo Chi Tiết Từng Phase Đã Hoàn Thành

### Phase 1A: Tầng Domain Lõi & Điều Phối Dispatcher
- **Subagent**: `Domain Logic Engineer`
- **Mục tiêu**: Xây dựng toàn bộ các Entity, Request/Response, Options, Hằng số, Thuật toán xác định hiện diện (`StreamPresenceTrackerUseCase`) và Điều phối hàng đợi (`StreamScanDispatcher`) thuần Dart, độc lập hoàn toàn với Flutter UI/GetX.

#### Các tệp đã tạo & chuẩn hóa:
1. [stream_scan_constants.dart](file:///d:/code/smart_scanner/lib/src/core/constants/stream_scan_constants.dart):
   - Quản lý tập trung các hằng số: `defaultMissedFrames` ($N = 2$), `defaultIgnoreBlurryOrGlareMisses` (bỏ qua frame mờ/lóa tối đa $K = 2$), `defaultMaxCodesPerFrame` (1), `defaultMaxConcurrent` (2), `defaultSlowHintAfter` (3s), `defaultMaxVisibleCards` (3), `defaultMaxVisibleChips` (3), `defaultChipAutoHide` (5s), thông số rung (70ms Android, 80ms nghỉ). Đã loại bỏ hoàn toàn `defaultErrorCooldown`, `normalChipAutoHide`, `retryableChipAutoHide`, `defaultRetryButtonText` (D7).
2. [stream_frame_report.dart](file:///d:/code/smart_scanner/lib/src/domain/entities/stream_frame_report.dart):
   - Đối tượng báo cáo frame: `barcodes`, `isBlurry`, `hasGlare`, `isMoving`.
3. [stream_scan_request.dart](file:///d:/code/smart_scanner/lib/src/domain/entities/stream_scan_request.dart):
   - [`StreamScanRequest`](file:///d:/code/smart_scanner/lib/src/domain/entities/stream_scan_request.dart#L7-L20) (`code`, `format`, `quantity`) kèm `typedef ScanRequest`. Đã loại bỏ `attempt` (D7).
4. [stream_scan_response.dart](file:///d:/code/smart_scanner/lib/src/domain/entities/stream_scan_response.dart):
   - [`StreamScanResponse`](file:///d:/code/smart_scanner/lib/src/domain/entities/stream_scan_response.dart#L5-L55) (`.accept`, `.reject(message)` không còn `retryable`), `typedef ScanAck`, [`StreamScanSession`](file:///d:/code/smart_scanner/lib/src/domain/entities/stream_scan_response.dart#L90-L98) (chứa `drained` kiểu `Future<StreamScanSummary>`), [`StreamScanSummary`](file:///d:/code/smart_scanner/lib/src/domain/entities/stream_scan_response.dart#L60-L88) (`acceptedQuantity`, `notAddedQuantity`). Đã xóa bỏ hoàn toàn `StreamScanSessionResult`, `pendingDrain`, `toSessionResult()` (D7, R3).
5. [stream_scan_options.dart](file:///d:/code/smart_scanner/lib/src/domain/entities/stream_scan_options.dart):
   - [`RescanPolicy.leaveFrame`](file:///d:/code/smart_scanner/lib/src/domain/entities/stream_scan_options.dart#L4-L21) và [`StreamScanOptions`](file:///d:/code/smart_scanner/lib/src/domain/entities/stream_scan_options.dart#L24-L55) với `chipAutoHide = 5s`, đã xóa bỏ `errorCooldown`.
6. [stream_presence_tracker_usecase.dart](file:///d:/code/smart_scanner/lib/src/domain/usecases/stream_presence_tracker_usecase.dart):
   - Triển khai giải thuật `RescanPolicy.leaveFrame`.
   - **Xử lý triệt để bug 2 mã cạnh nhau**: Cập nhật trạng thái "có mặt" (`missedFrames = 0`) cho **toàn bộ** mã nhìn thấy trong khung trước khi lọc; chỉ mã gần tâm nhất được phát sự kiện đếm, mã còn lại được đánh dấu "có mặt" ngay tại frame đó để không bị đếm lặp ở các frame sau.
   - **Chống đếm thừa khi mờ/lóa**: Bỏ qua tối đa $K$ frame rỗng liên tiếp do `isBlurry` hoặc `hasGlare`.
   - Duy trì trạng thái qua `pause()` và `resume()`.
7. [stream_scan_dispatcher.dart](file:///d:/code/smart_scanner/lib/src/domain/usecases/stream_scan_dispatcher.dart):
   - Đảm bảo tuần tự theo từng mã (không gọi `onScan` song song cho cùng 1 mã).
   - Gộp số lượng (`quantity aggregation`): Gom các lượt quét tới trong lúc mã đang gọi API hoặc đang xếp hàng.
   - Giới hạn song song (`maxConcurrent = 2`) và thứ tự FIFO cho các mã khác nhau.
   - Xử lý `reject`: Hủy các lượt đang chờ của mã đó; tính tổng số lượng chưa vào giỏ (`failedQty = req.quantity + queued`). Bỏ luồng thử lại và cooldown; quét lại ngay lập tức được tiếp nhận như một lượt quét mới bình thường (D7). Khi reject trùng mã và message với chip đang hiển thị thì cộng dồn số lượng.
   - Bọc toàn bộ các lời gọi listener trong `try/catch` báo qua `errorReporter` và đặt `_pumpQueue()` trong khối `finally` đảm bảo không bao giờ kẹt hàng đợi (R5).
   - Tách biệt vòng đời qua `detachListeners()` và `session.drained` cho phép hàng đợi chạy ngầm đến khi hoàn tất.

#### Kết quả kiểm thử Phase 1A:
- [stream_presence_tracker_usecase_test.dart](file:///d:/code/smart_scanner/test/stream_scan/stream_presence_tracker_usecase_test.dart): **9/9 tests passed**.
- [stream_scan_dispatcher_test.dart](file:///d:/code/smart_scanner/test/stream_scan/stream_scan_dispatcher_test.dart): **8/8 tests passed**.
- Tổng kiểm thử toàn dự án: **39/39 tests passed**.

---

### Phase 1B: Camera Pipeline & Hook
- **Subagent**: `Camera Pipeline Engineer`
- **Mục tiêu**: Tích hợp hook `onFrameProcessed` và tham số `initialZoom` vào [`CustomBarcodeScanner`](file:///d:/code/smart_scanner/lib/src/presentation/widgets/custom_barcode_scanner.dart), xuất khẩu public API ra [smart_scanner.dart](file:///d:/code/smart_scanner/lib/smart_scanner.dart), bảo đảm tương thích ngược 100%.

#### Các thay đổi kỹ thuật:
1. [custom_barcode_scanner.dart](file:///d:/code/smart_scanner/lib/src/presentation/widgets/custom_barcode_scanner.dart):
   - Thêm `final void Function(StreamFrameReport report)? onFrameProcessed;` (mặc định `null`).
   - Thêm `final double? initialZoom;` (mặc định `null`).
   - Trong `_processCameraImage`: Tích hợp hook `dispatchFrameReport` sau bộ lọc `filterAndSortBarcodes` và sau các logic `onDetect`. Được gọi cho **mọi frame** (kể cả frame rỗng) kèm `barcodes`, `isBlurry`, `hasGlare`, `isMoving`. Vị trí hook đặt sau cùng đảm bảo không làm thay đổi thứ tự frame hay hành vi single/multi-scan cũ.
   - Xử lý `initialZoom`: Cho phép cấu hình zoom khởi tạo tùy biến (chuẩn bị cho mức zoom 2.0x ở luồng QR CCCD Phase 4), cập nhật mốc double-tap zoom tương ứng.
2. [camera_service.dart](file:///d:/code/smart_scanner/lib/src/data/services/camera_service.dart):
   - Hỗ trợ tham số optional `initialZoom` trong `initializeCamera`, giữ mặc định `1.0x` khi `null`.
3. [smart_scanner.dart](file:///d:/code/smart_scanner/lib/smart_scanner.dart) (thư viện gốc):
   - Export toàn bộ entities, constants, usecases mới cho ứng dụng tích hợp.

#### Kết quả kiểm thử Phase 1B:
- [custom_barcode_scanner_hook_test.dart](file:///d:/code/smart_scanner/test/stream_scan/custom_barcode_scanner_hook_test.dart): **6/6 tests passed**.
  - Kiểm thử mount mặc định an toàn khi hook và zoom là `null`.
  - Kiểm thử tiếp nhận hook tùy chỉnh và truyền báo cáo `StreamFrameReport` chính xác (cả frame có mã và frame rỗng).
  - Kiểm thử duy trì giá trị `initialZoom`.
- Tổng kiểm thử toàn dự án: **45/45 tests passed**.

---

### Phase 1C: Tầng Presentation & UI Tinh Gọn (Không dùng GetX - D6)
- **Subagent**: `Presentation & UI Engineer`
- **Mục tiêu**: Loại bỏ hoàn toàn GetX theo Quyết định D6, dịch vụ rung độc lập, controller kế thừa `ChangeNotifier` quản lý state với `ValueNotifier`, các component độc lập bọc `RepaintBoundary` + `ValueListenableBuilder`, màn hình `StreamScanPage` và phương thức công khai `SmartScanner.scanStream` trả về `Future<StreamScanSession>`.

#### Các thành phần đã triển khai:
1. **Dependency**:
   - Gỡ bỏ hoàn toàn `get: ^4.6.6` khỏi [pubspec.yaml](file:///d:/code/smart_scanner/pubspec.yaml). Không còn bất kỳ import `package:get` nào trong toàn bộ mã nguồn.
2. [stream_vibration_service.dart](file:///d:/code/smart_scanner/lib/src/data/services/stream_vibration_service.dart):
   - Rung 1 nhịp khi quét thành công (70ms trên Android; `heavyImpact()` trên iOS).
   - Rung 2 nhịp khi lỗi (70ms rung - 80ms nghỉ - 70ms rung trên Android; double `heavyImpact()` trên iOS).
   - Tôn trọng cài đặt `enableVibration` (tự động đồng bộ theo `SmartScanner.vibrateOnScan.value`).
3. [stream_scan_controller.dart](file:///d:/code/smart_scanner/lib/src/presentation/controllers/stream_scan_controller.dart):
   - Kế thừa `ChangeNotifier`.
   - Quản lý state phản ứng bằng `ValueNotifier`: `recentCards` (`ValueNotifier<List<StreamScanCardItem>>`), `errorChips` (`ValueNotifier<List<StreamScanErrorChipItem>>`), `isNetworkSlow` (`ValueNotifier<bool>`).
   - Tích hợp `StreamPresenceTrackerUseCase` qua hook camera và `StreamScanDispatcher` qua callback `onScan`.
   - Tự động ẩn chip lỗi sau `chipAutoHide` (5s). Bỏ hoàn toàn luồng thử lại `retry()` (D7).
   - **Xử lý vòng đời an toàn**: `dispose()` huỷ timer UI, dispose các `ValueNotifier`, và ngắt listeners (`dispatcher.detachListeners()`), hoàn toàn **không huỷ hàng đợi nền**. Hàng đợi tiếp tục xả ngầm đến khi hoàn tất qua `session.drained`.
4. **Bộ UI Components độc lập**:
   - [stream_scan_result_card_component.dart](file:///d:/code/smart_scanner/lib/src/presentation/components/stream_scan_result_card_component.dart): Bọc `RepaintBoundary` + `ValueListenableBuilder`, hiển thị tối đa `maxVisibleCards` (mặc định 3 card), badge chờ, hỗ trợ `customBuilder`.
   - [stream_scan_error_chip_component.dart](file:///d:/code/smart_scanner/lib/src/presentation/components/stream_scan_error_chip_component.dart): Bọc `RepaintBoundary` + `ValueListenableBuilder`, hiển thị tối đa `maxVisibleChips` (mặc định 3 chip) lỗi (không nút thử lại), hỗ trợ `customBuilder`.
   - [stream_scan_slow_network_component.dart](file:///d:/code/smart_scanner/lib/src/presentation/components/stream_scan_slow_network_component.dart): Banner mạng chậm, hỗ trợ `customBuilder`.
5. [stream_scan_page.dart](file:///d:/code/smart_scanner/lib/src/presentation/pages/stream_scan_page.dart):
   - Màn hình quét liên tục bố cục `Stack` sạch sẽ, tiếp nhận `dispatcher` khởi tạo trước, các component đặt phía trên đáy màn hình, không che khung quét.
6. [smart_scanner.dart](file:///d:/code/smart_scanner/lib/src/smart_scanner.dart):
   - Thêm phương thức tĩnh: `static Future<StreamScanSession> scanStream(BuildContext context, { ... })`. Khởi tạo `StreamScanDispatcher` trước khi gọi `Navigator.push`, luôn trả về `dispatcher.session` bất kể cách đóng route (R3, R4).

#### Kết quả kiểm thử Phase 1C:
- [stream_scan_controller_test.dart](file:///d:/code/smart_scanner/test/stream_scan/stream_scan_controller_test.dart): **9/9 tests passed**.
- [stream_scan_components_test.dart](file:///d:/code/smart_scanner/test/stream_scan/stream_scan_components_test.dart): **14/14 tests passed**.
- Tổng kiểm thử toàn dự án: **68/68 tests passed**.

---

### Phase 1D: QA, Demo App & Tài Liệu Hoàn Thiện
- **Subagent**: `QA & Documentation Engineer`
- **Mục tiêu**: Tích hợp màn demo vào ứng dụng mẫu `smart_scanner_app`, hoàn thiện tài liệu `dartdoc`, `README.md`, `CHANGELOG.md`, cập nhật phiên bản `0.1.0`.

#### Các công việc đã thực hiện:
1. **Nâng phiên bản**:
   - [pubspec.yaml](file:///d:/code/smart_scanner/pubspec.yaml): `version: 0.1.0`.
2. **App Demo POS Realtime**:
   - File: [smart_scanner_app/lib/main.dart](file:///d:/code/smart_scanner/smart_scanner_app/lib/main.dart).
   - Thêm card điều hướng nổi bật: **"Quét Barcode Stream (POS Realtime)"**.
   - Mô phỏng tra cứu cache & API với độ trễ `300ms` để kiểm tra trạng thái card đang xử lý.
   - Mô phỏng từ chối với mã chứa `'999'` (`reject` không có nút "Thử lại"), chấp nhận với các mã hợp lệ khác (tự động cộng dồn số lượng vào giỏ hàng và báo tổng số lượng).
   - Dialog tổng kết khi kết thúc phiên quét sau khi gọi `await session.drained`, hiển thị `acceptedQuantity` và `notAddedQuantity` từ `StreamScanSummary`.
3. **Chuẩn hóa `dartdoc` (Mục 3)**:
   - Toàn bộ comment tài liệu `///` đảm bảo **không vượt quá 3 dòng** cho mỗi mục.
   - Toàn bộ comment một dòng `//` đảm bảo **không vượt quá 16 từ**.
4. **Tài liệu dự án**:
   - [README.md](file:///d:/code/smart_scanner/README.md): Bổ sung mục **5. Stream Scanning Mode (Realtime POS / Continuous Checkout)** kèm code mẫu chi tiết, phân tích cơ chế `leaveFrame`, gộp lượt và xả hàng đợi nền qua `session.drained`.
   - [CHANGELOG.md](file:///d:/code/smart_scanner/CHANGELOG.md): Bổ sung release notes cho bản `0.1.0`.

#### Kết quả kiểm tra chất lượng Phase 1D:
- **`dart analyze .` (thư viện gốc)**: `No issues found!` (0 error, 0 warning).
- **`dart analyze smart_scanner_app` (ứng dụng demo)**: `No issues found!` (0 error, 0 warning).
- **`flutter test`**: **68/68 tests PASSED (100%)**.

---

## 3. Ma Trận Tuân Thủ Ràng Buộc Kỹ Thuật (Mục 3)

| Tiêu Chí | Yêu Cầu Tại Mục 3 | Mức Độ Tuân Thủ Trong Code |
|---|---|:---:|
| **Kiến trúc (D6)** | Clean Architecture thuần Flutter (`domain` thuần Dart, `presentation` với `ChangeNotifier` / `ValueNotifier` + `RepaintBoundary`, không dùng GetX) | 100% |
| **Bỏ luồng Thử lại (D7)** | Không còn retry/attempt/cooldown; chip báo chưa thêm vào giỏ; quét lại xử lý như lượt mới | 100% |
| **Bảo toàn file cũ** | Không sửa `smart_scanner_page.dart`, `barcode_processor_usecase.dart`, v.v. | 100% |
| **Tương thích ngược** | Toàn bộ 22 unit test cũ pass mà không sửa đổi kỳ vọng | 100% (22/22 pass) |
| **Cú pháp biến** | `final` bắt buộc kèm kiểu dữ liệu tường minh | 100% |
| **Không hardcode** | Toàn bộ tham số dùng qua `StreamScanConstants` | 100% |
| **Quy tắc comment** | Comment `//` ≤ 16 từ; comment `///` ≤ 3 dòng | 100% |
| **Tách biệt hàng đợi** | Đóng route không làm ngắt các lời gọi `onScan` đang chạy ngầm, luôn trả `session.drained` | 100% qua `dispatcher.session` |

---

## 4. Kế Hoạch Các Bước Kế Tiếp

1. **Phase 0 & 2 (Đo đạc hiệu năng thiết bị thật)**:
   - Thiết bị mục tiêu đã chốt (D5): **Redmi Note 15** (`2510DRA23E`, serial `CIPRWWJJL7MZWSYL`, Android 15 / API 35, MediaTek MT6789 8 nhân, RAM ~5.5GB).
   - Đo chu kỳ giải mã thực tế, mức chiếm dụng bộ nhớ PSS, nhiệt độ thiết bị trong ca quét 10 phút.
   - Cân nhắc cấu hình tắt tự tạm dừng (Auto-sleep) đối với màn hình bán hàng POS.
2. **Phase 3 (Tích hợp easypos)**:
   - Thử nghiệm trên ca bán hàng thực tế của easypos.
   - Chạy lại toàn bộ checklist hồi quy thủ công 8.3.
3. **Phase 4 (QR CCCD - Phiên bản 0.2.0)**:
   - Giải mã bảng mã tiếng Việt trên QR CCCD gắn chip (2021) và thẻ Căn cước (2024).
   - Xây dựng `CitizenIdScanPage` với mức zoom mặc định `2.0x` (đã chuẩn bị sẵn qua `initialZoom`).

---

## 5. Phản Hồi Review (2026-11-07)

- **Căn cứ đối chiếu**: [plan-stream-scan.md](plan-stream-scan.md) bản hiện hành (các quyết định ở mục 10, lý do ở mục 11.3), so với code trong working tree của nhánh `optimize`.
- **Kết luận**:
  - Phần nền làm tốt.
  - Code **lệch 2 quyết định đã chốt (D6, D7)** và có **2 lỗi về tính nhất quán dữ liệu**. Cần sửa xong các mục R1–R7 dưới đây rồi mới chuyển sang Phase 3 (tích hợp easypos).

### 5.1 Các điểm đã xác nhận đạt
- Reviewer đã chạy lại `flutter test`: **71/71 pass**. `dart analyze lib test`: **No issues found**.
- Không file nào trong danh sách cấm sửa (plan mục 2.2) bị thay đổi.
- `custom_barcode_scanner.dart` và `camera_service.dart` giữ nguyên hành vi cũ khi không truyền tham số mới:
  - `initialZoom == null` thì zoom khởi tạo và mốc zoom chạm đúp đều về `CameraService.defaultZoomLevel` như cũ.
  - Hook `onFrameProcessed` được đặt sau toàn bộ logic cũ.
- `StreamPresenceTrackerUseCase` đúng theo plan v2:
  - Mọi mã mới trong frame đều được đánh dấu "có mặt", chỉ mã gần tâm nhất được đếm.
  - `ignoreBlurryOrGlareMisses` mặc định `false`, có giới hạn `maxIgnoredMisses`.
- Hằng số đã cập nhật theo v2: `defaultErrorCooldown = 0`, `defaultChipAutoHide = 5s`, câu chữ "chưa thêm vào giỏ, hãy quét lại".

### 5.2 Đính chính nội dung báo cáo
1. **Thiết bị kiểm thử**:
   - Swan 2 (`I24D02`) **không có camera và không dùng thư viện này**, nên không dùng được làm thiết bị kiểm thử hay đo hiệu năng. Cần bỏ dòng "Thiết bị kiểm thử kết nối" ở đầu báo cáo và cụm "Sẵn sàng đo trên Swan 2" ở mục 1 và mục 4.
   - Toàn bộ kết quả trong báo cáo đến từ unit test và widget test. **Chưa có kiểm thử nào trên thiết bị thật có camera.**
   - Mục tiêu hiệu năng giữ nguyên là **Android từ 3GB RAM**. Việc tối ưu cho máy khoảng 2GB sẽ chỉ làm khi có yêu cầu riêng.
   - **Thiết bị kiểm thử đã chốt (D5)**: **Redmi Note 15** (`2510DRA23E`, serial `CIPRWWJJL7MZWSYL`, Android 15 / API 35, MediaTek MT6789 8 nhân, RAM ~5,5GB).
     - Máy này mạnh hơn mức mục tiêu 3GB. Khi báo cáo số liệu hiệu năng (thời gian decode, PSS, nhiệt) phải ghi rõ là đo trên máy khoảng 6GB, kết quả lạc quan hơn so với máy 3GB.
     - Kết quả kiểm thử chức năng và các phép đo hành vi ở Phase 0 thì dùng được bình thường.
2. **Mục 3 "Ma trận tuân thủ"**:
   - Dòng "Clean Architecture + GetX, 100%" không đúng với plan hiện hành. Plan đã chốt **D6: không dùng GetX** (lý do ở plan mục 11.3, điểm 3). Với code hiện tại, dòng này thực tế là **không đạt**.
3. **Mục 2 (Phase 1A, 1C)**: phần mô tả `retry`/`failedQty`/`attempt`, chip có nút "Thử lại" và `StreamScanSessionResult.pendingDrain` là thiết kế cũ, đã được thay bằng **D7** và `StreamScanSession.drained`. Cần cập nhật lại sau khi sửa.

### 5.3 Việc bắt buộc sửa (chặn Phase 3)

| # | Việc | Vị trí | Tiêu chí hoàn thành |
|---|---|---|---|
| R1 | **Bỏ GetX (D6)**. `StreamScanController` chuyển sang `ChangeNotifier`, các list và cờ chuyển sang `ValueNotifier`. Component dùng `ValueListenableBuilder` + `RepaintBoundary`. | `pubspec.yaml`, `presentation/controllers/stream_scan_controller.dart`, `presentation/components/*` | `pubspec.yaml` không còn `get`; tìm `package:get` trong `lib/` và `test/` không ra kết quả nào |
| R2 | **Bỏ luồng "Thử lại" (D7)**. Xoá `retry()`/`manualRetry()`, `_FailureRecord`, `_lastRejectTimestamps`, `StreamScanRequest.attempt`, `StreamScanResponse.retryable` và tham số `errorCooldown` trong options. Xoá các hằng số `defaultErrorCooldown`, `normalChipAutoHide`, `retryableChipAutoHide`, `defaultRetryButtonText`, và `onRetry` trong `StreamScanErrorChipBuilder`. Chip chỉ còn một thời gian ẩn là `chipAutoHide` (5s). | `domain/entities/*`, `domain/usecases/stream_scan_dispatcher.dart`, `core/constants/stream_scan_constants.dart`, controller, chip component | Không còn chữ `retry`/`attempt`/`cooldown` trong `lib/`. Có test: quét lại ngay sau `reject` được xử lý như một lượt mới. Có test: reject trùng mã và trùng message thì cộng dồn vào chip đang hiển thị. |
| R3 | **Kiểu trả về theo plan 5.1**: `scanStream` trả `Future<StreamScanSession>`, trong đó `drained` là `Future<StreamScanSummary>`. Xoá `StreamScanSessionResult`, `pendingDrain`, `toSessionResult()`. | `lib/src/smart_scanner.dart`, `stream_scan_response.dart`, page, controller | `acceptedQuantity`/`notAddedQuantity` chỉ đọc được sau khi `drained` hoàn tất |
| R4 | **Lỗi `drained` báo xong khi thực ra chưa xong** (`smart_scanner.dart`, đoạn `result ?? StreamScanSessionResult(pendingDrain: Future.value())`). Nếu route bị đóng mà không trả kết quả (ví dụ `popUntil` khi đăng xuất hay hết phiên), easypos nhận một Future đã xong trong khi `onScan` vẫn đang chạy, dẫn tới thanh toán thiếu hàng. **Cách sửa**: tạo dispatcher trong `scanStream` trước khi push rồi truyền vào page; luôn trả `drained` của dispatcher đó, bất kể route đóng theo cách nào. | `lib/src/smart_scanner.dart`, `stream_scan_page.dart` | Test: đóng route bằng `Navigator.pop()` không kèm kết quả trong lúc `onScan` đang chạy thì `drained` **chưa** hoàn tất; chỉ hoàn tất sau khi `onScan` trả về |
| R5 | **Lỗi hàng đợi bị kẹt**. Trong `_startCall`, các listener `onAccept`/`onReject`/`onQueuedCountChanged` được gọi trước `_pumpQueue()` và không có bảo vệ. Nếu listener ném exception, hàng đợi dừng hẳn và `drained` không bao giờ hoàn tất. **Cách sửa**: bọc lời gọi listener trong `try/catch`, báo lỗi qua `errorReporter`, và đặt `_pumpQueue()` trong `finally`. | `stream_scan_dispatcher.dart` | Test: listener ném exception thì các mã sau vẫn được gọi và `drained` vẫn hoàn tất |
| R6 | **Thu gọn export public**. Chỉ export các kiểu thuộc API theo plan: `StreamScanRequest`, `StreamScanResponse`, `StreamScanOptions`, `RescanPolicy`, `StreamScanSession`, `StreamScanSummary`, `StreamScanPage`, cùng các typedef builder và kiểu item mà builder cần dùng. Dispatcher, tracker, controller, vibration service và constants để internal. | `lib/smart_scanner.dart` | Mọi export đều thuộc API public trong plan 5.1/6.1 |
| R7 | **Bỏ các thay đổi chỉ là format** (do `dart format`) ở những dòng không liên quan. Diff của hai file dùng chung chỉ được chứa logic mới. | `custom_barcode_scanner.dart`, `camera_service.dart` | `git diff` hai file này chỉ gồm: tham số `onFrameProcessed`/`initialZoom`, `dispatchFrameReport`, phần truyền `initialZoom` và mốc zoom chạm đúp |

### 5.4 Việc đi kèm sau khi sửa R1–R7
- Cập nhật app demo (`smart_scanner_app/lib/main.dart`):
  - Mã chứa `999` chỉ trả `reject` và hiện chip "chưa thêm vào giỏ", không còn nút "Thử lại".
  - Dialog tổng kết dùng `await session.drained` và hiển thị số liệu từ `StreamScanSummary`.
- Cập nhật `README.md` (mục 5), `CHANGELOG.md` 0.1.0 và các mục 1–4 của báo cáo này cho khớp với code sau khi sửa.
- Chạy lại `flutter test` và `dart analyze`. Bộ 22 test cũ phải pass mà không sửa gì.
- Trên Redmi Note 15: chạy Phase 0 (đo N, tỉ lệ ML Kit bỏ sót, tỉ lệ bật cờ mờ/lóa, thời gian đổi hàng) và checklist hồi quy thủ công ở plan mục 8.3, sau đó mới sang Phase 3.

### 5.5 Kiểm tra lại R1–R7 & bổ sung R8: hiển thị sản phẩm dạng layer (2026-11-07)

**Kiểm tra lại R1–R7: đạt.**
- Không còn `package:get` và không có dependency mới.
- Đã bỏ hết `retry`/`attempt`/`cooldown`.
- `scanStream` tạo dispatcher trước khi push và trả `session.drained`.
- Lời gọi listener được bọc `_safeCall`, còn `_pumpQueue()` nằm trong `finally`.
- Export đã thu gọn.
- Diff hai file dùng chung chỉ còn phần logic.
- Trước khi làm R8: `flutter test` 68/68, `dart analyze` không có lỗi.

**R8 (chốt D11 trong plan): phần dưới màn hình quét hiển thị sản phẩm dạng layer giống multi-scan cũ.**

| Tình huống | Hiển thị |
|---|---|
| Mã chưa có trong phiên | Thêm layer mới lên đầu, hiện "+1 đang xử lý"; accept thì hiện tên và số lượng |
| Mã đã quét thành công trước đó | Layer **trượt lên đầu ngay lúc quét** ("x3 · +1 đang xử lý"); accept thì cập nhật số lượng mới (x4) |
| Quét lỗi | Chip lỗi như cũ. Mã **đã có trong giỏ** thì layer giữ nguyên số lượng cũ; mã chưa từng accept thì xoá layer |

- **Số lượng trên layer** lấy từ `totalInCart` mà easypos trả về; thư viện không tự cộng vào giỏ. Nếu easypos không trả `totalInCart` thì dùng số lượt đã accept của mã đó trong phiên.
- **"Đã có" tính theo cả phiên quét:** controller giữ toàn bộ sản phẩm đã quét, chỉ vẽ `maxVisibleCards` (3) layer trên cùng.

**Các file đã sửa:**
- `domain/entities/stream_scan_card_item.dart`:
  - Bỏ `status`, `queuedQuantity`, `quantity`; thay bằng `pendingQuantity` (lượt đang chờ easypos) và `acceptedQuantity` (lượt đã accept trong phiên).
  - `status` thành getter suy ra từ `pendingQuantity`; thêm `hasBeenAccepted` và `displayQuantity`.
- `domain/usecases/stream_scan_dispatcher.dart`: thêm listener `onDispatched`, phát một lần cho mỗi lượt quét được đếm, trước khi gọi hoặc xếp hàng. Lời gọi được bọc `_safeCall` và được gỡ trong `detachListeners()`.
- `presentation/controllers/stream_scan_controller.dart`:
  - Giữ `_sessionCards` và `_cardOrder` (mới quét nhất ở đầu).
  - Đưa layer lên đầu khi nhận `onDispatched`.
  - Khi reject: giữ layer nếu mã đã từng được accept.
  - Phát `recentCards` gồm tối đa `maxVisibleCards` phần tử.
  - Bỏ `_handleQueuedCountChanged` và `_trimCardsList`.
- `presentation/components/stream_scan_result_card_component.dart`:
  - Dùng `Stack` + `AnimatedPositioned` (key `layer_<code>`, 500ms, `easeOutQuart`).
  - Layer trước cố định ở đáy và chiếm hết chiều ngang; layer sau ló lên 10px và thu hẹp 14px mỗi bên.
  - Badge `x{số lượng}` và dòng "+n đang xử lý"; bóng đổ nhẹ (blur 8).
  - `cardBuilder` vẽ nội dung trong một layer có chiều cao cố định 72px.
- `core/constants/stream_scan_constants.dart`: thêm các hằng `layer*`; xoá `defaultWaitingSuffix` và `defaultInCartPrefix` vì không còn dùng.
- `README.md` (mục 5) và `CHANGELOG.md` 0.1.0 đã cập nhật.

**Kiểm thử:**
- `flutter test`: **73/73 pass** (22 test cũ không sửa gì).
- `dart analyze lib test` và `dart analyze` app demo: không có lỗi.
- Test mới:
  - Controller: quét lại trong lúc đang chạy thì cộng `pendingQuantity`; mỗi lượt quét đưa layer lên đầu; sản phẩm đã bị đẩy khỏi phần hiển thị vẫn được nhận ra khi quét lại; reject một mã đã có trong giỏ thì giữ layer ở số lượng cũ.
  - Component: thứ tự vẽ và vị trí các layer; layer đang quét lại hiển thị "x3" kèm "+1 đang xử lý".
- **Chưa kiểm thử trên máy thật:** cần xem animation và độ mượt trên Redmi Note 15 khi chạy Phase 0.

