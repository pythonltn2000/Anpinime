# Anime legacy regression và premium transport — 30/10/2026

Tiếp tục nhánh `repair/source2-live-playback` sau `44cd48a`, bảo vệ nguồn 1/3.
Đã đọc lại báo cáo V3/V4 và Tools/source2-analysis trước khi sửa. App mới:
**2.4.3 (12)**, code commit `7b600ca`.

## Đối chiếu các bản cũ

- `ac6f239` và mã trước `83fed3c`: `AnimeService.detail` tải DOM WebKit khi
  HTML mới có ≤1 tập hoặc danh sách có khoảng khuyết. Đây là đường lấy tập
  được JavaScript bổ sung sau phản hồi ban đầu.
- `83fed3c`: chỉ tải DOM khi danh sách rỗng/truncated **và** trang còn challenge.
  `7feb0e0` bỏ điều kiện challenge nhưng vẫn không đọc lại DOM nếu chỉ có tập 1.
  Vì vậy một preview tập 1 có thể bị coi là danh sách đủ và cache.
- `83fed3c` nhận các URL tập có nhãn số ngay cả khi không có CSS/hash riêng.
  `334d0d7` bỏ nhánh đó để loại tên người dùng trong bình luận. Các bản sau
  không phục hồi trường hợp `/phim/<slug>/tap-N-<id>.html` không có marker.
- Đã kiểm tra artifact playback `12801280889` của build `ef05b3e`, run
  `40654189602`: chỉ có JSON/ảnh MKV và các màn hình player. Không có artifact
  anime hoặc premium live. Kết quả đó không phủ nhận ghi nhận trên điện thoại
  của người dùng; chỉ giới hạn điều có thể xác minh lại từ CI còn lưu.

## Bản sửa anime

Phục hồi link tập legacy do nguồn thật cấp, kiểm tra đúng slug/canonical ID,
nhãn số khớp số trong URL. Không dựng tập bằng số suy đoán. Vẫn bỏ link
bình luận, login, nav/form, phim khác, fragment và query reply/comment; giữ
query server hợp lệ. `watchURL` cũng tìm được link tập đầu từ cấu trúc này.

Phục hồi đọc DOM cho preview chỉ có một tập đánh số. WebKit chờ singleton
trong giới hạn tám giây để API có thể bổ sung danh sách, thay vì chốt sau ba
lần poll ổn định (~2,1 giây). Hủy tác vụ được truyền tiếp và không cache danh
sách một tập sau khi khôi phục DOM thất bại.
Không ép đọc DOM cho một mục Full/OVA không đánh số hoặc danh sách Next.js
đã khai báo đầy đủ. Không đổi ID lịch sử hoặc trình phát của nguồn 1/3.

Thêm phép thử simulator bắt buộc qua pipeline thật:

1. Home → metadata chỉ có link Xem phim.
2. Trang xem ban đầu chỉ có tập 1, dùng anchor legacy không có marker quen.
3. Hủy một lần tải đang chạy và kiểm tra không cache kết quả dở; JavaScript
   của lần tải kế tiếp thêm tập 2 sau 3,5 giây, service phải đọc đủ hai tập.
4. Chọn đúng tập 1 → iframe → media có cookie/Referer → libmpv.
5. Chỉ PASS khi có kích thước video giải mã và thời gian phát tăng. Kiểm tra
   live cũng đọc kích thước/time của video WebKit, nên một sealed/blob player
   hợp lệ không bị đánh trượt chỉ vì không dùng mpv.

Fixture là mẫu tổng hợp tái hiện hai hồi quy, không phải bản sao DOM `.news`.
Các override HTTP loopback chỉ có trong DEBUG/cờ smoke; bản Release vẫn dùng
cấu hình tên miền và luồng HTTPS bình thường. Live `.news` có bước riêng,
không thay bằng website `.dev` hay fixture nếu gặp challenge.

## Phân tích premium mới

Directory đã giải mã/xác thực hiện công bố CDN `svpc.cryboiz.workers.dev`;
app đang bỏ trường `cdn`, trong khi helper ký URL cũ hardcode host khác.
Đã lưu metadata CDN hợp lệ, giữ qua cập nhật thiếu trường và cung cấp accessor
không có host mặc định. Không kích hoạt ký URL hoặc sửa host của media.

