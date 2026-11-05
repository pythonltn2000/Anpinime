# AnPinime 2.9.3 (22): phục hồi trạng thái PiP

**[Tải IPA 2.9.3 (22)](https://github.com/pythonltn2000/Anpinime/actions/runs/42009981972/artifacts/13406846480)**,
source `2cb9096`. Gói unsigned đã được tải về và kiểm tra độc lập đúng phiên
bản, source commit, cây ứng dụng, mpv, background audio và checksum. Artifact
giữ đến 08/11/2026 10:24 UTC. Đây là xác nhận biên dịch/đóng gói.

Tiếp nối bản 2.9.2 (21) tại kho `pythonltn2000/Anpinime`. Bản này sửa các
đường lỗi có thể xác nhận trong mã; không coi build IPA là xác nhận PiP tự
động trên iPhone. Cải tiến Home anime và chặn lệnh PiP inline làm dừng phim
ngắn của bản 21 được giữ lại. Báo cáo trước: [Home/phim ngắn/PiP](HOME_SHORTS_PIP_REPAIR.md).

## Sửa native PiP

- Trước đây chỉ thử lấy frame giải mã ba lần trong cả phiên. Nếu video chưa
  sẵn sàng ở cả ba lần, PiP không được chuẩn bị cho đến khi mở lại player.
  Giờ thử theo đợt tối đa ba lần, nghỉ hai giây rồi cho phép phục hồi trong
  cùng phiên. Request bị mất phản hồi được kết thúc sau hai giây; mỗi lần
  dùng ID mới để phản hồi cũ không nhận nhầm request mới.
- Chỉ khởi tạo output software khi đã có kích thước video thật. Không tạo
  renderer từ kích thước giả 1×1 khi người dùng bấm PiP quá sớm.
- Trạng thái sẵn sàng yêu cầu frame thật, output đã chuẩn bị, nguồn còn gắn
  vào cửa sổ và video đang phát. Không đánh dấu sẵn sàng chỉ vì đã tạo object.
- Không hủy phiên PiP đã chuẩn bị khi chỉ mở Control Center hoặc có gián đoạn
  inactive ngắn. Khi thật sự trở về từ background, vẫn dừng theo handshake
  AVKit trước khi trả GPU và giải phóng output.
- Không tiếp tục nạp lặp lại cùng một frame bootstrap sau khi layer đã nhận
  nó. Giữ GPU inline; chỉ chuyển software output khi thật sự yêu cầu PiP.
- Play/Pause/Seek từ controller chưa active tiếp tục bị bỏ qua, bảo vệ ý định
  tạm dừng của người dùng và tránh ghi nhầm pause vào phiên phim ngắn.

Giữ nguyên layer native dưới Metal trong player, không di chuyển sang một
host view khác dựa trên giả thuyết. Việc iOS có chấp nhận tự động chuyển từ
hierarchy này vẫn chưa được xác nhận trên thiết bị thật.

## Sửa cầu nối WebKit

Swift và JavaScript dùng cùng session ID theo video/tài liệu và request ID
theo lần yêu cầu. Swift ghi pending trước khi gửi lệnh, chờ thông báo active,
stopped hoặc lỗi; callback trễ từ phiên cũ không thay đổi phiên mới. Lỗi JS,
Promise bị từ chối hoặc request không hoàn tất đều giải phóng pending để có
thể thử lại. Khi video được tạo muộn hoặc thay element cùng URL, danh tính
phiên vẫn được cập nhật.

Lệnh broadcast vào iframe khác phiên bị bỏ qua. Iframe không được gửi lỗi
mang ID của video khác rồi vô tình kết thúc request PiP đang mở đúng.

Thông báo stopped kết thúc đúng phiên đang active. Một snapshot inline đến
trễ không được phép tự xóa pending/active. Nếu WebKit tự mở PiP qua nút của nó
hoặc hệ thống, app nhận luôn request ID của phiên đó, kể cả ID rỗng, để nhận
được thông báo đóng tương ứng. Không chuyển sang native player hoặc nạp lại
trang khi WebKit còn đang sở hữu một lần chuyển PiP.

Chỉ yêu cầu tự động khi app thật sự vào background và lựa chọn PiP được bật;
không ép PiP ở willResignActive. Public API của WKWebView không có cờ tự động
inline tương đương AVKit. Video sealed/blob cần decoder website vẫn có giới
hạn đã nêu trong [căn cứ Apple/WebKit](HOME_SHORTS_PIP_REPAIR.md#căn-cứ-ios-và-giới-hạn-webkit).

## Kiểm chứng và ngân sách

Kết quả kiểm tra local và hash chính xác nằm trong
[local-checks.json](Tools/evidence/2026-11-05-pip-recovery/local-checks.json).
Các bài kiểm tra dùng chính policy native và JavaScript production được trích
từ PlayerView, gồm nhận diện request, timeout, lỗi và phản hồi cũ. Home anime
vẫn được kiểm tra bằng fixture; timing fixture không phải tốc độ website live.
Parse Swift trên Linux không thay thế typecheck Apple SDK.

Đạt 26 kiểm tra Home, 26 kiểm tra policy PiP (80 tổ hợp điều kiện), tám nhóm
JavaScript, các fixture provider AI và 18 kiểm tra cache. Server fixture xác
nhận tải đủ mười video và dùng lại video trước; đây là kiểm tra file/cache,
không phải bằng chứng mười video đã render hoặc lướt phát thành công trên iOS.

Nguồn Movie 1/3, provider nguồn 2, relay và parser không đổi ở bản sửa này.
Không có chứng cứ mới rằng anime live, Free1 live hoặc PiP tự động trên iPhone
đã phát thành công. Những lần SKIP/FAIL runtime trước vẫn giữ nguyên giá trị.
Kiểm tra video chạy liên tục và lướt ngược/tiếp trên iOS chưa được chạy lại.

Theo [chính sách build](Tools/build-cost-policy.md), chỉ gửi một lượt **Build
IPA only** sau kiểm tra local; không Simulator, live test hay full suite trên
Actions.

Kết quả: một job macOS **198 giây (3 phút 18 giây)**, thành công; helper Linux
gửi đúng một lệnh dispatch mất **5 giây**. Không retry, không nhập lại lịch sử,
không job Simulator/live/full suite. Helper chỉ nằm trên nhánh riêng; hai
workflow ở main vẫn chạy thủ công. Thời gian trên là thời gian thực thi job,
không phải hóa đơn GitHub. Bằng chứng:
[release-and-budget.json](Tools/evidence/2026-11-05-pip-recovery/release-and-budget.json)
và [ipa-identity.json](Tools/evidence/2026-11-05-pip-recovery/ipa-identity.json).

## Kiểm tra trên iPhone còn thiếu

Với PiP tự động trong iOS và app đã bật: phát ít nhất vài giây, về Home một
lần, dùng Play/Pause ở PiP, trở lại app, lặp lại; mở/đóng Control Center rồi
thử lại. Làm riêng cho phim AI, nguồn 2 và anime/WebKit. Ghi rõ manual PiP và
automatic PiP; manual thành công không tính là automatic thành công. Phim
ngắn cần phát qua giây 6 sau mỗi lần lướt tiếp → tiếp → ngược và giữ một audio
owner. Đây là kiểm chứng còn thiếu, không phải kết quả đã đạt.
