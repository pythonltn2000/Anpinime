# Build tiết kiệm

Workflow mặc định để xuất IPA là **Build IPA only** (`build-ipa-light.yml`),
chạy thủ công trên đúng nhánh mã cần build. Chỉ một job macOS, không Simulator,
không ffmpeg, không kiểm tra live; giới hạn 20 phút và giữ artifact 3 ngày.
Không tự chạy khi push. Build mới cùng nhánh hủy lượt build nhẹ cũ đang chạy.
XcodeGen được dùng lại nếu runner đã có; tắt cập nhật Homebrew tự động. Không
lưu cache DerivedData hoặc artifact Simulator lớn. Chỉ tải IPA, checksum và
manifest ghi commit/cây ứng dụng/phiên bản/bundle ID. Manifest xác nhận đúng gói
được build, đồng thời ghi rõ playback và PiP máy thật chưa được workflow kiểm tra.

Workflow cũ được đổi tên **Full playback verification (manual)** và bỏ trigger
push. Chỉ chạy kiểm tra iOS đầy đủ khi người dùng yêu cầu rõ. Không tự retry
build hoặc tự chuyển sang pipeline đầy đủ.

Kiểm tra JavaScript, Home/cache, parser và network fixture phù hợp được chạy
trong workspace Linux trước khi gửi build. Những bộ Swift phụ thuộc CryptoKit,
Combine/SwiftUI hoặc UIKit có thể cần macOS; ghi rõ phần chưa chạy, không thay
thế bằng kết quả giả. Simulator, giải mã/render iOS và cửa sổ PiP hệ thống
không chạy được trên workspace Linux hiện tại. Kiểm chứng còn lại thực hiện
trên iPhone của người dùng hoặc một lượt macOS được yêu cầu riêng.

IPA build thành công chỉ xác nhận biên dịch và đóng gói, không chứng minh mọi
nguồn phát hoặc PiP đã được sửa. Codemagic cũng có hạn mức riêng; không tự chạy
dịch vụ đó để thay thế việc kiểm tra đắt tiền.

## Khi chuyển kho

Tạo nhánh mặc định của kho mới trực tiếp ở commit đã có hai workflow thủ công.
Không tạo `main` ở một commit lịch sử còn trigger `push` rồi mới cập nhật sau,
vì thao tác tạo nhánh đó có thể khởi chạy pipeline cũ.

Lịch sử Git và những nhánh sửa lỗi cũ có thể giữ lại. Riêng nhánh helper cũ
`migration/bootstrap-20261104` từng theo dõi thay đổi file request rồi dispatch
bộ kiểm tra đầy đủ; nếu giữ nhánh này, đổi tên thành
`archive/migration/bootstrap-20261104`. Không nhập nó dưới tên hoạt động cũ,
không gửi request vào helper cũ, không dùng workflow đó để build IPA nhẹ.

Trước lần build đầu, kiểm tra danh sách workflow của nhánh mặc định chỉ có hai
workflow thủ công; chọn **Build IPA only**. Một lần build được người dùng yêu
cầu là một lượt macOS tối đa 20 phút. Nếu thất bại, đọc log và kiểm tra lại trong
workspace trước khi quyết định lượt tiếp theo; không tự chạy lại toàn bộ suite.
