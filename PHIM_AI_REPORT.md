# AnPinime 2.7.0 (17) — Phim ngắn, Khám phá và player

**Bản giao:** [IPA unsigned, artifact 13199392297](https://github.com/thuyan1510/AnPinime/actions/runs/41565698005/artifacts/13199392297).
Mã ứng dụng `e6ee6dc02624ae27e4cce38011a9c1fa26fcb570`,
[run 41565698005](https://github.com/thuyan1510/AnPinime/actions/runs/41565698005).
Nhánh `feature/ai-drama`, [PR #2](https://github.com/thuyan1510/AnPinime/pull/2),
tiếp nối nhánh sửa nguồn 2 tại `a785d35`; chưa gộp vào main.

IPA đã được mở để kiểm tra `Info.plist`: **2.7.0 (17)**,
`com.xemphim.aipinime`, iOS tối thiểu 15.0, có background audio, không có
provisioning profile/chữ ký app. SHA-256:
`0b80b998655f8f769c9a2c3f4a3041e9cddce825e1fa93c947fcb4ff60635fac`.
[Danh tính artifact](Tools/evidence/2026-11-03-short-feed/release-artifact.json).

## Giao diện

Ba thư viện ngang hàng là **Anime / Phim / Phim AI**. Phim AI có bốn tab:
**Trang chủ / Phim ngắn / Khám phá / Cài đặt**. Ba mục **Thịnh hành / Danh mục /
Mới** nằm trong Khám phá; giữ dữ liệu thật, bốn hàng lọc và tải tiếp native.

**Phim ngắn** dùng feed riêng của PineDrama, không lấy lại bảng xếp hạng.
Lướt dọc chuyển video; video ngang nằm vừa trong màn hình dọc. Nút toàn màn
hình xoay ngang cùng player và giữ tiến độ. Chỉ giữ tên phim, tập, phát/tạm
dừng, toàn màn hình và **Phát tất cả**. Không thêm tim, bình luận, chia sẻ.

**Phát tất cả** lấy panel của đúng collection, kiểm tra đầy đủ rồi mở đúng
tập đang xem. Dừng preview trước khi player danh sách nhận quyền phát. Feed
tải tiếp theo ID video đã nhận, loại trùng và dừng nếu không còn ID mới.
URL video được lấy mới theo tập, không lưu vào lịch sử.

Một bộ nhận cử chỉ chung xử lý vuốt trên cả video và vùng phủ; UIKit thực
hiện hoạt ảnh chuyển trang. Cách này giữ nút bấm hoạt động và tránh tranh
chấp giữa vùng phủ/scroll recognizer. Các phản hồi trễ không được lắp player
cho tập đã bỏ qua. Chỉ tập hiện tại sở hữu player đang phát.

Banner Home kéo tới đỉnh sau nút đổi thư viện/nguồn đặt chồng lên ảnh. Đã bỏ
nút tải lại trên Home. Toàn bộ thẻ/kết quả gồm ảnh, tên và vùng trống mở đúng
phim. Anime vẫn có Lịch chiếu; thư viện Phim giữ các tab riêng của nó.

## Cài đặt phát và PiP

IPA Phim4K gốc có sáu nhóm **Âm thanh / Phụ đề / Hiển thị / Tốc độ / Chung /
Thông tin**. Menu mới dùng hàng tab ngang, vùng tùy chọn cuộn và hàng chọn
track lớn. Hiển thị có tỷ lệ video, lấp đầy khung hình và kiểu phụ đề. Menu
cũng có trong player AI; lựa chọn audio/subtitle/file rời nối tới ID track
thật. AI ghi nhớ tốc độ và dùng tùy chọn tự chuyển tập của người dùng.

PiP native dùng AVSampleBufferDisplayLayer cùng decoder/âm thanh mpv. Chỉ
PiP chuyển sang khung render CPU nhỏ; phát thường giữ Metal và các tùy chọn
cache/hardware decoding cũ. Khi trở về, GPU nhận output trước khi giải phóng
render context PiP. Có nút cửa sổ nổi, tùy chọn PiP khi rời app và background
audio. AVPlayer/WKWebView bật khả năng PiP của hệ thống; web player còn phụ
thuộc trang phát.

**Chưa xác nhận cửa sổ PiP tự bật trên iPhone vật lý.** Kiểm tra simulator
bên dưới xác nhận frame/pause/seek/restore; không thay cho hành vi hệ thống
trên điện thoại hoặc chứng nhận mọi web player hỗ trợ PiP.

Nguồn 2 hiển thị `S01E001` thành **Tập 1** bằng thuộc tính trình bày riêng.
Tên tập gốc, công thức ID lịch sử và ID lookup mùa/tập giữ nguyên. Catalog
nguồn 2 trở lại byte-identical với baseline; không sửa dữ liệu để đổi nhãn.

## Kết quả của đúng bản giao

Bốn XCTest fixture và hai XCTest live đều **PASS** trong run `41565698005`:

| Kiểm tra | Thời gian |
| --- | ---: |
| Khám phá, phân trang, bốn bộ lọc, đổi thư viện | 101.680 giây |
| Phim ngắn: phát ngang/dọc, vuốt, tải tiếp, Phát tất cả, dọn player | 24.635 giây |
| Player tập, chọn phụ đề thật, hủy tập trễ, pause/background, history | 62.045 giây |
| Bấm các phần của hàng tìm kiếm chọn đúng phim | 12.791 giây |
| Live catalog → panel đầy đủ → đúng tập đầu/hai/cuối | 53.247 giây |
| Live feed → xoay cùng video → panel đầy đủ → phát tập cuối | 50.791 giây |

JSON playback native của cùng run xác nhận:

- MKV tự phát, hai audio và hai làn phụ đề; **13 frame PiP hợp lệ**, pause,
  seek và restore GPU thành công, playback tiếp tục tới **9.958 giây**.
- HLS nguồn 2 qua relay: giải mã **640×360**, thời gian tiến tới **3.440 giây**.
- Anime fixture qua danh sách tập động/resolver: **320×180**, **3.583 giây**.
- Gateway nguồn 2 dùng metadata Core đã lưu: **1920×1080**, **15.641 giây**;
  đây không phải xác nhận fresh Core catalog.

CLI parser/provider/protocol/JS và AI provider/store cũng đạt. Bài kiểm tra
ID nguồn 2 xác nhận nhãn mới giữ nguyên persistence key và lookup IDs. Thứ
tự phản hồi chậm đối chiếu bằng **đúng episode ID**, không lẫn hai bộ có
cùng số tập trong các bài kiểm tra dùng chung fixture.

[Kết quả từng phép thử và hash JSON](Tools/evidence/2026-11-03-short-feed/run-41565698005-final.json).
[Bằng chứng feed gốc và phạm vi bảo vệ](Tools/evidence/2026-11-03-short-feed/README.md).
Các snapshot `partial`/baseline giữ lịch sử điều tra; không dùng IPA cũ làm
bản giao. Không suy ra playback chỉ từ trạng thái workflow/build xanh.

## Phạm vi bảo vệ và phần chưa xác nhận

Ba nhãn Movie là **Anpinime Free / Anpinime Premium / Anpinime dự phòng**.
Raw source cases, URL/ID lịch sử và routing nguồn 1/3 không đổi. Hash của
parser, catalog, provider, relay và cấu hình mpv thường được so với baseline.
Player/menu/banner chung thay đổi theo yêu cầu này.

Các kiểm tra live **AnimeVietsub, Free1 và fresh Core** trong run này chưa
phát thành công; ghi riêng trong kết quả, dù các bước optional không chặn
IPA. Gateway có metadata lưu phát được không chứng minh fresh Core đã sửa.
Các bộ có tổng catalog khác panel vẫn báo chưa đủ danh sách, ví dụ mẫu cũ
45 tập nhưng panel chỉ 41; không tự nhận đó là trọn bộ.

Chưa kết luận đã sửa hết tốc độ/lag MKV trên iPhone. Các tối ưu directory
cache/probe giới hạn từ 2.6 được giữ, không cache URL video có thời hạn và
không tráo server. Mẫu Người Nhện có đoạn mở đầu đen; đo Linux hoặc gateway
không thay cho startup fresh Core trên máy người dùng.
[Phân tích startup nguồn 2](Tools/source2-startup-analysis.md),
[kết quả iOS trước đó](Tools/evidence/2026-11-02-source2-startup/ios-startup-results.json).
