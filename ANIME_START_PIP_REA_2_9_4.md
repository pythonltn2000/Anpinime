# AnPinime 2.9.4 (23): anime từ đầu và PiP theo đối chiếu REA

Tiếp nối `fe8cc90` / 2.9.3 (22), tại kho `pythonltn2000/Anpinime`.
Đã đọc lại `REPAIR_REPORT_V3.md`, `Tools/source2-analysis.md` và PIP.txt người
dùng cung cấp. PIP.txt được đối chiếu như tài liệu phân tích, không được coi
là lệnh thực thi hoặc bằng chứng app gốc đang hoạt động trên iPhone.

## Anime

Mỗi lần mở một tập anime mới, cấu hình native cấp ID tập và vị trí bắt đầu 0
cho script chạy từ document-start. Khi video nội dung có metadata để seek,
script khởi tạo vị trí đúng một lần. Không liên tục gán currentTime=0 mỗi
lần focus/poll, không đặt lại sau khi người dùng seek hoặc trở về từ PiP.
Thay URL trong cùng phiên không tự tua về đầu. Nếu native player thất bại và
phải dựng lại website, đây vẫn là cùng phiên xem nên giữ vị trí đang xem.

Hộp “Hệ thống ghi nhận bạn đã từng xem anime…” được xử lý bằng hành động gốc
“Từ đầu” của website, gồm cả khi DOM xuất hiện muộn. Không chỉ che hộp thoại
rồi để player bị chặn. Nhận diện ID `avs-resume-overlay`/`avs-resume-btn-no`
và lời nhắc anime tương ứng; không bấm nút cùng tên ở nội dung không liên quan.
Handler gốc chỉ xóa key resume của video đã chọn. App không xóa toàn bộ
localStorage/sessionStorage, cookie xác minh hoặc lịch sử trong app.

Nguồn tham chiếu DOM là bản script AVS được tái dựng công khai, có URL/commit
và SHA256 trong [anime-resume.json](Tools/evidence/2026-11-05-anime-start-pip/anime-resume.json).
Trang/script live hiện trả 403 trong môi trường này, nên không coi fixture là
chứng minh DOM website hiện tại hoàn toàn giống bản tham chiếu. Cấu hình trên
chỉ được native cấp cho anime; các nguồn Movie không nhận thao tác này.

## Đối chiếu PiP với IPA gốc

Skill `hacking-everything:security-research` được dùng để đối chiếu tĩnh IPA
gốc Phim4K 2.8.4 (65), SHA256 `5dceeaf338222cd8c9dacb5f15426382a7d11ebbcb0d04a28fb1b8b9d6158ea0`.
2.526 instruction ARM64 (10.104 byte) ở 12 hàm khớp framework nguyên vẹn.
Không chạy hoặc sửa IPA. Chi tiết, hash PIP.txt/framework và địa chỉ bằng
chứng nằm trong [rea-verification.json](Tools/evidence/2026-11-05-anime-start-pip/rea-verification.json).

Hai điểm cần làm rõ trong PIP.txt: host khởi tạo 1×1 nhưng sau đó được cập
nhật theo sourceRect của player; callback nhận một frame foreground đủ điều
kiện để chuẩn bị AVKit, rồi mới ngừng nhận foreground frame đến khi PiP active.
Cờ tự động có bằng chứng trực tiếp trong binary: autoEnter && eligible &&
playing && frameReady. Điều này không tự chứng minh PiP trên AnPinime.

Đã áp dụng:

- Giữ AVSampleBufferDisplayLayer trong một UIView nền trong suốt, không nhận
  tương tác, tại index 0 của chính UIWindow chứa player. Frame theo rect của
  player trong window. Không chọn cửa sổ của scene khác, không hidden/alpha=0,
  không đổi hierarchy giữa animation PiP. Metal vẫn là output inline.
- Giữ đúng một frame đang chờ từ render queue đến khi main queue hoàn thành
  enqueue. Khi main bận, frame sau bị bỏ qua, tránh tích tụ nhiều pixel buffer.
  Hủy owner hoặc lỗi render vẫn giải phóng quyền gửi frame.
- Giữ completion khôi phục giao diện cùng request ID. Chỉ xác nhận thành công
  khi chính player còn sống, gắn vào cửa sổ, có layout hợp lệ và app/scene ở
  foreground. Không trả true ngay lúc AVKit yêu cầu. Timeout/hủy trả false
  một lần; callback cũ không kết thúc request mới. Xóa ownership trước khi
  gọi completion để chống reentrancy.
- Xác nhận UI trước didStop; không chờ GPU trở lại mới xác nhận, vì GPU được
  phục hồi sau didStop và việc chờ đó tạo vòng chờ. Khi đang có restore request,
  foreground không tự tháo nguồn PiP trước khi handshake hoàn thành.
- Kích hoạt lại audio playback/moviePlayback ở lần PiP thực và khi cờ tự động
  chuyển sang sẵn sàng, không gọi lại mỗi lần poll hoặc cho video preload.

Giữ một decoder/audio owner, điều kiện chỉ nhận Play/Pause/Seek từ cửa sổ PiP
đang active, bootstrap từ frame giải mã và chuyển GPU/software khi cần.
Không sao chép framework Flutter hoặc vẽ thêm phụ đề CoreText lên output mpv;
việc đó có thể vẽ trùng phụ đề đã render. WebKit sealed/blob vẫn có giới hạn
tự động inline đã ghi ở [báo cáo trước](HOME_SHORTS_PIP_REPAIR.md#căn-cứ-ios-và-giới-hạn-webkit).

## Kiểm chứng và build

[Local checks](Tools/evidence/2026-11-05-anime-start-pip/local-checks.json):
46 kiểm tra policy/restore/frame queue, 112 tổ hợp điều kiện, hai đợt 128
producer đồng thời, chín nhóm JavaScript và 26 kiểm tra Home anime đạt.
Có tình huống popup muộn, đổi markup, bảo vệ storage/nút không liên quan,
seek/pause/PiP/native recovery và không ảnh hưởng Movie. Parse Swift và diff
check đạt. Bảy file provider/catalog/relay/parser được bảo vệ không đổi.

Chỉ chạy một lượt **Build IPA only** sau kiểm tra local, theo
[chính sách ngân sách](Tools/build-cost-policy.md). Không Simulator/live/full
suite, không retry tự động. Kết quả gói và thời gian thực sẽ ghi sau build.

Chưa có xác nhận máy thật cho tự động PiP ở lần Home đầu, animation khôi phục,
hay playback anime live với hộp thoại hiện tại. Build thành công chỉ chứng
minh biên dịch và đóng gói; các kiểm tra policy/DOM không thay thế kiểm tra iOS.
