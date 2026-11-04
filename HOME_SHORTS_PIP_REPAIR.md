# AnPinime 2.9.2 (21): Home anime, phim ngắn và PiP tự động

Tiếp nối `a2d7fb4` / bản 2.9.1 (20). Phạm vi gồm thời gian hiện danh sách
Home anime, lỗi phim ngắn dừng gần giây đầu và chuẩn bị PiP trước khi về Home.
Kết quả build và kết quả phát video được ghi riêng; chưa coi một build xanh
là bằng chứng PiP tự động trên iPhone đã hoạt động.

## Thay đổi

Home trước đây chờ shortlink (timeout 8 giây), rồi chờ toàn bộ các probe trang
chi tiết ở những tên miền cũ (timeout 5 giây), mới gửi request danh sách.
Đường mới tải Home từ cấu hình hoặc tên miền đã biết và xác nhận chính phản hồi
Home. Lỗi tên miền vẫn dùng cơ chế discovery/rebase cũ; challenge vẫn đi qua
xác minh WebKit. Không chấp nhận một redirect sang website ngoài nguồn đã chọn.
Parser Home chạy ngoài main actor. Cache đĩa chỉ giữ thẻ danh sách đã parse,
tối đa 24 giờ, tách đúng cấu hình tự động/thủ công; ảnh, HTML, cookie và luồng
video không được tải trước hàng loạt. Mở lại app hiện thẻ cũ ngay trong lúc
request mới còn đang chờ, rồi thay bằng kết quả mới.

Browser xác minh được khởi tạo lazy và giữ một instance trên main actor. Mở
Movie/AI không còn khởi tạo WKWebView của anime khi chưa có nhu cầu. Đây là
giảm tài nguyên khởi động thực; chưa coi nó là bằng chứng nguyên nhân duy nhất
của việc tải AI live chậm.

Phim ngắn có một đường gây dừng gần giây đầu: callback PiP khi controller mới
được chuẩn bị ghi vào `userPaused`, rồi session lưu thành `manuallyPaused`.
Lệnh Play/Pause/Seek từ PiP giờ chỉ hợp lệ khi đúng controller và cửa sổ đang
active. Đây là lỗi có thể chứng minh trong mã và kiểm thử handler; chưa có trace
iPhone để khẳng định mọi trường hợp dừng một giây đều xuất phát từ nguyên nhân này.

Native PiP chuẩn bị render context software ngay khi có frame giải mã ở
foreground, thay vì cấp phát lần đầu sau khi app vào nền. Việc chuẩn bị không
đổi `gpu-next`, không tạm dừng và không đánh dấu pending. Chỉ lúc chuyển PiP
thực sự mới dùng output software. Giữ nguyên thứ tự dừng AVKit, trả GPU, giải
phóng render context rồi hủy decoder. Cờ sẵn sàng tự động được cập nhật trước
thông báo vòng đời. Time range cung cấp cho AVKit luôn chứa thời gian đang phát.

## Căn cứ iOS và giới hạn WebKit

