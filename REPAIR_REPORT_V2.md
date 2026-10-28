# Báo cáo sửa chữa AnPinime V2

## Mốc kiểm tra

Ngày 28/10/2026; repository `/home/user/bot/anime`, `main` tại `7feb0e040e1c48e582e0258d542a19c54dc11be3`; working tree sạch trước khi sửa. GitHub cùng commit. Bản ghi baseline và SHA-256 các file nguồn 1/3 ở `dist/repair-v2/`. CI của mốc này đã build và kiểm tra MKV simulator thành công trong run 40667484695.

## Anime: điều tra và sửa

`DomainResolver.resolve` trước đây chấp nhận host khi cú pháp hợp lệ và có thể lưu cả URL trả 403; fallback đầu tiên được chọn không kiểm tra nội dung. Công cụ tra cứu theo shortlink `bit.ly/animevietsubtv` quan sát redirect tới `animevietsub.xyz`; truy cập trực tiếp các `.xyz`, `.zip`, `.fan`, `.bio`, `.sale`, `.vip` trong môi trường này đều trả 403 với trang chi tiết Bleach và trang lịch. Không khẳng định domain nào đã được xác minh trực tiếp trong phiên này. Trang hướng dẫn được lập chỉ mục của nguồn liệt kê `.fan`, `.bio` và shortlink. `.dev` có dữ liệu Next.js nhưng chưa chứng minh được là đích hiện hành của shortlink, nên không tự đặt làm domain chính.

Resolver mới thử một trang chi tiết thật trên các ứng viên đồng thời; chỉ ghi cache bền khi trang HTML có nội dung chi tiết phù hợp và không phải challenge. Nếu tất cả bị chặn, chọn ứng viên tạm để luồng WebKit/xác minh hiện tại có thể hoạt động, không ghi host đó là đã xác minh. Cache host cũ chỉ là ứng viên. Hủy yêu cầu hoặc timeout WebKit không còn bị mặc định báo HTTP 403.

Parser trước đó đã hỗ trợ `/xem-phim/<slug>/tap-N` và payload Next.js nhưng có hai họ website có cấu trúc khác nhau. Những sửa đổi lần này không xem số tập fixture là bằng chứng phát. Không có response DOM thật của năm anime trên domain chính thức trong môi trường này do 403, do đó chưa thể chứng minh số tập/server và phát tập trên iPhone. HTML công khai `.dev` của năm mẫu từ lần trước vẫn là bằng chứng parser đối với cấu trúc đó, không phải bằng chứng xác định host chính thức. `AnimeDetailView`, `Episode.id`, `PlayerView` và logic lịch sử không đổi. Trong mã hiện tại không tìm thấy một kho lịch sử phát riêng để đối chiếu dữ liệu “Tiếp tục xem” của người dùng; cần kiểm tra trên thiết bị.

## Lịch chiếu

Lỗi có căn cứ: parser cũ ưu tiên JSON Next.js và fallback card kiểu Next.js, trong khi trang lịch của nguồn `.sale` được lập chỉ mục hiển thị nhóm thứ/ngày và giờ dạng “21 giờ 00 phút”. Thêm parser cho các nhóm heading và link phim trong danh sách, không gán giờ/trạng thái khi thiếu, không hiển thị WebView. Dữ liệu React được đọc bằng JSON với bộ quét ngoặc hiểu chuỗi escape/nested. Thêm cache native bền qua khởi động, hiển thị thời điểm dữ liệu đã lưu nếu cập nhật lỗi. Fixture legacy là dữ liệu tổng hợp dựa trên cấu trúc ngày/giờ được lập chỉ mục, **không phải bản HTML gốc**. Do response live trả 403, chưa thể xác nhận markup HTML thực tế hoặc đối chiếu giao diện hai ngày trên iPhone.

## Phim4K nguồn 2

Phản hồi người dùng cung cấp chứng minh một worker trả 206 và hỗ trợ Range với User-Agent `oxoo`, nhưng không kèm URL/phiên hợp lệ để thử lại. Không hard-code query, token hoặc tạo chữ ký VIP. User-Agent hiện tại giữ nguyên vì chưa có phép so sánh đối chứng chứng minh cần đổi.

Sửa lỗi chặn trước khi phát khi HEAD trả 405/501 hoặc MIME không rõ: thực hiện GET `Range: bytes=0-2047` qua `Phim4KMediaProbe`. Delegate giữ tối đa 2.048 byte, hủy khi đạt giới hạn kể cả server trả 200 bỏ qua Range, nhận diện chữ ký MP4/MKV/HLS/DASH, phân biệt JSON/HTML và xác thực; redirect khác host được bỏ header nhạy cảm trong probe. Một URL `.model`/`.pb` vẫn được chấp nhận khi MIME hoặc chữ ký phù hợp. Trình phát tiếp tục nhận URL đúng server gốc và header nguồn 2; không thay VIP bằng Free1.

