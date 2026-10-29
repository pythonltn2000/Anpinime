# Anime `.news` và Phim4K Free — 29/10/2026

Baseline: `35366ae2a1dfad5467e11d416e27080135905043`, working tree sạch. Build baseline run `40685743066` thành công (kể cả simulator); nó không chứng minh các nguồn live đều hoạt động.

## Những lỗi có thể xác nhận trong mã

- `DomainResolver` giữ host đã xác minh trong UserDefaults không có ngày hết hạn. Khi website chuyển tên miền, app có thể dùng lại host cũ qua nhiều lần mở. Bổ sung TTL sáu giờ, ưu tiên shortlink và thêm `animevietsub.news` (website người dùng xác nhận) vào ứng viên dự phòng. Không đổi sang website Next.js `.dev` đã dùng làm mẫu parser trước đây.
- Cài đặt chỉ có ô URL của nguồn phim 2, chưa có cấu hình anime riêng. Thêm `AnPinime.animeURL`, nối vào resolver dùng chung cho home/search/detail/tập/lịch; khi lưu phải bỏ cache anime cũ. URL anime từng lưu nhầm vào key nguồn 2 được chuyển sang key anime nếu chưa có lựa chọn anime. URL kho Free thật giữ nguyên. URL anime bị chặn ở phần nhập Free để tránh trộn nguồn.
- `watchURL` bị giới hạn vào `xem-phim`/tập 1, dù nút Xem phim có thể dẫn tới một tập thực khác. Giờ dùng link đã được trang cấp, vẫn kiểm tra đúng bộ anime và loại bình luận/login. Alias canonical đổi slug chỉ được nhận khi giữ cùng ID anime `aNNN`.
- Payload tập Next.js trước yêu cầu key liền nhau và đúng thứ tự. Giờ decode JSON của đối tượng bằng parser, không phụ thuộc khoảng trắng/thứ tự key. Captcha ở phần bình luận không biến một trang thông tin phim đầy đủ thành trang chặn toàn bộ.
- Khi thay URL thủ công nguồn 2, cấu hình cũ đặt Core=nil và chỉ giữ một Free catalog. Sửa để chỉ thay đúng Free1/Free2, vẫn giữ Core và kho Free còn lại; xóa URL thủ công khôi phục cấu hình app gốc. Bootstrap trả thiếu không còn xóa các host đã biết.

## Đối chiếu Phim4K và kiểm tra live

Đã dùng skill `reverse-engineer-anything` để kiểm kê IPA gốc. SHA-256 giữ nguyên `5dceeaf338222cd8c9dacb5f15426382a7d11ebbcb0d04a28fb1b8b9d6158ea0`; REA Evidence `ev_bbe18dcb4952bd6b65047d4096c62c51bd40ce67abd55696ff5b8bd0f4825aa3`. Đây là kiểm kê/phân tích tĩnh, không phải ghi nhận app gốc đang chạy.

- Free1 tại `free.cryboiz.workers.dev` trả danh sách, phim Thương Nguyên Đồ có 100 tập và Xóm Nhỏ có 6 tập. Row `link` dẫn tới endpoint HLS của app `sf.phim4k.space/api/content/stream/hls`; không thay bằng embed KKPhim.
- Mẫu Thương Nguyên Đồ trả HLS 28.277 byte, 336 segment; prefix segment đầu HTTP 200, MIME `video/mp2t`, sync byte `0x47`. `oxoo`, `exoplayer` và Safari đều đọc được prefix manifest trong phép thử giới hạn. Không có lý do đổi User-Agent chung.
- Core hiện trả 403 HTML/Cloudflare từ môi trường này, Free2 lỗi DNS. Chưa xác minh phát VIP thật; không kết luận API key sai chỉ từ 403 HTML.
- Chuỗi `/link_play` trong IPA thuộc luồng live-TV, không phải bằng chứng resolver phim VIP. Không tự ghép endpoint, tạo chữ ký hoặc thay VIP bằng Free.

## Anime live và giới hạn

Người dùng xác nhận website tự cập nhật là `.news`; tra cứu công khai cũng có dữ liệu home, lịch và các phim trên `animevietsub.news`. Truy cập trực tiếp và Chromium thông thường trong môi trường này gặp 403/challenge; không thể lấy DOM đầy đủ từ kết nối đó. Vì vậy chưa xác nhận đã sửa dứt điểm việc mở tập trên iPhone. Bộ kiểm thử mới kiểm tra các đường đi có lỗi xác định trong mã; nó không thay cho việc đối chiếu từng tập của website live.

Không đổi ID lịch sử hoặc player. Cần xác nhận trên iPhone rằng home, chi tiết và tập đều dùng cùng host `.news`, sau khi làm mới kết nối/xác minh.

## Kiểm thử và phạm vi bảo vệ

- Local Swift parser/catalog/config: 125 PASS, gồm cấu hình nguồn độc lập, migration, canonical đúng/sai ID, link Xem phim tới tập mới nhất, JSON tập đổi thứ tự và captcha bình luận.
- JavaScript player: năm nhóm PASS. Kiểm tra cú pháp Swift và `git diff --check` đạt.
- Provider suite bổ sung cấu hình Free và endpoint HLS thực tế. CI macOS chạy toàn bộ suite và MKV hai audio/hai phụ đề.
- Thêm bước live Free1 trên simulator: tìm chính xác Thương Nguyên Đồ trong kho Free1, phát bằng mpv, lưu `playback-phim4k-live.json` và ảnh. Bước này phụ thuộc mạng và không chặn IPA; chỉ có JSON/ảnh xác nhận mới tính là đã phát live. Không đại diện cho VIP.
- Checksum `MovieCatalog`, `MovieProvider`, `FilmMediaRelay`, `FilmMediaTransform`, `PlayerView`, `MPVPlaybackController`, `Models` trùng baseline. Các nguồn 1/3 không đổi domain, API, parser catalog hoặc resolver; hồi quy routing của chúng chạy trong CI.
- App bản `2.4.2` build `11`. Kết quả build mới được xác nhận bằng workflow của commit chứa thay đổi này, không dựa vào build baseline.

## File chính

`AnimeSiteConfiguration.swift`, `DomainResolver.swift`, `AnimeService.swift`, `HTMLParser.swift`, `RootView.swift`, `VerificationView.swift`, `MovieSourceDirectory.swift`, `Phim4KProvider.swift`, `PlaybackSmokeTest.swift`, `Info.plist`; Tests/main, ProviderTests, phim4k-live-smoke; workflow và Tools/source2-analysis.

## Kiểm tra trên iPhone

1. Trong Anime → Cài đặt, làm mới kết nối; kiểm tra máy chủ là `.news`. Có thể chọn website anime thủ công bằng địa chỉ gốc HTTPS. Kiểm tra Bleach và một phim mới từ danh sách, rồi một mục Tiếp tục xem.
2. Trong Phim4K, để trống URL kho Free để dùng cấu hình tự động của app gốc. Thử Thương Nguyên Đồ ở Free1; nhãn Core VIP/Free1/Free2 vẫn phân biệt rõ.
3. Nếu VIP lỗi, ghi tên phim, tên server, thời điểm và thông báo; không gửi cookie, token hay URL ký đầy đủ. Audio/subtitle VIP chỉ có thể xác nhận sau khi video VIP thực sự phát.
