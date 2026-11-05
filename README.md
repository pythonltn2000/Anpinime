# AnPinime (iOS 15+)

Ứng dụng xem anime và phim với danh sách, tìm kiếm, thể loại và trình phát toàn màn hình. Mỗi lần khởi động, chọn **Anime** hoặc **Phim**; chạm logo ở trang chủ để chọn lại. Trong mục Phim, menu cạnh logo đổi giữa **Nguồn phim 1 (NguonC)**, **Nguồn phim 2 (Phim4K)** và **Nguồn phim 3 (KKPhim)**. Danh sách, tìm kiếm và tập phim của các nguồn không bị trộn chung.

Màn hình chờ phim dùng ảnh nền và tên phim nhấp nháy; trình phát có danh sách tập, tua, tốc độ, tỉ lệ hình, khóa chạm, độ sáng và tự phát tập tiếp theo. Luồng native có nhiều track cho phép chọn âm thanh và phụ đề trong cài đặt trình phát.

Tác giả: **KingLTN** — Telegram [@kingltnn](https://t.me/kingltnn).

Khi mở phim, app chuyển sang hướng ngang và trở lại hướng dọc khi thoát. Bảng tập và cài đặt dùng Liquid Glass trên iOS 26; iOS 15–18 dùng nền material. Ảnh phim được tải cùng User-Agent, Referer và cookie của phiên kết nối, có cache và làm mới sau khi đổi tên miền.

## Cơ chế tên miền động

Nguồn chuẩn là `https://bit.ly/animevietsubtv`. `DomainResolver` thực hiện request với redirect, lấy URL phản hồi cuối cùng và chỉ giữ `scheme://host`. Domain hợp lệ được cache để lần mở tiếp theo nhanh hơn. Nếu shortlink tạm thời lỗi, app thử domain đã cache rồi mới dùng danh sách dự phòng.

App không khóa dữ liệu vào `animevietsub.vip`, `.sale` hay `.xyz`; mọi URL ảnh, danh sách, tìm kiếm, chi tiết và tập đều được chuẩn hóa tương đối theo domain vừa resolve.

## Cloudflare/CAPTCHA

Khi request dữ liệu gặp HTTP 403 hoặc trang xác minh, app thử lại bằng phiên WebKit ở nền. Trang đã có dữ liệu được đọc trực tiếp, đồng bộ cookie và tiếp tục đúng yêu cầu đang chờ. Chỉ khi phát hiện phần xác minh có thể tương tác mới mở cửa sổ; cửa sổ tự đóng sau khi website cho truy cập. Trang thông thường chứa script Cloudflare không bị xem là CAPTCHA.

## Dữ liệu và trình phát

### Anime

- Danh sách được đọc từ HTML công khai bằng nhiều selector dự phòng (`TPost`, `ml-item`, `film-item`, `movie-item`).
- Tìm kiếm dùng `/tim-kiem/{từ-khóa}/`.
- Thể loại và trạng thái dùng các đường dẫn của website nguồn.
- Trình phát ưu tiên cơ chế native: đọc `filmID` và `data-hash`, POST `/ajax/player`, giải AES-CBC bằng khóa SHA-256 rồi giải nén dữ liệu. Nếu cơ chế đó thay đổi hoặc lỗi, app tự chuyển sang trình phát WKWebView và dò URL video để mở bằng AVPlayer.

URL video phát hiện từ iframe (kể cả manifest của player dùng blob) được chuyển sang AVPlayer cùng cookie và Referer của iframe. Nếu native không phát được, app tiếp tục phiên video WebKit. Nút phát vẫn khả dụng khi đã nhận metadata nhưng chưa có khung hình.

### Nguồn phim 1 · NguonC

Thay Film4k.net bằng `https://phim.nguonc.com`: danh sách `/api/films/phim-moi-cap-nhat`, tìm kiếm `/api/films/search?keyword=...`, chi tiết `/api/film/{slug}`. Thể loại dùng slug riêng của NguonC (ví dụ `phim-hai`, `khoa-hoc-vien-tuong`), không dùng slug KKPhim. Đọc đầy đủ máy chủ/tập trong `movie.episodes[].items`, ưu tiên HLS nếu có, dùng WebKit với nguồn chỉ có embed. ID nội bộ `film4k` được giữ để tương thích dữ liệu và fixture cũ.

### Nguồn phim 3 · KKPhim

Dùng API `https://phimapi.com` được công bố tại [tài liệu KKPhim](https://www.kkphim.com/api-document). Danh sách `/danh-sach/phim-moi-cap-nhat-v3`, tìm kiếm `/v1/api/tim-kiem`, thể loại `/v1/api/the-loai/{slug}` và chi tiết `/phim/{slug}`. Danh sách và tập mang định danh `.kkphim`, tách biệt nguồn 2 dù cấu trúc JSON tương thích.

### Chuyển nguồn và độ ổn định

- Cache trang chủ riêng theo nguồn trong 5 phút; cache danh sách/chi tiết trong 2 phút, có giới hạn số mục. Làm mới thủ công xóa cache liên quan.
- Hiển thị trang đầu ngay khi có dữ liệu, sau đó tải các hàng movie còn lại đồng thời. Không chờ gom máy chủ từ nhà cung cấp khác khi mở chi tiết.
- Đổi nguồn tạo lại các tab và ngăn kết quả tìm kiếm cũ ghi đè kết quả mới. Tìm kiếm chờ 350 ms sau khi nhập và hủy yêu cầu cũ.
- Anime đọc cả trang xem phim để bổ sung danh sách tập; khi chưa có danh sách, chờ DOM WebKit ổn định. Không giới hạn số tập trong parser, sắp xếp nhãn tập dạng số và bỏ liên kết xem phim trùng.
- Dùng tên miền anime đã lưu trước, resolve lại khi lỗi kết nối; thử lại một lần với lỗi mạng/HTTP 5xx. Yêu cầu WebKit bị hủy khi tác vụ không còn cần.
- Web player đặt viewport theo thiết bị, bỏ inset tự động và transform của trang; mặc định giữ tỉ lệ video (`contain`). Các tab dùng điều hướng một cột trên điện thoại. Bỏ dòng trạng thái “Đã kết nối”.

### Nguồn phim 2 · app Phim4K

Nguồn này sử dụng cấu hình của IPA Phim4K 2.8.4, không phải website Film4k.net. `MovieSourceDirectory` đọc directory AES-GCM của app và lưu địa chỉ hợp lệ gần nhất. Tích hợp ba kho của app:

- **Phim4K Core**: trang chủ, phim lẻ/phim bộ, tìm kiếm, thể loại/quốc gia theo ID của REST API `/rest-api/v130/`. Chi tiết dùng `videos_id`; giữ toàn bộ máy chủ trong `videos` và các phần/tập trong `season`.
- **Phim4K · Free1**: API định dạng A, qua địa chỉ `free1` do app công bố.
- **Phim4K · Free2**: API định dạng B, qua địa chỉ `free2` do app công bố. Khi máy chủ này lỗi, hiển thị lỗi; không đổi sang `phim.nguonc.com`.

Kết quả tìm kiếm ghi rõ kho. Mỗi danh mục gắn với đúng kho và endpoint. Free1 hiện có danh mục giống KKPhim ở phía máy chủ; điều này không có nghĩa Core và KKPhim là một nguồn. App không tự gọi trực tiếp NguonC/KKPhim để thay dữ liệu Core.

Các bản 4K/Remux/MKV giữ nguyên nhãn và liên kết từ Core. Khi phát, chọn lại đúng ID máy chủ/tập trong phản hồi mới; không gắn nhãn VIP lên một link Free1 thay thế. Máy chủ Vietsub/lồng tiếng ở NguonC, KKPhim và Free1/Free2 cũng được chọn theo tên máy chủ + slug tập, tránh đổi nhầm khi API sắp xếp lại danh sách.

Tùy chọn URL thủ công trong Cài đặt vẫn dành cho API Free1/Free2. Để trống để dùng đầy đủ cấu hình tự động của app Phim4K. Tài khoản, đăng ký và plugin từ app tham chiếu không được sử dụng.

### Phát phim và lịch sử tìm kiếm

Ưu tiên link HLS do API cung cấp. Nếu link trực tiếp lỗi, không tự chuyển sang trang embed có quảng cáo. Với phim chỉ có embed, trình phát loại video quảng cáo khỏi việc chuyển sang AVPlayer và khỏi sự kiện tự chuyển tập. JW Player dùng nguồn trong playlist của phim, không lấy video đầu trang hoặc một request m3u8 bất kỳ. Giữ màn hình xác minh khi player còn chờ tải.

Lịch sử tìm kiếm lưu trên thiết bị, riêng cho Anime/NguonC/Phim4K/KKPhim, tối đa 20 từ khóa mỗi nguồn. Lưu khi bấm Tìm trên bàn phím hoặc mở một kết quả; chạm từ khóa cũ để tìm lại, vuốt để xóa từng mục hoặc chọn Xóa lịch sử.

## Build IPA

Kho đang chuyển sang `pythonltn2000/Anpinime`. Chọn workflow **Build IPA only**
trên nhánh `main`: một job macOS, giới hạn 20 phút, không Simulator và không tự
chạy khi push. Tải artifact `AnPinime_UNSIGNED`, ký bằng chứng chỉ hợp lệ rồi cài.
Artifact được giữ 3 ngày. [Chính sách tiết kiệm Actions](Tools/build-cost-policy.md).

Kiểm tra phù hợp chạy trong workspace Linux trước build; Simulator và PiP máy
thật cần kiểm chứng riêng. Build thành công không có nghĩa mọi nguồn hoặc PiP
đã được sửa. Workflow **Full playback verification (manual)** chỉ dùng khi được
người dùng yêu cầu rõ. Không tự retry hoặc chạy song song cả bộ kiểm tra.

Bundle ID: `com.xemphim.aipinime`. Tên hiển thị: `AnPinime`. Gói ứng dụng: `anpinime.app`. Các IPA tham chiếu không được đưa lên Git.

Logo sử dụng `logo.png`. Animation `Code_Generated_Image.gif` chỉ dùng khi tải danh sách, tìm kiếm và chi tiết; phần nền đen được hòa bằng screen blending trên nền tối. Màn hình chờ phát phim dùng ảnh phim riêng.

Mục Phim có GIF `AnyAnime/Resources/MovieLoading.gif` tạo từ `logo2.png`. Khởi động kết hợp hai logo; chuyển Anime/Phim dùng hiệu ứng tách mảnh và hiện logo mới bằng Canvas. Reduce Motion dùng chuyển mờ nhẹ. Các icon trình phát dùng đường nét tạo bằng Morphicons 2.0.0 và vẽ native với CAShapeLayer; không nhúng WebView cho icon. Bảng chọn track dùng ID ổn định thay vì chỉ số hàng. Xem [ghi chú tài nguyên](Tools/animation-assets.md).

## Kiểm thử

Workflow kiểm tra parser anime và JSON của ba nguồn phim, URL ảnh, định danh nguồn, thứ tự phần/tập, chuẩn hóa PNG/HLS/Range, trạng thái phát và thao tác tạm dừng. Khi chạy thủ công với `preview=true`, simulator kiểm tra AVPlayer, WebKit và hai provider bằng máy chủ cục bộ. Fixture Film4k yêu cầu cookie/Referer/ticket, cố ý trả video hết hạn ở lần đầu rồi HLS có segment bọc PNG để kiểm tra tự làm mới URL và relay. Chỉ đạt khi thời gian phát vượt một giây và màn hình nằm ngang.

Các bước riêng kiểm tra cả hai nguồn trực tiếp trên mạng và lưu JSON nếu phát thành công; chúng không chặn build vì phụ thuộc website bên ngoài. Phải có `playback-film4k-live.json`/`playback-phim4k-live.json` trong artifact mới tính là xác nhận phát trực tiếp, không chỉ nhìn trạng thái workflow. Fixture cũng kiểm tra chọn/tắt phụ đề, bỏ qua ID cũ và chọn chất lượng. Fixture và chế độ kiểm thử không nằm trong bản Release.

## Giới hạn

Website nguồn có thể thay HTML, player hoặc chính sách chống bot bất kỳ lúc nào. Resolver xử lý việc đổi domain, nhưng selector và cơ chế player vẫn cần cập nhật nếu website thay đổi cấu trúc lớn.

### Kiểm tra thay đổi nguồn (27/10/2026)

NguonC: đọc được tài liệu, danh sách và chi tiết/tập; trang embed StreamC yêu cầu Cloudflare trong Chromium của môi trường kiểm tra, nên chưa xác nhận phát thực tế trên iPhone.

KKPhim: đọc được API danh sách, chi tiết, HLS master/media và phần đầu segment MPEG-TS. Đây là kiểm tra dữ liệu media, chưa phải xác nhận giải mã/phát trên iPhone.

Phim4K: directory hiện trả `api.phim4k.space`, `free.cryboiz.workers.dev`, `free2.p4k.dpdns.org`. Core trả trang chủ, tìm kiếm, thể loại/quốc gia, chi tiết phim lẻ và phim bộ. Các mẫu Core giữ được các bản 1080p/2160p/Remux; link `cdn.phim4k.lol` trong mẫu và Free2 hiện lỗi DNS tại môi trường kiểm tra. Không suy đoán đường dẫn thay thế hay tuyên bố các link này đã phát được. AVPlayer chưa hỗ trợ đầy đủ MKV/ASS như mpv trong app gốc.

`Tests/ProviderTests.swift` chạy provider thật qua URLSession giả lập, ghi nhận host/path/header cho trang chủ → tìm kiếm → danh mục → chi tiết → phát; kiểm tra khi lỗi không đổi nguồn, Core giữ nguyên link VIP và API-KEY chỉ gửi đến Core. `Tests/main.swift` kiểm tra ID phần/tập, đảo thứ tự server và lịch sử tìm kiếm. `Tests/player.test.cjs` kiểm tra quảng cáo đứng trước phim, preroll dùng chung thẻ video, kết thúc quảng cáo không chuyển tập, và giữ màn hình xác minh. Fixture Film4k cũ chỉ kiểm tra ticket/relay, không đại diện cho nguồn 1 hiện tại.

### Bản 2.3.2 (build 8): danh mục riêng và tập anime

- KKPhim có đủ 12 danh sách theo website, 26 thể loại và 36 quốc gia dự phòng; thể loại/quốc gia cập nhật từ API của KKPhim. Hai mục phim bộ đang chiếu/đã hoàn thành hiện trả 404 ở API danh sách, nên lấy bảng phim và phân trang từ chính `kkphim.com`, sau đó mở chi tiết qua `phimapi.com`.
- NguonC có 22 thể loại, bốn danh sách TV shows/phim lẻ/phim bộ/phim AI, quốc gia, năm và ngôn ngữ. Menu cập nhật từ website NguonC và có dữ liệu dự phòng khi website lỗi.
- Phim4K đánh dấu kho VIP/Premium riêng với Free1/Free2. Mẫu Wakanda Forever (Core ID 10403) giữ đủ 5 máy chủ: ba bản 1080p và hai bản 2160p, gồm UHD Remux. Đây là xác nhận danh sách, chưa xác nhận phát VIP.
- Parser tập anime chỉ nhận nút/tập trong đúng bộ phim, loại liên kết đăng nhập, bình luận, người dùng và chuỗi HTML trong script. Hỗ trợ dạng URL Bleach `tap-01-114773.html`, không lấy ID 114773 làm số tập. Bộ đợi DOM dùng cùng parser này nên bình luận không còn làm nó tưởng danh sách tập đã tải xong.

Trang Bleach: Sennen Kessen-hen - Kashin-tan hiện trả trang xác minh trong môi trường kiểm tra; fixture kiểm thử dùng dạng URL đã đối chiếu và bình luận mô phỏng, không được xem là xác nhận đủ tập trực tiếp trên iPhone. Luồng ký yêu cầu CDN của VIP và hỗ trợ MKV/ASS vẫn chưa hoàn tất.