Helper `Phim4KVIPResolver` xuất hiện tại `83fed3c`; cùng commit từng in log
HTTP 200/MIME cố định trước khi có bằng chứng media. Các test khi đó chỉ kiểm
tra chuỗi ký, không phải phản hồi app gốc. Không phục hồi helper dựa trên những
log này. `stream_key` và file handle Wakanda là hai trường khác nhau, không có
bằng chứng để dùng thay nhau. Chi tiết ở `Tools/premium-transport-review.md`.

IPA gốc Phim4K 2.8.4/disassembly không còn trong workspace. Hash và offsets
trong báo cáo trước vẫn là bằng chứng thứ cấp, chưa được đối chiếu lại với
binary trong lượt này. Đã hỏi đường dẫn IPA gốc để tiếp tục trace chính xác
request token/ts → JSON url; không dùng một bản IPA khác thay cho bản đã phân tích.

## Kiểm chứng bản mới

Run đầu `41142345897` (`4caa2b6`) đã đi hết pipeline fixture, lấy đủ hai
tập và phát đúng tập 1 bằng mpv: 320×180, time=3,125 giây. Live `.news`
trả lỗi yêu cầu xác minh trình duyệt, không có JSON phát thành công.

Run cuối `41143287070` (`7b600ca`) kiểm tra thêm API tập chậm 3,5 giây,
hủy tải/cache và video WebKit. Đã tải và xem JSON/ảnh artifact cuối `13019987665`:

| Kiểm tra | Kết quả |
| --- | --- |
| Parser/provider/JS/Range | PASS, gồm hồi quy nguồn 1/3 và cấu hình CDN |
| Anime fixture qua service/DOM/player thật | PASS: 2 tập, chọn tập 1, 320×180, time=3,958 giây |
| Hủy tải anime | PASS: `cancelledEpisodeLoadVerified=true`, không cache danh sách dở |
| MKV audio/dual subtitles | PASS, time=3,375 giây |
| HLS qua relay nguồn 2 | PASS, 640×360, time=3,273 giây |
| `.news` live | FAIL trong runner: website yêu cầu xác minh trình duyệt |
| Free1 live | FAIL: segment trả 404 HTML, không có video |
| Wakanda VIP 31937 | FAIL ở resolve: không tìm được hostname CDN gốc |

Run cuối: [41143287070](https://github.com/thuyan1510/AnPinime/actions/runs/41143287070).
Không có `playback-anime-live.json` thành công. Ba bước live thoát mã 1;
workflow vẫn xanh do `continue-on-error`. Điều này không phải bằng chứng
đã sửa live anime, Free1 hoặc premium trên iPhone.

JSON an toàn nằm trong `Tools/evidence/2026-10-30-followup/`; ảnh test pattern
và ảnh lỗi xác minh nằm trong artifact. Playback ZIP SHA-256:
`f1512c5aa7eb81d9bc5755a47a74e68862f4d984c4f78baa99c07042f536d844`.

IPA thử **2.4.3 (12)** từ đúng code `7b600ca`: artifact `13019358301`.
SHA-256 của ZIP artifact:
`bd6b4b869ca083fba33fddec04f95e95b7bd3febb85b8dfc341453a92b269a5f`.
Đây là bản chưa ký, nằm trên nhánh PR #1; `main` chưa được merge.

## Phạm vi bảo vệ

So với `44cd48a`, `MovieProvider`, `MovieCatalog`, `Models`, `FilmMediaRelay`,
`FilmMediaTransform`, `Phim4KProvider`, `Phim4KCatalog` và
`Phim4KVIPResolver` không đổi. MovieSourceDirectory chỉ giữ thêm metadata CDN
nguồn 2; không đổi Core/Free hoặc gửi API key tới CDN. Thay đổi MPV ở lượt này
chỉ mở chẩn đoán DEBUG cho phép thử anime, không đổi codec/track/autoplay.

PlayerView chỉ thêm kích thước video vào thông điệp trạng thái sẵn có và
đưa chúng vào bộ ghi smoke DEBUG. Không đổi loader, license, quảng cáo,
provider routing hoặc hành vi phát nguồn 1/3; các hồi quy JS chạy lại trong CI.
