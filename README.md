# AnPinime (iOS 15+)

Ứng dụng xem anime với danh sách phim, tìm kiếm, thể loại và trình phát toàn màn hình. Màn hình chờ phim dùng ảnh nền và tên phim nhấp nháy; trình phát có danh sách tập, tua, tốc độ, tỉ lệ hình, khóa chạm, độ sáng và tự phát tập tiếp theo.

Tác giả: **KingLTN** — Telegram [@kingltnn](https://t.me/kingltnn).

Khi mở phim, app chuyển sang hướng ngang và trở lại hướng dọc khi thoát. Bảng tập và cài đặt dùng Liquid Glass trên iOS 26; iOS 15–18 dùng nền material. Ảnh phim được tải cùng User-Agent, Referer và cookie của phiên kết nối, có cache và làm mới sau khi đổi tên miền.

## Cơ chế tên miền động

Nguồn chuẩn là `https://bit.ly/animevietsubtv`. `DomainResolver` thực hiện request với redirect, lấy URL phản hồi cuối cùng và chỉ giữ `scheme://host`. Domain hợp lệ được cache để lần mở tiếp theo nhanh hơn. Nếu shortlink tạm thời lỗi, app thử domain đã cache rồi mới dùng danh sách dự phòng.

App không khóa dữ liệu vào `animevietsub.vip`, `.sale` hay `.xyz`; mọi URL ảnh, danh sách, tìm kiếm, chi tiết và tập đều được chuẩn hóa tương đối theo domain vừa resolve.

## Cloudflare/CAPTCHA

Khi request dữ liệu gặp HTTP 403 hoặc trang xác minh, app thử lại bằng phiên WebKit ở nền. Trang đã có dữ liệu được đọc trực tiếp, đồng bộ cookie và tiếp tục đúng yêu cầu đang chờ. Chỉ khi phát hiện phần xác minh có thể tương tác mới mở cửa sổ; cửa sổ tự đóng sau khi website cho truy cập. Trang thông thường chứa script Cloudflare không bị xem là CAPTCHA.

## Dữ liệu và trình phát

- Danh sách được đọc từ HTML công khai bằng nhiều selector dự phòng (`TPost`, `ml-item`, `film-item`, `movie-item`).
- Tìm kiếm dùng `/tim-kiem/{từ-khóa}/`.
- Thể loại và trạng thái dùng các đường dẫn của website nguồn.
- Trình phát ưu tiên cơ chế native: đọc `filmID` và `data-hash`, POST `/ajax/player`, giải AES-CBC bằng khóa SHA-256 rồi giải nén dữ liệu. Nếu cơ chế đó thay đổi hoặc lỗi, app tự chuyển sang trình phát WKWebView và dò URL video để mở bằng AVPlayer.

URL video phát hiện từ iframe (kể cả manifest của player dùng blob) được chuyển sang AVPlayer cùng cookie và Referer của iframe. Nếu native không phát được, app tiếp tục phiên video WebKit. Nút phát vẫn khả dụng khi đã nhận metadata nhưng chưa có khung hình.

## Build IPA

Workflow `.github/workflows/build-ipa.yml` tạo IPA chưa ký:

1. Mở tab **Actions** của repository.
2. Chạy **Build AnPinime IPA**, hoặc push vào nhánh `main`.
3. Tải artifact `AnPinime_UNSIGNED`.
4. Ký IPA bằng ESign/chứng chỉ hợp lệ trước khi cài.

Bundle ID: `com.xemphim.aipinime`. Tên hiển thị: `AnPinime`. Gói ứng dụng: `anpinime.app`. Các IPA tham chiếu không được đưa lên Git.

Logo sử dụng `logo.png`. Animation `Code_Generated_Image.gif` chỉ dùng khi tải danh sách, tìm kiếm và chi tiết; phần nền đen được hòa bằng screen blending trên nền tối. Màn hình chờ phát phim dùng ảnh phim riêng.

## Kiểm thử

Workflow kiểm tra parser, nguồn ảnh lazy-load, trạng thái phát và thao tác tạm dừng. Khi chạy thủ công với `preview=true`, simulator phát video mẫu qua iframe của máy chủ cục bộ yêu cầu cookie/Referer; chỉ đạt khi thời gian phát vượt một giây và màn hình nằm ngang, cho cả AVPlayer và WebKit. Sau đó chụp các màn hình giao diện. Fixture và chế độ kiểm thử không nằm trong bản Release.

## Giới hạn

Website nguồn có thể thay HTML, player hoặc chính sách chống bot bất kỳ lúc nào. Resolver xử lý việc đổi domain, nhưng selector và cơ chế player vẫn cần cập nhật nếu website thay đổi cấu trúc lớn.
