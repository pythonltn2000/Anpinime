# AnPinime (iOS 15+)

Ứng dụng xem anime và phim với danh sách, tìm kiếm, thể loại và trình phát toàn màn hình. Mỗi lần khởi động, chọn **Anime** hoặc **Phim**; chạm logo ở trang chủ để chọn lại. Trong mục Phim, menu cạnh logo đổi giữa **Nguồn phim 1** và **Nguồn phim 2**. Danh sách, tìm kiếm và tập phim của các nguồn không bị trộn chung.

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

### Nguồn phim 1 · Film4k.net

Đọc JSON công khai từ `/api/home`, `/api/search/suggest`, `/api/title/{slug}` và `/api/watch/{slug}`. Hỗ trợ danh sách phân trang, phim lẻ, phim bộ, từng phần và từng tập. Khi bấm xem, lấy URL mới từ watch và phiên `/api/play-ticket`; chấp nhận cả phản hồi có token và phản hồi `{ok:true}` không cần token. Không lưu URL video hết hạn vào danh sách.

Luồng HLS/MP4 dùng AVPlayer cùng cookie/Referer và ticket nếu có. Khi phát lỗi, lấy lại URL một lần rồi mới chuyển sang trình phát website đúng tập. Ticket chỉ được gắn vào URL thuộc máy chủ nguồn. Nguồn ngoài có thể thay đổi codec, API hoặc yêu cầu đăng nhập; app không đảm bảo mọi phim của website đều phát được trên mọi thiết bị.

Film4k có các luồng fMP4 bọc trong PNG. `FilmMediaRelay` chỉ lắng nghe tại loopback của thiết bị, viết lại URL playlist và bỏ lớp PNG hoàn chỉnh trước khi đưa byte video cho AVPlayer. Hỗ trợ init segment, audio, subtitle và Range sau khi chuẩn hóa; không tải phim xuống ổ đĩa. Listener bị đóng khi rời trình phát. Cơ chế này dựa trên định dạng thực tế và cách xử lý trong player công khai của website, không xử lý DRM.

### Nguồn phim 2 · Phim4K

Đây là nguồn riêng, **không phải Film4k.net**. Tích hợp hai họ endpoint tìm thấy khi phân tích IPA 2.8.4: Free1 (`/danh-sach/phim-moi-cap-nhat-v3`, `/v1/api/tim-kiem`, `/phim/{slug}`) và Free2 (`/api/films/phim-moi-cap-nhat`, `/api/films/search`, `/api/film/{slug}`). Hỗ trợ danh sách, tìm kiếm, máy chủ/tập, HLS và embed theo hai cấu trúc JSON tương ứng.

`MovieSourceDirectory` đọc cấu hình AES-GCM công khai của IPA từ `rip.cryboiz.workers.dev/api/add`, chỉ lấy địa chỉ `free1/free2` và lưu địa chỉ hợp lệ gần nhất. Không nhập tài khoản, quảng cáo, token hoặc plugin của app tham chiếu. Phân tích ngày 23/10/2026 xác định máy chủ mới `free.cryboiz.workers.dev` đang trả danh sách/chi tiết thật, với video trong trường `link` trỏ đến HLS không có đuôi `.m3u8`. Relay hỗ trợ cả định dạng này. Những địa chỉ `.lol` ghi cứng trong IPA đã lỗi DNS; backend REST riêng và Free2 chưa được xác nhận hoạt động.

Một số phim trả HTTP 500 từ máy chủ video, trong khi tập 1 của `thuong-nguyen-do` trả playlist HLS hợp lệ. Không tự thay phim lỗi bằng phim khác. Máy chủ Vietsub/lồng tiếng được giữ riêng trong Danh sách tập. Chọn phụ đề/âm thanh rời khi luồng thực sự có track; phụ đề đã ghép vào hình không thể tắt. Chưa hỗ trợ đầy đủ các tệp MKV/ASS mà trình phát mpv của app tham chiếu có thể xử lý.

Khi có địa chỉ thay thế tương thích, vào **Cài đặt → Nguồn phim 2**, nhập URL HTTPS và chọn Kiểu API A/B. Để trống để cập nhật tự động. Địa chỉ mới phải thực sự cung cấp API tương ứng, không chỉ là trang giới thiệu ứng dụng.

## Build IPA

Workflow `.github/workflows/build-ipa.yml` tạo IPA chưa ký:

1. Mở tab **Actions** của repository.
2. Chạy **Build AnPinime IPA**, hoặc push vào nhánh `main`.
3. Tải artifact `AnPinime_UNSIGNED`.
4. Ký IPA bằng ESign/chứng chỉ hợp lệ trước khi cài.

Bundle ID: `com.xemphim.aipinime`. Tên hiển thị: `AnPinime`. Gói ứng dụng: `anpinime.app`. Các IPA tham chiếu không được đưa lên Git.

Logo sử dụng `logo.png`. Animation `Code_Generated_Image.gif` chỉ dùng khi tải danh sách, tìm kiếm và chi tiết; phần nền đen được hòa bằng screen blending trên nền tối. Màn hình chờ phát phim dùng ảnh phim riêng.

Mục Phim có GIF `AnyAnime/Resources/MovieLoading.gif` tạo từ `logo2.png`. Khởi động kết hợp hai logo; chuyển Anime/Phim dùng hiệu ứng tách mảnh và hiện logo mới bằng Canvas. Reduce Motion dùng chuyển mờ nhẹ. Các icon trình phát dùng đường nét tạo bằng Morphicons 2.0.0 và vẽ native với CAShapeLayer; không nhúng WebView cho icon. Bảng chọn track dùng ID ổn định thay vì chỉ số hàng. Xem [ghi chú tài nguyên](Tools/animation-assets.md).

## Kiểm thử

Workflow kiểm tra parser anime và JSON của hai nguồn phim, URL ảnh, định danh nguồn, thứ tự phần/tập, chuẩn hóa PNG/HLS/Range, trạng thái phát và thao tác tạm dừng. Khi chạy thủ công với `preview=true`, simulator kiểm tra AVPlayer, WebKit và hai provider bằng máy chủ cục bộ. Fixture Film4k yêu cầu cookie/Referer/ticket, cố ý trả video hết hạn ở lần đầu rồi HLS có segment bọc PNG để kiểm tra tự làm mới URL và relay. Chỉ đạt khi thời gian phát vượt một giây và màn hình nằm ngang.

Các bước riêng kiểm tra cả hai nguồn trực tiếp trên mạng và lưu JSON nếu phát thành công; chúng không chặn build vì phụ thuộc website bên ngoài. Phải có `playback-film4k-live.json`/`playback-phim4k-live.json` trong artifact mới tính là xác nhận phát trực tiếp, không chỉ nhìn trạng thái workflow. Fixture cũng kiểm tra chọn/tắt phụ đề, bỏ qua ID cũ và chọn chất lượng. Fixture và chế độ kiểm thử không nằm trong bản Release.

## Giới hạn

Website nguồn có thể thay HTML, player hoặc chính sách chống bot bất kỳ lúc nào. Resolver xử lý việc đổi domain, nhưng selector và cơ chế player vẫn cần cập nhật nếu website thay đổi cấu trúc lớn.
