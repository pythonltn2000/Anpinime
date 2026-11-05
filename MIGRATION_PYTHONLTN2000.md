# Chuyển kho và giới hạn Actions — 05/11/2026

Đích được người dùng chọn: `pythonltn2000/Anpinime`. Giữ nguyên mã sửa Home,
phim ngắn và PiP ở `21456fb`; không đổi provider/parser/transport nguồn 1/3.
Ứng dụng 2.9.2 (21). Giữ lịch sử Git, đưa nhánh chính tới mã mới có workflow
thủ công; nhánh main lịch sử được lưu dưới tên archive để tránh trigger cũ.

Mỗi lần xuất IPA chỉ chạy **Build IPA only**: một job macOS tối đa 20 phút,
không Simulator, ffmpeg hoặc live test, không tự chạy khi push và không tự retry.
Artifact chỉ giữ 3 ngày, gồm gói IPA, checksum và manifest định danh. Không bật
Codemagic hoặc bất kỳ dịch vụ tính phí nào trong lần chuyển này.

Nhập lịch sử, nếu cần, dùng một job Linux riêng có thời gian giới hạn. Job nhập
không chạy kiểm thử iOS và không tự dispatch workflow đầy đủ. Kho mới giữ đúng
visibility mà người dùng tạo; không thay đổi thanh toán hoặc hạn mức tài khoản.

## Mã sửa và kiểm tra

- Home tải catalog trực tiếp, cache thẻ có hạn dùng và đúng cấu hình, parser
  ngoài main actor; browser xác minh được tạo lazy, giữ cùng phiên khi cần.
- Native PiP chỉ nhận điều khiển từ controller đang active; chuẩn bị renderer
  sớm, giữ GPU inline và cùng decoder cho tới lúc chuyển PiP thực sự.
- Sửa harness phim ngắn: vùng chạm DEBUG, thống kê theo testcase, mẫu thời gian
  trước/sau; không hạ điều kiện phát liên tục để làm xanh kiểm tra.
- Local Linux: Home 26, JavaScript 7 nhóm, provider AI, cache media thực 18 kiểm
  tra/server đủ 10 file, Range probe và nguồn giả lập 12 GB đạt. Swift parse và
  shell syntax đạt; bảy file nguồn 1/3 được bảo vệ trùng baseline. Chi tiết ở
  [local-checks.json](Tools/evidence/2026-11-05-account-migration/local-checks.json).

Linux hiện tại không có Xcode/UIKit/Simulator. Không báo đã chạy lại UI iOS của
harness mới hoặc xác minh PiP tự bật trên iPhone thật. Luồng sealed WebKit vẫn
có giới hạn tự động PiP. Bằng chứng native trước đó ở `7be7706` đạt các kiểm
tra bắt buộc; các FAIL AI trước đó vẫn được ghi nhận trong
[báo cáo sửa lỗi](HOME_SHORTS_PIP_REPAIR.md). IPA mới là bản để kiểm tra tiếp trên
iPhone, không phải bằng chứng những giới hạn này đã biến mất.
