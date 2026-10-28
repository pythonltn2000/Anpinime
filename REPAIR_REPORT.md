# Báo cáo sửa AnimeVietsub và Movie nguồn 2

Ngày: 28/10/2026. Repository làm việc: `/home/user/bot/anime`; mốc ban đầu `9b89983271d46dff740c40924e713f74f2d080be` (`main`), trùng `origin/main` khi bắt đầu. Working tree ban đầu sạch. Các kết quả kiểm thử bên dưới được ghi trước khi đẩy bản sửa; hãy kiểm tra workflow của commit mới để xác nhận build iOS.

Báo cáo trước đây khẳng định đã phát thành công cả năm server VIP, tốc độ và lịch đầy đủ. Những khẳng định đó không có bằng chứng phát thực tế trong lần kiểm tra này và không được dùng làm kết quả nghiệm thu. Không tạo chữ ký hoặc trích xuất bí mật để kiểm thử.

## Anime: nguyên nhân và sửa đổi

Shortlink `bit.ly/animevietsubtv` và hai domain dự phòng `.vip`/`.sale` trả 403 ở môi trường này; không xác nhận được domain cuối cùng của shortlink. Trong khi đó, năm trang chi tiết công khai trên `animevietsub.dev` trả HTTP 200. Các trang đó có link dạng `/xem-phim/<slug>/tap-N` trong khi chi tiết là `/phim/<slug>`; danh sách dài còn nằm trong các đoạn React/Next.js được gửi theo luồng. Parser tại mốc ban đầu không nhận dạng đúng liên kết và danh sách này. `.dev` chỉ là mẫu điều tra, không được thêm làm domain mặc định, vì chưa chứng minh được shortlink chính thức chuyển tới nó.

Parser hiện chỉ nhận route mới nếu slug khớp bộ phim; với danh sách Next.js chỉ dựng URL từ các số tập có thật trong dữ liệu và khi DOM cùng trang đã xác nhận cấu trúc URL. Link bình luận và bộ phim khác vẫn bị loại. Server cũ, special/OVA và ID tập cũ được giữ; không tạo tập mặc định. Thêm fixture đã loại dữ liệu không cần thiết ở `Tests/Fixtures/anime-next-episodes.html`.

Metadata được phân tích và hiển thị trước; danh sách tập được phân tích trên tác vụ nền. Khi dữ liệu Next.js có đủ số tập được khai báo, không cần tải trang xem thứ hai; nếu thiếu, thử trang xem và DOM WebKit ẩn. Đã bỏ điều kiện sai khiến chỉ đọc DOM động khi có CAPTCHA; refresh bỏ cache HTML liên quan. Danh sách rỗng không được cache là kết quả thành công, và UI báo chưa đọc được danh sách thay vì khẳng định phim không có tập.

Trên cùng HTML mẫu One Piece trong Linux, đo parser ba lần: mốc cũ mất 623–695 ms để trả metadata kèm 0 tập; đường chỉ phân tích metadata mới mất 110–162 ms. Đây là phép đo parser tại máy kiểm thử, không bao gồm mạng hoặc thời gian hiển thị iPhone. Với năm HTML thực tế, mốc cũ trả 0 tập cho cả năm; parser mới trả lần lượt 1.203, 2, 2, 9 và 25 tập. Năm trang xem tập 1 tương ứng trả HTTP 200; chưa xác nhận video thực sự phát. Cơ chế tiếp tục xem và `Episode.id` không sửa, nhưng chưa kiểm thử được dữ liệu lịch sử thật trên iPhone.

## Lịch chiếu

Giao diện SwiftUI native đã tồn tại ở mốc ban đầu, không hiển thị WKWebView. Parser giờ đọc JSON thực tế trong các đoạn streamed, chấp nhận thiếu poster/giờ, không tự gán thứ Hai, chất lượng hoặc trạng thái khi nguồn không cung cấp. Lịch sắp theo giờ được cung cấp; giao diện ghi rõ giờ theo website. Bỏ fallback cứng sang `.dev`. Cache gần nhất được giữ trong bộ nhớ; nếu cập nhật thất bại trong cùng phiên, UI giữ lịch và hiển thị thời điểm cập nhật. Chưa có cache bền qua lần khởi động và chưa xác minh được múi giờ gốc của website.

HTML mẫu `.dev` tải ngày kiểm tra có 31 cặp phim/ngày khác nhau có thứ xác định; không tự gán mười bản ghi không có ngày. Điều này không chứng minh đây là toàn bộ lịch của domain chính thức. Swift tests có fixture thứ Hai/Chủ nhật và trường hợp không có thứ; chưa có kiểm thử UI trên iPhone cho bản local.

## Movie nguồn 2: server, resolver và trình phát

Danh mục/tìm kiếm Core và Free1/Free2 giữ nguyên. Server Core có `video_file_id` hoặc `episodes_id` vẫn xuất hiện khi thiếu `file_url`; chọn server chưa có URL sẽ nhận thông báo cần resolver hợp lệ. Không đổi sang Free1 và không tạo URL khác. `resolveCore` không còn gọi cơ chế ký URL chưa được xác minh ở mốc ban đầu; đoạn mã cũ vẫn nằm trong repository nhưng không được gọi từ luồng này.