Chưa xác minh luồng resolve của VIP: năm URL Wakanda trong fixture trước gặp lỗi DNS; chưa có phiên hoặc URL hợp lệ để thử và chưa quan sát frame thực. Do đó audio/subtitle VIP chưa thể xác minh. Probe GET 2 KB không chứng minh seek toàn bộ hoặc first frame.

### Giới hạn relay

`FilmMediaRelay` dùng chung vẫn tải toàn bộ tài nguyên trước khi áp dụng Range. Nó được dùng cho HLS/nguồn khác; file progressive nguồn 2 hiện được chuyển trực tiếp tới libmpv, không qua relay. Chưa viết relay streaming/ánh xạ offset và chưa chứng minh Range playback/seek >12 GB qua relay; sửa sai logic dùng chung có thể phá nguồn 1/3. Đây là việc còn thiếu, không được coi là đã sửa xong. Test 12 GB dưới đây xác minh probe và server ảo, **không** xác minh relay hoặc phát phim thật.

## Kiểm thử và bảo vệ nguồn 1/3

- Swift parser/catalog/schedule tests: 116 PASS trên Swift 5.10.1/Linux; gồm fixture nhiều tập/server, domain challenge, cache và lịch có/không giờ; JSON lịch có nested object và dấu ngoặc trong chuỗi.
- Server ảo có tổng tài nguyên 12.285.989.889 byte, không cấp phát toàn tệp. Kiểm tra origin với GET không Range, `0-`, `100-199`, gần cuối tệp, suffix, 416, server bỏ Range, HEAD 405 và redirect.
- `Phim4KMediaProbe` kiểm tra thật 206, server bỏ Range trả 200, redirect, 403 và JSON; giới hạn 2.048 byte. Chưa kiểm thử relay, HLS rendition, upstream chunked hay huỷ từ UI trong các bài này.
- `Tests/ProviderTests.swift` thêm fixture HEAD 405 → GET Range và phân biệt auth/JSON. Hồi quy provider nguồn 1/3 chạy trong CI macOS.
- Checksum trước/sau của `MovieProvider`, `MovieCatalog`, `MovieSourceDirectory`, `FilmMediaRelay`, `FilmMediaTransform`, `MPVPlaybackController`, `PlayerView`, `Models` giữ nguyên. Không chứng minh phát nguồn 1/3 trên iPhone thật.
- Build iOS của bản V2: xem kết quả workflow GitHub Actions ứng với commit chứa báo cáo này. Không suy diễn thành công từ build cũ; simulator không thay thế iPhone thật.

## File thay đổi

`AnyAnime/Info.plist`, `AnyAnime/DomainResolver.swift`, `HTMLParser.swift`, `AnimeService.swift`, `VerificationView.swift`, `AnimeScheduleView.swift`, `AnimeScheduleStore.swift`, `Phim4KCatalog.swift`, `Phim4KProvider.swift`, `Phim4KMediaProbe.swift`, `.github/workflows/build-ipa.yml`, `Tests/main.swift`, `Tests/ProviderTests.swift`, `Tests/RangeProbeTests.swift`, `Tests/range_probe_server.py`, `Tests/range_virtual_test.py`, `Tests/Fixtures/anime-schedule-legacy.html` và báo cáo này.

## Kiểm tra trên iPhone và thu thông tin

1. Kiểm tra website anime trên chính kết nối điện thoại, hoàn tất sheet xác minh nếu xuất hiện; mở năm phim mới, so từng tập/server với web và thử mục Tiếp tục xem. Ghi tên phim, tập, thời điểm và thông báo; không gửi cookie hoặc link có chữ ký.
2. So hai ngày lịch với website, thử refresh và tắt mạng sau khi đã có dữ liệu để kiểm tra nhãn lịch đã lưu.
3. Trong Phim4K thử từng server của Wakanda; ghi nhãn server, thông báo, thời điểm và liệu có frame/âm thanh/phụ đề thực. Nếu lấy log DEBUG, chỉ chia sẻ host, HTTP status, loại lỗi, số track và Range; xóa query, cookie, token và URL đầy đủ.
4. Kiểm tra nguồn 1/3 với home, tìm kiếm, chi tiết, server, phát và tua.
