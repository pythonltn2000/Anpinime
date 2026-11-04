# AnPinime 2.9.1 (20) — khắc phục hồi quy anime và PiP

Kho hiện tại: `letunam2k/anpinime`, nhánh `feature/ai-drama`,
[PR #1](https://github.com/letunam2k/anpinime/pull/1). Bản 2.9.0 người dùng đã
báo lỗi nghiêm trọng; không dùng Candidate của bản đó làm bản đã xác minh.

- Bỏ suy đoán manifest từ thời lượng video blob. Khi thử player native thất bại,
  quay về đúng video WebKit, vị trí và ý định tạm dừng; không tải lại trang.
  Iframe quảng cáo không được ghi đè trạng thái phát của video chính.
- PiP chỉ chuẩn bị khi app tạm mất hoạt động; giữ owner/layer đến khi hệ thống
  hoàn tất dừng. Phim AI giữ player khi PiP đang bắt đầu hoặc đang phát.
  WebKit nhớ cài đặt PiP kể cả khi trang chưa tạo video.
- Sửa vùng bấm của nút danh sách tập AI để toàn bộ nút nhận thao tác.

[Kiểm tra iOS tại b208461](https://github.com/letunam2k/anpinime/actions/runs/41798383187):
anime fixture, lỗi native HTTP 403 → phục hồi cùng WebKit, hết loading, MKV,
PiP phần mềm, cache 5/10 video, lướt/toàn màn hình AI và tạm mất hoạt động đều đạt.
Chưa phát hành IPA đã qua toàn bộ kiểm tra: bảng tập và kiểm tra chuyển thư viện
AI cần chạy lại với sửa đổi tiếp theo. Anime live còn bị xác minh trình duyệt;
Free1 trả segment HTTP 404. Chưa xác nhận cửa sổ PiP hệ thống trên iPhone thật.

Chi tiết nguyên nhân và giới hạn: [PLAYER_REGRESSION_REPAIR.md](PLAYER_REGRESSION_REPAIR.md).

Lượt [2aa3e39](https://github.com/letunam2k/anpinime/actions/runs/41802881152)
đã qua toàn bộ job native và kiểm tra bảng trọn bộ 40 tập AI. Tiếp tục sửa dọn
lớp hiệu ứng khi hủy chuyển thư viện, đồng thời phân biệt thao tác vuốt chưa
chuyển tập với lỗi phát video trong kiểm tra live. Chưa giao Candidate khi
kiểm tra chuyển thư viện/live chưa đạt.

---

## Lịch sử bản 2.9.0 (19) — sửa player và bộ đệm Phim AI

**Đã sửa mã, chưa có IPA 2.9 đã kiểm chứng.** Mã ứng dụng:
[`6c6f548`](https://github.com/thuyan1510/AnPinime/commit/6c6f548f30b26a5432a72ae3a1811fc2afcaebee),
nhánh `feature/ai-drama`, [PR #2](https://github.com/thuyan1510/AnPinime/pull/2) còn draft.

- Anime vẫn có WebView dự phòng khi chưa lấy được URL phát trực tiếp. Sửa trạng
  thái loading/buffering theo tiến độ video; giữ pause của người dùng. Ẩn popup
  và hai nút quảng cáo kể cả khi nằm chung wrapper với phụ đề. Bổ sung nhận diện
  manifest VOD khớp thời lượng của video blob để chuyển sang player native;
  giữ decoder web khi nguồn yêu cầu sealed loader.
- Phim AI tải trước **5 hoặc 10 file video**, tối đa hai lượt tải đồng thời,
  ưu tiên video đang xem. Giữ ba video vừa qua để lướt xuống quay lại đúng phim;
  lướt lên tiếp tục danh sách hiện có. Vẫn chỉ chuẩn bị một decoder kế tiếp.
  Cache tạm tối đa 256 MiB, mỗi clip tối đa 24 MiB; file quá lớn/tải lỗi dùng
  luồng mạng. Đây là chính sách nạp trước, không bảo đảm mọi video live có thể
  phát ngay bất kể tốc độ mạng và kích thước.
- Sửa nút thu nhỏ bằng cách đóng controller UIKit trực tiếp. Ảnh chờ phủ kín
  vùng phát. Nút tập, tốc độ và toàn màn hình đặt cạnh nhau; danh sách tập chia
  nhóm 24 tập, sáu cột, mở đúng tập từ feed.
- Cài đặt player dùng kính mờ; trên iOS 26 dùng Liquid Glass. Bảng nằm ngang
  rộng nửa màn hình; Phim AI dọc mở sheet nửa màn hình. Bổ sung cài đặt khi
  xem Phim ngắn.
- PiP native giữ frame thật sẵn sàng trong foreground và gửi yêu cầu từ
  `willResignActive`; WebView có lệnh PiP riêng, kiểm tra API hỗ trợ và giữ
  ý định tạm dừng. **Chưa xác nhận PiP mở ngay lần đầu trên iPhone hoặc đủ tất
  cả nguồn.** Không thay đổi đường an toàn khôi phục GPU của bản trước.

**Kiểm tra cục bộ PASS:** 7 nhóm JavaScript của player, 143 assertion provider
PineDrama và 18 assertion cache trên Swift/Linux. Máy chủ fixture xác nhận đủ
10 lượt tải hoàn chỉnh; kiểm tra lướt ngược, hủy, dọn bộ nhớ, loại file HTML và
file chỉ tải một phần. Parse cú pháp toàn bộ Swift ứng dụng và XCTest, typecheck
Foundation models/cache, kiểm tra Python/shell và diff đều qua. Parse cú pháp
không thay thế biên dịch UIKit hay chạy app iOS.

**GitHub chặn job trước bước đầu tiên:**
[run 41761873633](https://github.com/thuyan1510/AnPinime/actions/runs/41761873633)
báo thanh toán gần đây thất bại hoặc cần tăng spending limit trong Billing & plans.
Lượt này chạy trên commit `2d28879`; mã cuối `6c6f548` chưa chạy iOS. Không có
log biên dịch, XCTest iOS hay IPA mới. Cần gỡ chặn tài khoản rồi chạy lại workflow
đầy đủ để kiểm tra anime live, MKV/HLS, fullscreen và PiP; chưa có số đo cải thiện
startup live cho tất cả nguồn.

[Bằng chứng của lượt này](Tools/evidence/2026-11-04-player-followup/README.md) ·
[Bảo vệ nguồn 1/3](Tools/evidence/2026-11-04-player-followup/source-preservation.json).
Provider/catalog/transport được bảo vệ và cấu hình mpv thông thường giữ nguyên;
thay đổi shared player ở trên nằm trong yêu cầu mới của người dùng.

---

## Lịch sử bản 2.8.0 (18) — Home, lướt Phim ngắn, toàn màn hình và PiP

**Bản giao đã xác minh:** [IPA unsigned 2.8.0 (18)](https://github.com/thuyan1510/AnPinime/actions/runs/41600837879/artifacts/13215081382).
[Run 41600837879](https://github.com/thuyan1510/AnPinime/actions/runs/41600837879),
mã ứng dụng `30d304ea4d478cf1fdd85e37ac7eb003135f1bc6`, cây nguồn ứng dụng
`524c59a7592c08b2124e16ecfdddeec2fcba5689`.
Nhánh `feature/ai-drama`, [PR #2](https://github.com/thuyan1510/AnPinime/pull/2),
tiếp nối sửa nguồn 2 tại `a785d35`; chưa gộp vào main.

IPA được mở kiểm tra: **2.8.0 (18)**, `com.xemphim.aipinime`, iOS 15+,
có background audio, không có chữ ký/provisioning profile. SHA-256:
`814286b4a9cc3984a81ffe4808f0ec366615af5d9bdd8934fb2d85668e006871`.
[Danh tính artifact](Tools/evidence/2026-11-03-feed-polish/release-artifact.json).

## Thay đổi

- Bỏ lớp nền tối riêng phía sau thanh nút Home. Banner ưu tiên ảnh nguồn cung cấp
  và ảnh từ metadata của phim đang hiển thị; giữ ảnh cũ nếu ảnh mới kém nét hơn.
  Không đoán URL ảnh lớn và không sửa parser/luồng dữ liệu nguồn 1/3.
- Phim ngắn cuộn bằng UIScrollView native, nội dung đi theo ngón tay. Chuẩn bị tối
  đa một video kế tiếp, tạm dừng/tắt tiếng, bộ đệm 3 giây/12 MiB. Khi chuyển sang
  video đó, dùng player đã chuẩn bị. Dọn khi rời tab, xuống nền, có cảnh báo bộ nhớ
  hoặc hết 45 giây; không ghi video chưa xem vào lịch sử.
- Chỉ clip ngang có nút toàn màn hình. Màn phát UIKit riêng che thanh tab và các
  nút thư viện. Khi đổi dọc/ngang, tạo bề mặt Metal mới và khôi phục tập/vị trí xem.
  Dùng link còn mới trong bộ nhớ; link cũ được resolve lại. Dừng/tắt tiếng owner cũ
  trước khi lắp owner mới. Video dọc giữ nguyên hướng.
- PiP chuẩn bị AVKit content source trong foreground bằng frame thật, qua lệnh
  bất đồng bộ và `screenshot-sw=yes`. Chuẩn bị frame phần mềm trước khi xuống nền,
  yêu cầu mở PiP khi thật sự vào background, khôi phục GPU khi trở lại. Tránh đọc
  ảnh trực tiếp từ GPU vì đường đó làm crash Metal Simulator.
- IPA chính thức chỉ được xuất sau khi cả kiểm tra native và Phim AI, gồm phát
  live PineDrama, đều thành công. Bản build đơn thuần được đặt tên Candidate.

## Kiểm chứng của bản giao

**6 XCTest PASS, 0 lỗi, 1 SKIP.** Native fixture kiểm tra phân trang/lọc, cuộn,
chuẩn bị video kế tiếp với API cố tình chậm 4 giây, mở trọn bộ 40 tập, hủy phản hồi
trễ, lịch sử, pause/background và vùng bấm ảnh/tên phim. Kiểm tra fullscreen đọc
ảnh **toàn màn hình hệ thống**, yêu cầu vùng giữa có hình video >80%, đồng thời
kiểm tra kích thước, thanh tab, thoát về dọc và tiếp tục phát. Ảnh cửa sổ app có thể
bị cắt sai tọa độ khi ép xoay; không dùng nó làm bằng chứng duy nhất.

Hai XCTest live PineDrama đều PASS: catalog/danh sách tập và video đầu/giữa/cuối;
feed Phim ngắn, fullscreen, mở đúng tập và danh sách đầy đủ.
MKV native phát đến 9 giây, có 2 audio/2 subtitle; PiP tạo 8 frame phần mềm,
pause/seek/khôi phục GPU thành công. HLS qua relay và anime dynamic-episode fixture
đều phát tăng thời gian. Gateway dùng metadata Core đã chụp phát 1920×1080 tới
15,974 giây; không coi đó là chứng minh Core fresh-live.

**PiP tự mở trên iPhone vật lý chưa được xác nhận.** Simulator báo AVKit system PiP
không được hỗ trợ nên riêng XCTest này SKIP; kiểm tra frame phần mềm PASS không
thay thế cho hành vi cửa sổ hệ thống trên điện thoại. Không có JSON pass fresh-live
cho Anime/Free1/Core ở lượt này; các giới hạn cũ vẫn được giữ rõ.

[Bằng chứng và kết quả](Tools/evidence/2026-11-03-feed-polish/README.md) ·
[Kết quả đúng run](Tools/evidence/2026-11-03-feed-polish/run-41600837879-final.json) ·
[Bảo vệ nguồn 1/3 và cấu hình mpv](Tools/evidence/2026-11-03-feed-polish/source-preservation.json).

---

## Lịch sử bản 2.7.0 (17)

**Bản giao:** [IPA unsigned, artifact 13199392297](https://github.com/thuyan1510/AnPinime/actions/runs/41565698005/artifacts/13199392297).
Mã ứng dụng `e6ee6dc02624ae27e4cce38011a9c1fa26fcb570`,
[run 41565698005](https://github.com/thuyan1510/AnPinime/actions/runs/41565698005).
Nhánh `feature/ai-drama`, [PR #2](https://github.com/thuyan1510/AnPinime/pull/2),
tiếp nối nhánh sửa nguồn 2 tại `a785d35`; chưa gộp vào main.

IPA đã được mở để kiểm tra `Info.plist`: **2.7.0 (17)**,
`com.xemphim.aipinime`, iOS tối thiểu 15.0, có background audio, không có
provisioning profile/chữ ký app. SHA-256:
`0b80b998655f8f769c9a2c3f4a3041e9cddce825e1fa93c947fcb4ff60635fac`.
[Danh tính artifact](Tools/evidence/2026-11-03-short-feed/release-artifact.json).

## Giao diện

Ba thư viện ngang hàng là **Anime / Phim / Phim AI**. Phim AI có bốn tab:
**Trang chủ / Phim ngắn / Khám phá / Cài đặt**. Ba mục **Thịnh hành / Danh mục /
Mới** nằm trong Khám phá; giữ dữ liệu thật, bốn hàng lọc và tải tiếp native.

**Phim ngắn** dùng feed riêng của PineDrama, không lấy lại bảng xếp hạng.
Lướt dọc chuyển video; video ngang nằm vừa trong màn hình dọc. Nút toàn màn
hình xoay ngang cùng player và giữ tiến độ. Chỉ giữ tên phim, tập, phát/tạm
dừng, toàn màn hình và **Phát tất cả**. Không thêm tim, bình luận, chia sẻ.

**Phát tất cả** lấy panel của đúng collection, kiểm tra đầy đủ rồi mở đúng
tập đang xem. Dừng preview trước khi player danh sách nhận quyền phát. Feed
tải tiếp theo ID video đã nhận, loại trùng và dừng nếu không còn ID mới.
URL video được lấy mới theo tập, không lưu vào lịch sử.

Một bộ nhận cử chỉ chung xử lý vuốt trên cả video và vùng phủ; UIKit thực
hiện hoạt ảnh chuyển trang. Cách này giữ nút bấm hoạt động và tránh tranh
chấp giữa vùng phủ/scroll recognizer. Các phản hồi trễ không được lắp player
cho tập đã bỏ qua. Chỉ tập hiện tại sở hữu player đang phát.

Banner Home kéo tới đỉnh sau nút đổi thư viện/nguồn đặt chồng lên ảnh. Đã bỏ
nút tải lại trên Home. Toàn bộ thẻ/kết quả gồm ảnh, tên và vùng trống mở đúng
phim. Anime vẫn có Lịch chiếu; thư viện Phim giữ các tab riêng của nó.

## Cài đặt phát và PiP

IPA Phim4K gốc có sáu nhóm **Âm thanh / Phụ đề / Hiển thị / Tốc độ / Chung /
Thông tin**. Menu mới dùng hàng tab ngang, vùng tùy chọn cuộn và hàng chọn
track lớn. Hiển thị có tỷ lệ video, lấp đầy khung hình và kiểu phụ đề. Menu
cũng có trong player AI; lựa chọn audio/subtitle/file rời nối tới ID track
thật. AI ghi nhớ tốc độ và dùng tùy chọn tự chuyển tập của người dùng.

PiP native dùng AVSampleBufferDisplayLayer cùng decoder/âm thanh mpv. Chỉ
PiP chuyển sang khung render CPU nhỏ; phát thường giữ Metal và các tùy chọn
cache/hardware decoding cũ. Khi trở về, GPU nhận output trước khi giải phóng
render context PiP. Có nút cửa sổ nổi, tùy chọn PiP khi rời app và background
audio. AVPlayer/WKWebView bật khả năng PiP của hệ thống; web player còn phụ
thuộc trang phát.

**Chưa xác nhận cửa sổ PiP tự bật trên iPhone vật lý.** Kiểm tra simulator
bên dưới xác nhận frame/pause/seek/restore; không thay cho hành vi hệ thống
trên điện thoại hoặc chứng nhận mọi web player hỗ trợ PiP.

Nguồn 2 hiển thị `S01E001` thành **Tập 1** bằng thuộc tính trình bày riêng.
Tên tập gốc, công thức ID lịch sử và ID lookup mùa/tập giữ nguyên. Catalog
nguồn 2 trở lại byte-identical với baseline; không sửa dữ liệu để đổi nhãn.

## Kết quả của đúng bản giao

Bốn XCTest fixture và hai XCTest live đều **PASS** trong run `41565698005`:

| Kiểm tra | Thời gian |
| --- | ---: |
| Khám phá, phân trang, bốn bộ lọc, đổi thư viện | 101.680 giây |
| Phim ngắn: phát ngang/dọc, vuốt, tải tiếp, Phát tất cả, dọn player | 24.635 giây |
| Player tập, chọn phụ đề thật, hủy tập trễ, pause/background, history | 62.045 giây |
| Bấm các phần của hàng tìm kiếm chọn đúng phim | 12.791 giây |
| Live catalog → panel đầy đủ → đúng tập đầu/hai/cuối | 53.247 giây |
| Live feed → xoay cùng video → panel đầy đủ → phát tập cuối | 50.791 giây |

JSON playback native của cùng run xác nhận:

- MKV tự phát, hai audio và hai làn phụ đề; **13 frame PiP hợp lệ**, pause,
  seek và restore GPU thành công, playback tiếp tục tới **9.958 giây**.
- HLS nguồn 2 qua relay: giải mã **640×360**, thời gian tiến tới **3.440 giây**.
- Anime fixture qua danh sách tập động/resolver: **320×180**, **3.583 giây**.
- Gateway nguồn 2 dùng metadata Core đã lưu: **1920×1080**, **15.641 giây**;
  đây không phải xác nhận fresh Core catalog.

CLI parser/provider/protocol/JS và AI provider/store cũng đạt. Bài kiểm tra
ID nguồn 2 xác nhận nhãn mới giữ nguyên persistence key và lookup IDs. Thứ
tự phản hồi chậm đối chiếu bằng **đúng episode ID**, không lẫn hai bộ có
cùng số tập trong các bài kiểm tra dùng chung fixture.

[Kết quả từng phép thử và hash JSON](Tools/evidence/2026-11-03-short-feed/run-41565698005-final.json).
[Bằng chứng feed gốc và phạm vi bảo vệ](Tools/evidence/2026-11-03-short-feed/README.md).
Các snapshot `partial`/baseline giữ lịch sử điều tra; không dùng IPA cũ làm
bản giao. Không suy ra playback chỉ từ trạng thái workflow/build xanh.

## Phạm vi bảo vệ và phần chưa xác nhận

Ba nhãn Movie là **Anpinime Free / Anpinime Premium / Anpinime dự phòng**.
Raw source cases, URL/ID lịch sử và routing nguồn 1/3 không đổi. Hash của
parser, catalog, provider, relay và cấu hình mpv thường được so với baseline.
Player/menu/banner chung thay đổi theo yêu cầu này.

Các kiểm tra live **AnimeVietsub, Free1 và fresh Core** trong run này chưa
phát thành công; ghi riêng trong kết quả, dù các bước optional không chặn
IPA. Gateway có metadata lưu phát được không chứng minh fresh Core đã sửa.
Các bộ có tổng catalog khác panel vẫn báo chưa đủ danh sách, ví dụ mẫu cũ
45 tập nhưng panel chỉ 41; không tự nhận đó là trọn bộ.

Chưa kết luận đã sửa hết tốc độ/lag MKV trên iPhone. Các tối ưu directory
cache/probe giới hạn từ 2.6 được giữ, không cache URL video có thời hạn và
không tráo server. Mẫu Người Nhện có đoạn mở đầu đen; đo Linux hoặc gateway
không thay cho startup fresh Core trên máy người dùng.
[Phân tích startup nguồn 2](Tools/source2-startup-analysis.md),
[kết quả iOS trước đó](Tools/evidence/2026-11-02-source2-startup/ios-startup-results.json).
