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

## Kết quả hoàn tất

Kho mới: [pythonltn2000/Anpinime](https://github.com/pythonltn2000/Anpinime).
Giữ nguyên 129 commit ứng dụng; kiểm tra bằng clone/fetch độc lập từ kho đích,
SHA từng nhánh và `git fsck`. Nhánh `main` lịch sử ở `archive/main-before-budget`;
`main` và `feature/ai-drama` dùng bản mới. Remotes trong workspace đã chuyển sang
kho mới, kho trước được giữ ở `previous-origin`.

[Nhập lịch sử](https://github.com/pythonltn2000/Anpinime/actions/runs/41969325461)
đạt bằng Git bridge, phần nhập dữ liệu mất 7,57 giây; toàn job Linux 50 giây.
[Build IPA only](https://github.com/pythonltn2000/Anpinime/actions/runs/41969406418)
đạt, đúng một job macOS 208 giây (3 phút 28 giây). Không chạy Simulator, bộ live
hoặc retry. Source được build: `04c09c4c455517be12eecf0e1d39a604afca3daa`;
cây ứng dụng `3b0ae2c03e928b75cfd1e55afc834dc92db5631a`, giống mã app `21456fb`.
Commit báo cáo sau đó không thay đổi app hoặc workflow đã build.

**[Tải IPA 2.9.2 (21) chưa ký](https://github.com/pythonltn2000/Anpinime/actions/runs/41969406418/artifacts/13389037658)**,
artifact 13389037658, giữ 3 ngày. Đã tải lại artifact, xác minh digest, mở IPA
kiểm tra Info.plist/bundle ID/background audio/framework/executable và đối chiếu
manifest với commit/cây nguồn. SHA-256 IPA:
`847154f6e56b088e501dd571cfed76dd9fa265b9ab2121a63a69435874220754`.

Bản này chứa sửa Home, callback dừng phim ngắn và chuẩn bị PiP native. Điều kiện
xem trên iPhone, đặc biệt tự bật PiP ngay lần Home đầu và các luồng sealed WebKit,
vẫn cần kiểm chứng thực tế; không gọi build thành công là sửa triệt để.
Kết quả/hash/ngân sách nằm trong thư mục bằng chứng cùng báo cáo này.
