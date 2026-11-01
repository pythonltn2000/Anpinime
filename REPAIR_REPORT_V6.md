# Phim4K gốc → nguồn 2 — 01/11/2026

Tiếp tục nhánh `repair/source2-live-playback`, sau báo cáo V5; đã đọc
`REPAIR_REPORT_V3.md` và `Tools/source2-analysis.md` trước khi sửa. App thử:
**2.4.4 (13)**. PR #1 vẫn là draft, chưa merge `main`.

## IPA người dùng cung cấp

Đã tải đúng file Google Drive người dùng gửi, giữ nguyên bản gốc để đối chiếu.
Bundle `ios.phim4k.xyz`, Phim4K **2.8.4 (65)**, kích thước 26.503.200 byte.
SHA-256 IPA:
`fd0ef22c4f12e39ed35e335c22eb8dbf6edeb7c1d8be466be690aae6d316aed5`.
SHA-256 `App.framework/App`:
`070b6e44ffa8ca863ae60191179188db8cb3397ae3570c1757cd7a114da5af75`.

Hash ZIP khác bản ghi ở V3; không tuyên bố hai package giống nhau. Đã phân tích
tĩnh Dart AOT/arm64, đối chiếu object pool và lệnh máy bằng Blutter/Capstone;
không cài, thực thi hoặc sửa app gốc. Chi tiết offset và thuật toán nằm trong
[Tools/phim4k-original-protocol.md](Tools/phim4k-original-protocol.md).

## Lỗi premium và cách sửa

Helper cũ có seed sai, gateway hardcode và có thể trả URL gateway để player
phát khi chưa đổi được sang media. Mã mới tái hiện luồng quan sát trong IPA:

1. Giữ nguyên đúng `video_file_id` đã chọn, tải lại detail trước khi resolve.
2. Với Core virtual CDN, lấy **file handle cuối đường dẫn**; không thay bằng
   server ID, `stream_key`, nhãn chất lượng hoặc server khác.
3. Dùng `cdn` từ directory đã xác thực AES-GCM, không tự sửa hostname media.
4. Tái hiện seed từ hai mảng XOR của IPA, dẫn xuất khóa theo ngày UTC bằng
   AES-GCM; ký token HMAC và timestamp mask theo đúng byte order gốc.
5. GET gateway bằng Dart UA, chỉ chấp nhận HTTP 200 JSON có `url` hợp lệ.
   Mọi lỗi dừng ở resolver; không đưa URL gateway cho player.
6. Phát **URL media thực được trả về**, giữ nguyên scheme/query. Gateway HTTPS
   hiện trả media HTTP hợp lệ; ép sang HTTPS sẽ làm khác hành vi app gốc.
7. Media native nguồn 2 dùng riêng `User-Agent: oxoo`, không nhận API key,
   Basic header, Origin/Referer hoặc cookie từ catalog. Luồng trang nhúng vẫn
   giữ xử lý WebKit/cookie của nó bằng cờ `isWeb` rõ ràng.

Free1/Free2 có ngữ cảnh nguồn riêng, bỏ qua signer kể cả khi URL có dạng giống
virtual CDN. Không thay Core lỗi bằng Free, không thay tập/server người dùng
đã chọn. Core/gateway có session và redirect policy riêng; credential chỉ được
gửi tới đúng origin API, media redirect lọc header và giới hạn số lần chuyển.

Request Core cũng đã khớp header client quan sát trong IPA: Dart UA, `API-KEY`
và Basic từ cấu hình API `tokens` hoặc cặp mặc định được ship trong app gốc.
Đây là cấu hình client API, không phải phiên đăng nhập tài khoản. Hỗ trợ key
thường, map/JSON-map và alias gốc; cập nhật directory thiếu/sai không xóa cấu
hình hợp lệ. Bộ kiểm thử xác nhận các header này không tới Free/gateway/media.

## Bằng chứng media thật

Ngày 31/10, đã đọc đúng năm server Wakanda `10403`, mỗi file chỉ lấy prefix
2 KB: **31937, 33090, 27463, 31938, 31939** đều gateway 200 JSON → media 206,
prefix MKV. File lớn nhất khai báo 57.170.889.679 byte; không tải cả file.
Server `27463` có `stream_key=null` vẫn đổi link thành công.

Ngày 01/11, làm mới URL đúng server **31937**, giải mã bằng FFmpeg được
**72 khung hình H.264, 1920×1080, 3,003 giây**, exit 0, không lỗi HTTP và không
lưu video. Giới hạn: output 3 giây, probe 2 MB, phân tích 3 giây, network timeout
10 giây, process timeout 35 giây. Đây là bằng chứng giải mã Linux; chưa tự nó
chứng minh player iOS hiển thị được hình hoặc chuyển audio/phụ đề VIP.

Metadata an toàn: [Tools/evidence/2026-11-01-original4k/](Tools/evidence/2026-11-01-original4k/).
Không commit IPA, decompile, seed thô, URL ký đầy đủ, response gateway riêng tư
hoặc thông tin phiên tài khoản.

## Kiểm thử app

