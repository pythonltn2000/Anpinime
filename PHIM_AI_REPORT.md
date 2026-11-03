# AnPinime 2.7.0 (17) — Phim ngắn, Khám phá và player

Nhánh `feature/ai-drama`, [PR #2](https://github.com/thuyan1510/AnPinime/pull/2),
tiếp nối nhánh sửa nguồn 2 tại `a785d35`; chưa gộp vào main.
**Bản giao cuối: đang chờ kiểm tra native và IPA cùng mã nguồn cuối.**

## Giao diện theo yêu cầu mới

Ba thư viện ngang hàng vẫn là **Anime / Phim / Phim AI**. Phim AI có bốn tab:
**Trang chủ / Phim ngắn / Khám phá / Cài đặt**. Ba mục **Thịnh hành / Danh mục /
Mới** nằm trong Khám phá; dữ liệu, bốn hàng lọc và phân trang native được giữ.

Phim ngắn lấy endpoint feed riêng của PineDrama, không lấy lại một trang xếp
hạng rồi đổi tên. Lướt dọc chuyển giữa các video được giới thiệu; chỉ trang
đã chọn sở hữu player. Video ngang nằm vừa trong màn hình dọc; nút toàn màn
hình xoay ngang cùng player, giữ tập và tiến độ. Chỉ giữ tên phim, số tập,
phát/tạm dừng và **Phát tất cả**; không thêm tim, bình luận hay chia sẻ.

**Phát tất cả** lấy panel tập của đúng collection, kiểm tra đầy đủ, rồi mở
đúng tập đang xem. Player preview được dừng trước khi player danh sách nhận
quyền phát. URL video được lấy mới theo ID khi chọn tập, không lưu vào history.
Feed tải tiếp theo các video ID đã nhận, loại trùng và dừng khi không còn ID
mới; lỗi mạng có thao tác thử lại và không thay bằng catalog khác.

Banner Trang chủ kéo tới đỉnh sau nút đổi thư viện/nguồn đặt chồng lên ảnh.
Đã bỏ nút tải lại trên Home. Ảnh bìa, tên và khoảng trống trong thẻ/kết quả
cùng là vùng bấm của đúng phim; không để artwork nhận/chặn riêng sự kiện.

## Cài đặt phát và PiP

Đối chiếu IPA Phim4K gốc cho thấy sáu nhóm **Âm thanh / Phụ đề / Hiển thị /
Tốc độ / Chung / Thông tin**. Menu mới dùng hàng tab ngang gọn, vùng tùy chọn
cuộn, lựa chọn track lớn và rõ trạng thái đang chọn. Hiển thị gồm tỷ lệ video,
lấp đầy khung hình và kiểu phụ đề; các lựa chọn thật vẫn dùng track ID của
player. Menu này cũng có trong player Phim AI.

PiP dùng AVSampleBufferDisplayLayer và cùng decoder/âm thanh mpv. Chỉ khi cần
PiP mới chuyển sang khung render CPU nhỏ; phát thường giữ Metal và cấu hình
cache/hardware decoding cũ. Luồng render chạy riêng và được giải phóng trước
khi hủy mpv. Khi trả về app phải đưa output GPU trở lại trước khi giải phóng
render context PiP, để tránh mpv tự hủy video đang sử dụng context đó.

Có nút cửa sổ nổi và tùy chọn **PiP khi rời ứng dụng**. App khai báo chế độ âm
thanh nền. Kết quả renderer/seek/restore trên simulator phải được ghi riêng;
chưa xác nhận tự bật cửa sổ PiP trên iPhone vật lý. Không coi có nút hoặc build
thành công là PiP đã hoạt động.

Nguồn 2 hiển thị `S01E001` thành **Tập 1**, vẫn giữ nguyên ID mùa/tập và server
cho resolver. Tên đặc biệt không bị thay bằng số đoán theo tiêu đề.

## Kiểm chứng và giới hạn hiện tại

[Bằng chứng feed và phạm vi bảo vệ](Tools/evidence/2026-11-03-short-feed/README.md)
ghi hash IPA gốc, địa chỉ mã, hợp đồng feed và quan sát mạng đã loại URL ký.
Một mẫu feed live có panel **89 tập liên tục**, video response trùng chính xác
collection/video/số tập. Đây là quan sát API, không thay thế playback iOS.

Run [41558237765](https://github.com/thuyan1510/AnPinime/actions/runs/41558237765),
commit `93dd048`, có kết quả XCTest thực:

- Khám phá/phân trang/bốn bộ lọc/đổi ba thư viện: PASS, 104.679 giây.
- Player tập/lịch sử/cancel tập chậm/pause/background/dọn player: PASS, 53.876 giây.
- Vùng bấm các phần của kết quả tìm kiếm: PASS, 12.997 giây.
- Live catalog → panel đầy đủ → tập đầu/hai/cuối: PASS, 40.257 giây; giải mã
  HEVC 540×960, thời gian tiến lên, mỗi lần một player.
- Feed mới: FAIL ở nhận diện trạng thái trong XCTest. Identifier cấp màn hình
  đè lên ID từng nút; đã sửa và đang chạy lại cả luồng lướt/xoay/Phát tất cả.
- MKV/PiP mới: FAIL do video output initialization. Đã sửa thứ tự restore/free
  và thêm log native theo giai đoạn; đang kiểm tra lại. Release build PASS
  của run này không được dùng làm bằng chứng đã sửa PiP.

[Bản ghi từng kết quả](Tools/evidence/2026-11-03-short-feed/run-41558237765-partial.json).
Run/IPA cuối cùng sẽ được ghi sau khi các kiểm tra cần thiết đạt.

Các bộ có catalog tổng tập khác panel vẫn báo chưa đủ danh sách, không tự
coi panel thiếu là trọn bộ. Ví dụ trước đây collection `7696940578596328500`
báo 45 tập nhưng panel chỉ có 41. Phép thử live PASS của một bộ khác không
chứng minh mọi phim đều đầy đủ. [Lịch sử điều tra UI 2.6](Tools/evidence/2026-11-02-ai-library-v2/)
và [baseline player 2.5](Tools/evidence/2026-11-02-ai-baseline/README.md) được
lưu riêng, không dùng IPA cũ làm bản giao mới.

## Các sửa đổi Movie được giữ

Ba nhãn nguồn là **Anpinime Free / Anpinime Premium / Anpinime dự phòng**.
Raw cases, URL/ID lịch sử và routing của nguồn 1/3 được giữ nguyên. Parser,
resolver, catalog và relay được so sánh hash với baseline; player/menu/banner
chung thay đổi theo yêu cầu lần này.

Tìm kiếm bắt đúng đối tượng trên hàng đang hiển thị, bỏ kết quả cũ khi query/
nguồn đổi, hủy phản hồi trễ và mở đúng phim khi bấm ảnh, chữ hoặc vùng trống.

Nguồn 2 tiếp tục dùng cache ngắn cho directory đã xác thực và probe GET giới
hạn thay cho HEAD rồi GET. Không cache media URL có thời hạn hoặc tráo server.
Phân tích mẫu **Người Nhện: Khởi đầu mới**, Core ID `17997`, cho thấy các link
MKV đã đo có đoạn mở đầu đen; điều này có thể làm người xem tưởng chưa có hình.
Chưa kết luận đã sửa hết lag/tốc độ trên iPhone. Phép đo Core mới trước đây gặp
403 ở bước detail; số đo Linux hoặc gateway dùng metadata lưu không đại diện
cho startup fresh Core trên máy người dùng.

[Phân tích và giới hạn startup nguồn 2](Tools/source2-startup-analysis.md),
[kết quả iOS nguồn 2](Tools/evidence/2026-11-02-source2-startup/ios-startup-results.json).
Free1 live, anime live và VIP phải đọc theo kết quả playback riêng của từng
lượt, không lấy trạng thái build xanh để kết luận tất cả đã sửa.