Đối với URL video trực tiếp, gửi HEAD giới hạn thời gian để kiểm tra HTTP/MIME trước khi chuyển cho trình phát: 401/403 báo `AUTH_REQUIRED`, JSON/HTML báo phản hồi trung gian, và lỗi kết nối hay HTTP khác được thông báo. HLS, DASH, MP4 và MKV được nhận diện theo MIME hoặc phần mở rộng. HEAD không tải toàn bộ video; một số máy chủ hợp lệ có thể từ chối HEAD, hiện sẽ báo lỗi và cần bổ sung cơ chế kiểm tra GET Range có giới hạn trong tương lai. Embed vẫn dùng trình phát web. Không khẳng định phát VIP: cả năm URL trong fixture Wakanda đều gặp lỗi phân giải tên miền tại môi trường kiểm thử; chưa có phiên VIP hợp lệ hoặc phản hồi resolver đã xác minh. Các câu log HTTP 200/MIME cố định đã được thay bằng phản hồi thực tế.

Âm thanh, phụ đề nhúng/rời và hai lớp phụ đề do libmpv đã có ở mốc ban đầu. CI cũ đã xác nhận fixture MKV hai audio/hai phụ đề, không phải phim VIP trực tiếp; các lựa chọn thực tế trên một VIP đang phát chưa được xác nhận trong lần này.

## Nguồn 1 và 3, kiểm thử và build

Không thay đổi `MovieProvider.swift`, `MovieCatalog.swift`, `MovieSourceDirectory.swift`, `FilmMediaRelay.swift`, `FilmMediaTransform.swift`, `PlayerView.swift` hoặc `Models.swift`: checksum SHA-256 trùng mốc ban đầu; bản ghi nằm ở `dist/repair-baseline/movie-protected.sha256` (thư mục `dist` không được Git theo dõi). Thay đổi `HTMLParser` và `AnimeService` liên quan riêng anime; thay đổi provider/catalog còn lại chỉ dành cho nguồn 2.

- Bộ Swift parser/catalog chạy local: **105 kiểm tra PASS**, gồm fixture 12 tập, slug khác route, nhiều server, special, nhận diện media, bảo toàn danh sách Wakanda và các fixture nguồn 1/3. Dùng Swift 5.10.1 trên Linux với SDK tương thích tạm; không phải biên dịch iOS.
- `Tests/player.test.cjs`: **5 nhóm PASS**, gồm phân biệt quảng cáo và nội dung, lựa chọn track JW và giữ bộ giải mã StreamC.
- `Tests/verify_repairs.cjs`: chỉ là kiểm tra hình dạng mẫu, không chứng minh ký VIP hoặc kiểm thử production; đã bỏ kiểm thử tạo chữ ký giả.
- Bộ provider URLSession trên Linux chạy được bốn kiểm tra nguồn 1, sau đó bị treo ở lớp networking và dừng bằng timeout. Lần thử riêng nguồn 2 cũng timeout; các bài test provider bổ sung 403/JSON chưa được xác nhận chạy xong ở môi trường này. Đây là giới hạn kiểm thử, không phải PASS.
- `swiftc -frontend -parse AnyAnime/*.swift` và `git diff --check` thành công. Không có Xcode/iOS SDK trong Linux, nên bản local **chưa được build iOS**.
- [GitHub Actions run 40654189602](https://github.com/thuyan1510/AnPinime/actions/runs/40654189602) thành công ở commit `ef05b3e`, bao gồm fixture MKV trên simulator và IPA chưa ký. Đây là build trước các chỉnh sửa local hiện tại, không chứng minh bản hiện tại build hoặc phát được.

## File thay đổi

`AnyAnime/HTMLParser.swift`, `AnimeService.swift`, `AnimeDetailView.swift`, `AnimeScheduleView.swift`, `Phim4KCatalog.swift`, `Phim4KProvider.swift`, `Tests/main.swift`, `Tests/ProviderTests.swift`, `Tests/verify_repairs.cjs`, fixture `Tests/Fixtures/anime-next-episodes.html` và báo cáo này.

## Kiểm tra trên iPhone sau khi build bản local bằng macOS/Xcode

1. Mở anime từ danh sách mới, kiểm tra metadata xuất hiện trước và đối chiếu toàn bộ tập, server, OVA với website; thử cả một mục đã có trong Tiếp tục xem và refresh khi mạng lỗi/xác minh.
2. Mở lịch chiếu, so giờ và ngày với website; thử đổi ngày, làm mới và ngắt mạng sau khi lịch đã tải.
3. Mở Wakanda Forever ở Phim4K, xác nhận đủ năm server, chọn từng server và ghi lỗi HTTP/xác thực nếu có. Chỉ sau khi phát được mới thử đổi audio, phụ đề chính/phụ, file rời và tua.
4. Kiểm tra tìm kiếm, danh mục, chi tiết và phát của NguonC và KKPhim trên cùng bản build. Không có bằng chứng thiết bị thật cho các bước này trong lần sửa hiện tại.
