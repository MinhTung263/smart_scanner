# Báo cáo: Thư viện smart_scanner hỗ trợ easypos – Bán hàng nhanh (Quét hàng loạt mã vạch)

- **Dự án**: `smart_scanner` 0.1.0, nhánh `optimize`
- **Ngày**: 2026-11-09
- **Căn cứ**: Confluence 60568906 (bản 11) và các quyết định A–D của chủ dự án
- **Trạng thái**: code, test và app demo đã xong. Chưa chạy trên máy thật, chưa commit.

---

## 1. Kết quả kiểm tra

| Hạng mục | Kết quả |
|---|---|
| `flutter analyze lib test` | Sạch |
| Test (`flutter test`) | 104/104 đạt |
| App demo `smart_scanner_app` | Analyze sạch |
| File của luồng quét cũ | Không bị thay đổi |
| Chạy thử trên Redmi Note 15 | Chưa |
| Checklist hồi quy các màn quét cũ | Chưa |

---

## 2. Các quyết định đã chốt

| Mã | Nội dung | Kết quả |
|---|---|---|
| A | Bỏ chống trùng 1 giây | Chỉ dùng leaveFrame (`missedFrames = 2`) |
| B | Bỏ nút "Hoàn thành" | Chạm thẻ sản phẩm thì thoát để easypos mở giỏ hàng |
| C | Bộ đếm | Ban đầu tắt, sau đó chủ dự án chốt lại: vẫn hiện khi bật quét liên tục, ẩn khi chưa quét được sản phẩm nào |
| D | Không ưu tiên toast lỗi | Giữ nguyên, toast lỗi thay thế toast thành công |
| E (theo BR-012) | Nút X / back | Thoát ngay, không hỏi xác nhận, giữ nguyên giỏ hàng |

Đã được chủ dự án xác nhận (2026-11-09): bấm X hoặc back thì hàng đã tự thêm vào giỏ nên không cảnh báo. Việc bỏ nút "Hoàn thành" chỉ áp dụng cho màn quét hàng loạt; các màn quét cũ giữ nguyên nút "Hoàn thành".

---

## 3. Thư viện cung cấp gì cho easypos

### 3.1 Giao tiếp

```dart
final StreamScanSession session = await SmartScanner.scanStream(
  context,
  onScan: (StreamScanRequest req) async { ... },
  options: StreamScanOptions(...),
  enableVibration: null,
  cardBuilder: ..., chipBuilder: ..., slowNetworkBuilder: ...,
);
```

- `StreamScanRequest` gồm `code`, `format`, `quantity`.
- `onScan` được gọi ngay khi quét được mã, không đợi thoát màn.
- Cùng một mã được xử lý tuần tự. Lượt quét thêm trong lúc chờ được gộp vào `quantity`.
- Mã khác nhau chạy song song, tối đa `maxConcurrent` (mặc định 2).

### 3.2 Phản hồi từ easypos

| Trả về | Hành vi trên màn quét |
|---|---|
| `StreamScanResponse.accept(title, subtitle, totalInCart)` | Thẻ sản phẩm, rung 1 nhịp, khung nháy xanh, toast xanh "Thêm vào giỏ hàng thành công" |
| `StreamScanResponse.reject(message)` | Rung 2 nhịp, khung nháy đỏ, toast đỏ kèm số lượng chưa thêm. Hủy các lượt đang chờ của mã đó để quét lại ngay |

- Mã đã có trong giỏ mà bị từ chối: thẻ giữ số lượng cũ, chỉ hiện toast lỗi.
- Mã chưa từng được chấp nhận mà bị từ chối: thẻ bị gỡ.

### 3.3 Quy tắc kiểm tra mã do easypos truyền vào (Phần 7)

