# AnyAnime AutoRedirect (iOS 15+)

Đây là **một bản dựng lại phần truy cập phim**, không phải bản vá nguyên vẹn mã Swift của IPA gốc. Nó dùng `WKWebView` để hiển thị website, nên nội dung, điều hướng và trình phát phụ thuộc trực tiếp vào website. Thiết kế giao diện gốc của AnyAnime không được giữ nguyên.

## Tính năng

- Mở `https://bit.ly/animevietsubtv` như trình duyệt iOS. Theo HTTP redirect, JS redirect trong WKWebView.
- Có các nguồn dự phòng, gồm `https://www.animevietsub.sale/` (đã đọc được danh sách qua công cụ kiểm tra 22/10/2026).
- Lưu cookie trong chính app, hỗ trợ trang xác minh có tương tác (không tự động vượt CAPTCHA).
- Ghi nhật ký URL, HTTP status, tiêu đề, số link/phần tử HTML để chẩn đoán.
- Có nút chọn nguồn, trang chủ, tiến/lùi, tải lại.
- Tùy chọn nhập URL cấu hình JSON riêng trên HTTPS để thay danh sách nguồn về sau, không cần build lại.

## Build IPA bằng GitHub Actions

1. Tạo một repository GitHub mới và tải **toàn bộ nội dung thư mục dự án** vào root repository, bao gồm thư mục `.github/workflows`.
2. Vào tab **Actions** → workflow **Build AnyAnime AutoRedirect IPA** → **Run workflow**.
3. Khi workflow hoàn tất, lấy Artifact `AnyAnime_AutoRedirect_UNSIGNED` (trong đó có IPA chưa ký).
4. Dùng **ESign** ký file IPA với chứng chỉ/profile còn hiệu lực, rồi cài lên thiết bị.
5. Nếu thiết bị đã cài AnyAnime cũ cùng Bundle ID `com.34306.anyani`, cần lưu lại dữ liệu cần thiết trước khi cài bản mới hoặc đổi Bundle ID trong `project.yml`.

## Cập nhật domain từ xa

Tải `config.sample.json` lên GitHub Pages hoặc một HTTPS endpoint mà bạn kiểm soát. Trong app bấm **Nguồn phim** → **Cấu hình nguồn từ xa** rồi nhập URL JSON. App cập nhật danh sách nguồn từ JSON khi khởi chạy; bạn có thể chỉnh domain trong JSON khi website thay đổi.

Nếu không nhập cấu hình, app vẫn có URL Bitly và fallback mặc định. Bản này không bảo đảm tự động tìm được một domain không nằm trong chuỗi redirect hoặc danh sách fallback.

## Giới hạn & kiểm thử

- Môi trường tạo file ở đây **không có Xcode hoặc iOS SDK**, nên chưa build/kiểm thử IPA mới trên iPhone. Mã Swift đã được kiểm tra cú pháp; GitHub Actions là bước build thật.
- Bản mới là trình duyệt tích hợp; **không kế thừa** giao diện/phân tích danh sách phim gốc hay tính năng ngoại tuyến.
- Safari và WKWebView có cookies riêng; có thể phải xác minh lại trên app.
- Một số web chống bot, DRM, chính sách bảo mật và phát video có thể giới hạn WKWebView.
- Mặc dù dùng Bitly và JSON động, vẫn phải thay code khi website thay đổi tính năng lớn, chính sách đăng nhập hoặc phát video.

## Khác với bản sửa trực tiếp IPA gốc

File `AnyAnime_sale_direct_ESign.ipa` riêng biệt chỉ đổi 2 địa chỉ URL đã mã hóa trong executable ARM64 của app gốc: URL chính thành `https://www.animevietsub.sale/`, URL dự phòng thành `https://bit.ly/animevietsubtv`. Bản này giữ thiết kế cũ nhưng không bổ sung WKWebView vào DomainResolver/AnimeService, nên **không được coi là sửa triệt để**.