Run đầy đủ [41259259589](https://github.com/thuyan1510/AnPinime/actions/runs/41259259589),
code **`1cf796c`**, đã hoàn tất. Đã tải artifact, kiểm tra checksum và đọc JSON/ảnh:

| Phép thử | Kết quả thực |
| --- | --- |
| Parser/crypto/provider/JS/Range | PASS, gồm cấu hình Core, năm server, lỗi gateway và cách ly credential |
| MKV hai audio/hai phụ đề | PASS, autoplay, time 2,167 giây |
| HLS qua relay nguồn 2 | PASS, 640×360, time 4,106 giây |
| Anime fixture: DOM chậm/hủy tải/chọn tập | PASS, đủ 2 tập, chọn tập 1, 320×180, time 3,042 giây |
| Anime `.news` live | FAIL: yêu cầu xác minh trình duyệt; không có JSON phát thành công |
| Free1 live | FAIL: manifest 200, segment 404 HTML; video time/kích thước bằng 0 |
| Core Wakanda 31937 live đầy đủ | FAIL: HTTP 403 ở bước catalog-detail, trước gateway |
| Gateway/media live với metadata Core lưu | PASS: mpv, 1920×1080 H.264/AC-3, time 3,420 giây; ảnh sớm là đoạn nền đen có phụ đề |

Đã kiểm tra thêm run
[41260161453](https://github.com/thuyan1510/AnPinime/actions/runs/41260161453),
head `230168a`: **16,808 giây, 1920×1080**, ảnh có khung hình phim và phụ đề Việt
rõ ràng. Gateway/media thật và player iOS đã có bằng chứng giải mã/hiển thị;
Core metadata trong phép thử này vẫn là bản lưu, không phải API live thành công.
Ảnh cho thấy một thời điểm có vòng chờ; đây là phép thử ngắn, chưa chứng minh
phát ổn định cả phim. Run bổ sung chỉ đổi test/workflow; cây mã `AnyAnime/`
trùng code `1cf796c` của IPA đã kiểm chứng.

Ba script anime/Free1/Core live thoát mã 1, nhưng workflow và API step conclusion
vẫn báo success do `continue-on-error`. Không dùng trạng thái đó để tuyên bố đã
sửa live. JSON gateway nhận diện hai lựa chọn audio và ba lựa chọn subtitle
(gồm tắt); chưa kiểm chứng chuyển audio/hai phụ đề trên chính phim VIP.

Có hai phép thử premium độc lập: `phim4k-vip` đi qua Core live đầy đủ;
`phim4k-gateway` phát lại riêng metadata Core của đúng phim `10403`/server
`31937`, sau đó lấy directory/gateway/media **thật** bằng resolver production
và player native. Phép thử thứ hai lấy gateway mới vào namespace directory
trống, không dùng host hoặc URL ký được hardcode. Nó chỉ giúp tách lỗi API
Core khỏi resolver/player và luôn ghi `coreMetadataReplayed=true`; không được
dùng để tuyên bố Core live đã hoạt động đầy đủ.

IPA chưa ký **2.4.4 (13)**:
[artifact 13064343562](https://github.com/thuyan1510/AnPinime/actions/runs/41259259589/artifacts/13064343562).
SHA-256 ZIP artifact:
`48ce69d55f482be6dee3d145f573d7d6308fad6ea889481e0b57fd0bf605dba1`.
SHA-256 file IPA bên trong:
`945c0b75e3db41481235f3c59ab1317b25609452b700641e44aa6b6c96aa1bab`.

[Playback artifact 13064617518](https://github.com/thuyan1510/AnPinime/actions/runs/41259259589/artifacts/13064617518),
ZIP SHA-256:
`aa7aaa00c54a1d4c854b16322a5d79558a177ae16a854c4da97fddc9752803f0`.

[Ảnh/JSON sau 15 giây — artifact 13064543658](https://github.com/thuyan1510/AnPinime/actions/runs/41260161453/artifacts/13064543658),
ZIP SHA-256:
`ad52852f80186ea63cb5e2a8b540c704cf15d7c8c635440d749ec19dd63cce9f`.
Manifest kết quả: [verification-summary.json](Tools/evidence/2026-11-01-original4k/verification-summary.json).

## Anime, Free1 và phạm vi bảo vệ

Giữ bản sửa V5 cho link tập legacy, DOM thêm tập chậm và hủy tải/cache dở.
Không đổi domain, parser, API catalog hoặc resolver của nguồn 1/3 trong lượt
Phim4K này. Các thay đổi shared player/relay đều có điều kiện nguồn 2, giữ
default cookie/header cũ cho nguồn khác; hồi quy provider/JS và MKV audio/hai
phụ đề chạy lại trong CI. Anime live và Free1 live cần được ghi kết quả riêng,
không suy từ premium hoặc fixture thành công.

Đối chiếu hash từ `8acf5c0`: `MovieCatalog`, `MovieBrowseCatalog`, `Models` và
`FilmMediaTransform` giữ nguyên byte; MPV controller chỉ thêm chẩn đoán DEBUG.
Chi tiết: [source1-3-unchanged-files.json](Tools/evidence/2026-11-01-original4k/source1-3-unchanged-files.json).