- `StreamScanOptions.validator` có kiểu `String? Function(String code, BarcodeFormat format)`. Trả `null` là hợp lệ, trả chuỗi là nội dung toast lỗi.
- Mã không hợp lệ: nháy đỏ, rung, hiện toast. Mã đó không vào `onScan`, thẻ hay bộ đếm.
- Mặc định không kiểm tra gì. Thư viện không chứa quy tắc cứng.
- Có sẵn, tùy chọn dùng:
  - `StreamScanValidators.gs1CheckDigit()`: EAN-13, EAN-8, UPC-A, UPC-E, ITF-14.
  - `StreamScanValidators.all([...])`: gộp nhiều quy tắc.
- Validator ném lỗi: báo qua `FlutterError`, mã vẫn được cho đi tiếp.

### 3.4 Giao diện màn quét

| Phần | Hành vi |
|---|---|
| Công tắc quét liên tục | Tắt: quét một mã rồi tạm dừng, hiện "Chạm để quét tiếp". Mã không hợp lệ không làm dừng |
| Thẻ sản phẩm (Phần 4) | Ẩn đến khi quét được mã đầu tiên. Xếp chồng tối đa 3 lớp, mới nhất ở trên |
| Bộ đếm (Phần 5) | Nằm ngay phía trên chồng thẻ sản phẩm. Ẩn khi tắt quét liên tục và ẩn đến khi quét được sản phẩm đầu tiên |
| Toast (Phần 6) | Mỗi lúc chỉ hiện một toast: lỗi (đỏ), thành công (xanh), thông tin |
| Mạng chậm | Chỉ báo sau 3 giây chưa có phản hồi, không hủy request |
| Camera | Zoom 1x/2x/3x, flash, chạm lấy nét, tự ngủ sau 60 giây, giảm tốc độ khung hình khi đứng yên |
| Tùy biến | `cardBuilder`, `chipBuilder`, `slowNetworkBuilder`, `enableVibration` |

### 3.5 Thoát màn và chuyển sang giỏ hàng

- Không còn nút "Hoàn thành" và không có hộp thoại xác nhận.
- Nút quay lại hoặc back hệ thống: thoát ngay, giữ giỏ hàng, `session.exitReason == StreamScanExitReason.back`.
- Chạm thẻ sản phẩm: thoát ngay, `exitReason == StreamScanExitReason.cardTap`. easypos dựa vào đây để mở màn giỏ hàng.
- `await session.drained` chờ các request chạy ngầm xong và trả `StreamScanSummary` (`acceptedQuantity`, `notAddedQuantity`, `acceptedByCode`).

---

## 4. Thay đổi API so với bản nháp trước

Thư viện chưa phát hành bản có các mục dưới đây, nên easypos chưa bị ảnh hưởng.

- Bỏ tham số `finishButtonBuilder` và `exitConfirmBuilder` của `scanStream`.
- Bỏ `StreamScanSession.isDiscarded`, thay bằng `exitReason`.
- Thêm `StreamScanExitReason { back, cardTap }`.
- Thêm `StreamScanOptions.validator`, `StreamScanValidators`, `StreamScanChipKind.success`.

---

## 5. Việc còn lại và rủi ro

| # | Việc | Ghi chú |
|---|---|---|
| 1 | Build lên Redmi Note 15 và chạy checklist hồi quy các màn quét cũ (mục 8.3 của plan) | Chưa làm, đây là bước xác nhận chính |
| 2 | Cập nhật [plan-stream-scan.md](plan-stream-scan.md) và báo cáo phase theo bản 11 | Plan vẫn mô tả nút "Hoàn thành" và hộp xác nhận |
| 3 | Nút đổi camera trước/sau | Chưa làm |
| 4 | Kiểm tra quyền camera trên màn Bán hàng | Cần quyết định đặt ở easypos hay trong thư viện |
| 5 | Báo BA | Danh sách lỗi chưa đầy đủ, mâu thuẫn bộ đếm "0 \| 0", lỗi chính tả tiêu đề |
| 6 | Âm báo (BR-007) | Hoãn |
| 7 | Quét CCCD (Phase 4) | Làm sau |

**Lưu ý kỹ thuật**: ML Kit có thể đã tự loại một số mã EAN sai số kiểm tra. Khi đó validator `gs1CheckDigit` ít khi được kích hoạt với các định dạng này. Cần kiểm chứng trên máy thật.
