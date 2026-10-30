# Tiếp tục điều tra sau 8acf5c0 — 30/10/2026

Đã đọc `REPAIR_REPORT_V3.md` và `Tools/source2-analysis.md` trước khi sửa.
Baseline: `8acf5c0c9c316a16ac0e406ead1f4dcde1a3c2da`.
Nhánh điều tra: `repair/source2-live-playback`. Chưa xác nhận hoàn tất Free1,
anime hoặc VIP chỉ dựa trên build thành công.

## Hai lỗi đã tái hiện

1. `FilmMediaRelay` đổi mọi segment thành `.bin`. FFmpeg HLS có kiểm tra đuôi
   segment: cùng HLS cục bộ, URL `.bin` bị từ chối với
   `is not in allowed_segment_extensions`, còn `.ts` giải mã được. Nguồn 2 giờ
   giữ các đuôi media đã biết trong URL loopback có ID ngẫu nhiên; URL endpoint
   `/api/content/stream/hls` vẫn thành `.m3u8`. Không tắt kiểm tra đuôi của FFmpeg.
   Cần phân biệt lỗi này với lỗi upstream và kết quả libmpv simulator bên dưới.
2. Live `.news` trả HTTP 403 với tiêu đề `Đang Kiểm Tra - AnimeVietsub`, không có
   `challenge-form`/Turnstile trong HTML ban đầu. `containsVerification` cũ trả
   false cho trang này, khiến `WebsiteSession` có thể trả HTML challenge như
   nội dung thành công và cache nó. Đã nhận diện tiêu đề hiện tại; fixture giữ
   cấu trúc tối thiểu, không chứa mã challenge, IP, cookie hay token.
   Luồng WebKit/xác minh được giữ nguyên; thay đổi này không chứng minh anime phát.

## Live từ môi trường Linux

Các phép thử giới hạn vào mẫu đã ghi trong báo cáo cũ, không quét catalog.
`Tests/source2_live_probe.py` ghi HTTP status, host, MIME, số byte prefix và loại
chữ ký; không ghi URL/query, API header, nội dung video hoặc thông tin phiên.

- Free1 Thương Nguyên Đồ: detail 200; manifest gốc tại `sf.phim4k.space` 200,
  28.277 byte. Hai segment đầu trên `s6.kkphimplayer6.com` trả 404 HTML, không
  phải TS. Kiểm tra segment đầu bằng Range/không Range và Safari/exoplayer đều
  gặp 404. Không đổi User-Agent chung hoặc thay bằng embed của nhà cung cấp khác.
- Mẫu đối chiếu Xóm Nhỏ: detail và manifest đều 200; prefix segment đầu tại
  `a.kvp726.com` cũng trả 404. Mẫu này chỉ dùng để điều tra mạng, không thay
  mẫu Free1 trong smoke test hoặc đường phát thật.
- Core Wakanda `10403` hôm nay trả 200 và giữ đủ `31937`, `33090`, `27463`,
  `31938`, `31939`. Kết nối tới URL gốc của `31937` tại `cdn.phim4k.lol` bị tunnel
  trong môi trường từ chối. Đây không phải bằng chứng HTTP 403 từ máy chủ media
  hay kết luận API key/tài khoản sai.
- Anime detail `.news` gặp challenge. Chromium thường cũng chỉ tới 403 /
  `Just a moment...`. Không thu được DOM chi tiết/tập/video để xác nhận live.

## Kiểm thử simulator và bằng chứng

CI được chạy cho chính nhánh điều tra. Bổ sung fixture đi qua provider nguồn 2
→ endpoint HLS không đuôi → relay thực → libmpv. Đây là phép thử bắt buộc, độc lập
với MKV. Free1 live và Core VIP có kết quả riêng; lỗi live không bị đổi thành
phim/server khác.

Điều kiện thành công mới: backend mpv, có kích thước video giải mã > 0, đang phát,
thời gian tăng ít nhất một giây giữa các quan sát và giao diện ngang. Script
kiểm tra nội dung JSON, xóa kết quả cũ trước mỗi lần chạy và lưu ảnh/chẩn đoán
khi thất bại. Chẩn đoán chỉ bật trong DEBUG/smoke, loại URL và header nhạy cảm.