- [Apple WWDC21: What's new in AVKit](https://developer.apple.com/videos/play/wwdc2021/10290/)
  hướng dẫn bật `canStartPictureInPictureAutomaticallyFromInline` cho nội dung
  chính đang phát, cấu hình audio playback/background mode, và cung cấp state
  thực qua sample-buffer playback delegate. Chuẩn bị controller/frame sau khi
  app đã vào background làm mất thời gian để AVKit nhận phiên phát.
- [Thuộc tính tự động của AVPictureInPictureController](https://developer.apple.com/documentation/avkit/avpictureinpicturecontroller/canstartpictureinpictureautomaticallyfrominline)
  là cơ chế cho player native phát inline. App giữ một decoder/audio owner và
  để AVKit quản lý việc chuyển sang cửa sổ PiP.
- Callback `setPlaying` của sample-buffer delegate được Apple mô tả là thao
  tác từ nút Play/Pause của cửa sổ PiP. Callback lúc mới tạo controller inline
  không được phép ghi đè ý định tạm dừng của người đang xem phim ngắn.
- [WKWebViewConfiguration.allowsPictureInPictureMediaPlayback](https://developer.apple.com/documentation/webkit/wkwebviewconfiguration/allowspictureinpicturemediaplayback)
  chỉ cho phép HTML video dùng PiP; không cung cấp thuộc tính tự động inline
  của AVKit. `video.autoPictureInPicture` không nằm trong
  [interface WebKit](https://github.com/WebKit/WebKit/blob/5c8847859a197aed020d22f6faa7598c29e44733/Source/WebCore/html/HTMLVideoElement.idl).
  Việc gán trước đây chỉ tạo một thuộc tính JavaScript, không bật tính năng iOS.
- [WebKit: điều kiện tự chuyển PiP](https://github.com/WebKit/WebKit/blob/5c8847859a197aed020d22f6faa7598c29e44733/Source/WebCore/platform/ios/VideoPresentationInterfaceAVKitLegacy.mm#L871)
  yêu cầu đang phát, standby hoặc fullscreen thực và có hỗ trợ PiP. Video inline
  được app phủ CSS không tự thành fullscreen của WebKit. Đây là giới hạn của
  những luồng sealed/blob phải giữ bộ giải mã website; lời gọi JS sau background
  vẫn chỉ là best effort. Không dùng API riêng hay tự ép mở fullscreen.

Manual PiP của WebKit được giữ nguyên. Lệnh tự động riêng kiểm tra đúng lựa
chọn trong app, kể cả khi video được website tạo muộn. Thay đổi này không chứng
minh PiP tự động đáng tin cậy cho mọi luồng WebKit. Cài đặt tự động PiP của iOS
cũng do người dùng quản lý, theo
[hướng dẫn player của Apple](https://developer.apple.com/documentation/avkit/adopting-picture-in-picture-in-a-standard-player).

## Kiểm chứng

- Local: 26 kiểm tra Home đạt, gồm một request catalog ở cold start, thẻ cache
  hiện trước phản hồi refresh đang bị giữ lại, đổi host lỗi DNS, cache hết hạn,
  URL thủ công, challenge và redirect sai nguồn. Mẫu local cold 6 ms / warm
  1 ms chỉ là timing fixture; không phải số đo tốc độ website live trên iPhone.
  Kiểm tra thêm xác nhận không tạo browser khi chỉ tải Home và giữ cùng browser
  khi cần xác minh thật.
- Bảy nhóm JavaScript player đạt; Swift parse, shell syntax và diff check đạt.
- Thêm XCTest bắt buộc cho phim ngắn: phát qua ít nhất 5,5 giây / tiến hơn 4,5
  giây sau mỗi lần lướt đầu → tiếp → tiếp → ngược; giữ prefetch, đúng một player,
  GPU inline và không PiP pending/active. Gọi cùng chính sách xử lý lệnh PiP
  inactive; nếu bỏ điều kiện active thì bài kiểm tra sẽ ghi nhầm pause/play.
  Trên Simulator không hỗ trợ AVKit, inject state vào handler production,
  không tạo cửa sổ PiP giả.
- CI iOS và bằng chứng artifact sẽ được bổ sung sau khi chạy. Native XCTest
  Home hai lần vẫn đòi callback `didStart`/`didStop` thực; Simulator không hỗ trợ
  được ghi SKIP, không chuyển thành PASS.

Không có khẳng định phát live anime hoặc PiP máy thật từ các kiểm tra local này.

## Lần CI đầu: chưa đạt đầy đủ

[Run 41866403728](https://github.com/letunam2k/anpinime/actions/runs/41866403728),
source `7be77069`, đạt toàn bộ job native: Home 21 kiểm tra, MKV/audio/phụ đề,
8 frame PiP software, HLS relay, tập anime động và phục hồi cùng WebKit. Anime
live vẫn bị xác minh; Free1 vẫn có segment 404. Không tính các bước optional
màu xanh là phát live thành công.

Job AI có 4 fixture PASS, 1 SKIP, 2 FAIL; live 1 PASS/1 FAIL, nên cổng phát hành
IPA đã chặn đúng. Phim ngắn ở lỗi nút kiểm thử vẫn phát ở giây 7, một owner và
`gpu-next`; nút DEBUG bị che khi chuyển sang phim kế. Bài prefetch dùng nhầm
bộ đếm của bài trước. Đã sửa vùng bấm DEBUG và tách toàn bộ thống kê theo từng
testcase, thêm mẫu thời gian trước/sau từng phim và dọn trạng thái pause.

AI live tập đầu có state resolving ở deadline rồi giải mã HEVC 540×960 ở giây
3,167 lúc teardown. Đây vẫn là FAIL; không nới giới hạn 25 giây, không đổi phim
và không gọi đó là kiểm tra trọn bộ đạt. Cùng với browser lazy, truy vấn telemetry
dùng đúng Button theo ID để giảm công việc AX thừa. Cần kết quả lần CI tiếp.

Bằng chứng được lược bỏ URL/cookie/token trong
[Tools/evidence/2026-11-04-home-shorts-pip](Tools/evidence/2026-11-04-home-shorts-pip/).
