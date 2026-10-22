# AnyAnime Rewrite (iOS 15+)

Ứng dụng iOS native được viết lại từ hành vi quan sát được của IPA cũ, không sử dụng mã nguồn gốc. Giao diện gồm Trang chủ, Tìm kiếm, Thể loại, Chi tiết anime, Danh sách tập, Trình phát và Giới thiệu.

## Cơ chế tên miền động

Nguồn chuẩn là `https://bit.ly/animevietsubtv`. `DomainResolver` thực hiện request với redirect, lấy URL phản hồi cuối cùng và chỉ giữ `scheme://host`. Domain hợp lệ được cache để lần mở tiếp theo nhanh hơn. Nếu shortlink tạm thời lỗi, app thử domain đã cache rồi mới dùng danh sách dự phòng.

App không khóa dữ liệu vào `animevietsub.vip`, `.sale` hay `.xyz`; mọi URL ảnh, danh sách, tìm kiếm, chi tiết và tập đều được chuẩn hóa tương đối theo domain vừa resolve.

## Cloudflare/CAPTCHA

Khi request dữ liệu gặp HTTP 403 hoặc trang xác minh, app mở WKWebView dùng kho cookie bền vững. Người dùng hoàn tất CAPTCHA và bấm **Đã xác minh — thử lại**. Cookie sau đó được đồng bộ sang `HTTPCookieStorage` để các màn hình native tiếp tục lấy HTML. App không tự động vượt CAPTCHA.

## Dữ liệu và trình phát

- Danh sách được đọc từ HTML công khai bằng nhiều selector dự phòng (`TPost`, `ml-item`, `film-item`, `movie-item`).
- Tìm kiếm dùng `/tim-kiem/{từ-khóa}/`.
- Thể loại và trạng thái dùng các path quan sát được từ app cũ.
- Trình phát ưu tiên cơ chế native: đọc `filmID` và `data-hash`, POST `/ajax/player`, giải AES-CBC bằng khóa SHA-256 rồi giải nén dữ liệu. Nếu cơ chế đó thay đổi hoặc lỗi, app tự chuyển sang trình phát WKWebView và dò URL video để mở bằng AVPlayer.

## Build IPA

Workflow `.github/workflows/build-ipa.yml` tạo IPA chưa ký:

1. Mở tab **Actions** của repository.
2. Chạy **Build AnyAnime IPA**, hoặc push vào nhánh `main`.
3. Tải artifact `AnyAnime_Rewrite_UNSIGNED`.
4. Ký IPA bằng ESign/chứng chỉ hợp lệ trước khi cài.

Bundle ID mặc định là `com.34306.anyani`. Dự án không đưa IPA tham chiếu vào Git; `*.ipa` đã được thêm vào `.gitignore`.

## Giới hạn

Website nguồn có thể thay HTML, player hoặc chính sách chống bot bất kỳ lúc nào. Resolver xử lý việc đổi domain, nhưng selector và cơ chế player vẫn cần cập nhật nếu website thay đổi cấu trúc lớn.