Đã tải và kiểm tra trực tiếp JSON/ảnh artifact của run
[`41001476273`](https://github.com/thuyan1510/AnPinime/actions/runs/41001476273),
code commit `410aafb042bba997c552cda102de02bf50c2d28d`.
Artifact playback `12953593501`, SHA-256:
`5db6a58c4da1984c760341f4da3176d02782005a8e2265fd24fc3c3683bb6376`.
Bản sao JSON đã loại URL nằm trong `Tools/evidence/2026-10-30/`.

| Phép kiểm tra | Kết quả thực tế |
| --- | --- |
| Parser/catalog/provider, JS player, Range | PASS, gồm hồi quy routing nguồn 1/3 và trang challenge mới |
| MKV hai audio/hai phụ đề | PASS; mpv 2,542 giây; autoplay và chuyển track xác nhận |
| HLS cục bộ qua provider/relay/mpv thật | PASS; 640×360; 3,44 giây; ảnh có khung hình test pattern |
| Free1 live Thương Nguyên Đồ | FAIL; segment trả 404 HTML; loaded=false, time=0, videoWidth/Height=0 |
| Core Wakanda server 31937 | FAIL ở resolve; iOS báo không tìm thấy hostname CDN |
| Anime live | Chưa xác nhận phát; các kết nối thử nghiệm gặp challenge |

Trên macOS runner, probe độc lập cũng nhận detail/manifest 200 và hai segment
đầu 404. Chẩn đoán của player thật cho thấy mpv đã vượt qua bước mở manifest và
liên tục thử các segment `.ts`, đều nhận 404; sau 40 giây vẫn không có video.
Đây là bằng chứng phân biệt lỗi upstream hiện tại với khả năng giải mã HLS cục bộ.
Không có `playback-phim4k-live.json` hoặc `playback-phim4k-vip.json` thành công.

Hai bước live thoát mã 1. Workflow vẫn xanh vì `continue-on-error` cho các nguồn
mạng không ổn định; không được dùng màu xanh đó hay artifact IPA làm chứng cứ
đã sửa live. Script ghi FAIL rõ vào step summary và lưu ảnh/chẩn đoán khi lỗi.

Run đầu `41000905078` đã qua parser/provider, build và MKV nhưng fixture HLS
bị 403 vì yêu cầu sai cổng Origin; fixture đã sửa và run cuối ở trên kiểm chứng
lại thành công. Hai run trung gian được hủy khi có thay đổi kế tiếp để tránh
chạy trùng. Không lấy chúng làm bằng chứng phát live.

## Bảo vệ nguồn 1/3

`MovieCatalog`, `MovieProvider`, `MovieBrowseCatalog`, `FilmMediaTransform`,
`Models`, `Phim4KCatalog`, `Phim4KProvider`, `Phim4KVIPResolver` trùng byte với
baseline. Không đổi domain, API, parser catalog, định danh hay resolver của
NguonC/KKPhim. Các hồi quy routing của chúng vẫn chạy trong suite chung.

Hai file player/relay dùng chung có thay đổi được giới hạn: cờ giữ đuôi chỉ
bật khi `episode.source == .phim4k`, giá trị mặc định false giữ hành vi nguồn
1/3; phần ghi chẩn đoán mới chỉ có trong DEBUG với cờ smoke nguồn 2. Player,
codec, autoplay, lựa chọn audio/subtitle và xử lý byte media của nguồn 1/3
không được thay đổi.

## Phần chưa thể kết luận

Không nối `Phim4KVIPResolver` đang có sẵn vào runtime, không tạo token/chữ ký
phỏng đoán, không đổi hostname CDN và không dùng Free làm VIP. Danh sách Core
không chứng minh URL media dùng được. Anime cần DOM/live sau xác minh trên kết
nối hợp lệ; VIP cần resolver/URL/phiên hợp lệ từ nguồn gốc. HLS cục bộ đã có bằng chứng phát; Free1 live, anime và VIP vẫn chưa đạt.
Bước tiếp theo cần URL media/segment hoạt động từ nguồn gốc, hoặc DOM anime
sau xác minh trên kết nối hợp lệ; không giải quyết bằng thay phim, host hay token.
