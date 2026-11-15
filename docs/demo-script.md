# Kịch bản demo: Kết nối AWS CloudWatch với Xora Resolve

- **Người xem:** khách hàng hoặc người dùng mới chưa biết Xora Resolve
- **Thời lượng:** khoảng 1 phút 25 giây (bản rút gọn khoảng 45 giây ở cuối)
- **Thông điệp chính:** kết nối chỉ cần quyền đọc, và luồng chính là *alert → điều tra → RCA → khuyến nghị → người duyệt*.

## Chuẩn bị trước khi quay

- **Cho lab về trạng thái bình thường:** chạy `.\scripts\chaos.ps1 -Scenario stop` và đợi cả 6 alarm về OK.
- **Tạo sẵn một incident đã có RCA:** từ lúc gây lỗi tới lúc alarm bắn mất khoảng 2–3 phút, rồi Xora cần thêm khoảng 1 phút để điều tra. Chạy `.\scripts\chaos.ps1 -Scenario service-down` trước khi quay khoảng 5 phút. Khi quay, chỉ quay cảnh gõ lệnh rồi cắt sang incident đã có kết quả.
- **Mở sẵn các tab theo thứ tự:** trang tổng quan Xora → form connector CloudWatch_Demo → AWS SNS Subscriptions → incident rule → terminal → chi tiết alert → chi tiết incident (RCA).
- **Che (blur) External ID, ingest credential và AWS Account ID.**
- **Banner "missing data from Grafana":** che đi, hoặc nói một câu rằng connector Grafana chưa được cấu hình.

## Kịch bản

| Thời gian | Màn hình | Lời thoại |
|---|---|---|
| **0:00–0:08** | Trang tổng quan Xora Resolve | "Xora Resolve nhận alert từ hệ thống monitoring bạn đang dùng, như CloudWatch, tự điều tra và đề xuất nguyên nhân gốc để người phụ trách duyệt. Xora Resolve không thay thế công cụ monitoring." |
| **0:08–0:24** | Form connector: Region, SNS Topic, tab **Assume role** (External ID, Gateway principal, Role ARN) | "Bước một là kết nối. Xora cấp External ID và trust policy. Trong tài khoản AWS, ta tạo một IAM role chỉ có quyền đọc alarm, metric và log, rồi dán Role ARN, region và SNS topic vào đây. Xora không có quyền thay đổi tài nguyên của bạn." |
| **0:24–0:32** | AWS Console, SNS → Subscriptions, trạng thái **Confirmed** | "Alarm CloudWatch gửi qua SNS về Xora. Subscription chuyển sang Confirmed nghĩa là đường truyền đã thông." |
| **0:32–0:42** | Incident rule: Provider = CLOUDWATCH, Service = `xora-test-app`, Group by `service`, 20 phút | "Bước hai là incident rule: quy định alert nào sẽ mở incident. Ở đây là alert CloudWatch của service xora-test-app, gom theo service trong 20 phút." |
| **0:42–0:50** | Terminal: `.\chaos.ps1 -Scenario service-down` → **cắt** | "Giờ ta gây sự cố thật: dừng ứng dụng demo-app." |
| **0:50–0:58** | Chi tiết alert: Service, Environment, Provider, Labels | "Alarm bắn và alert về Xora kèm đầy đủ thông tin từ CloudWatch: service, môi trường, metric và ngưỡng." |
| **0:58–1:15** | Incident → RCA, mở **All cited evidence** | "Xora mở incident và tự điều tra, truy vấn log trong khung thời gian xảy ra sự cố. Kết luận: demo-app bị dừng bằng tín hiệu SIGTERM từ bên ngoài, không phải crash, kèm hai bằng chứng log được trích dẫn. Phần nào chưa đủ dữ liệu, ví dụ ai đã ra lệnh dừng, Xora ghi rõ là còn thiếu." |
| **1:15–1:25** | Khung **Recommended action (text only, never executed)** | "Khuyến nghị chỉ ở dạng văn bản, không tự thực thi. Người phụ trách xem xét và quyết định. Đó là luồng chính của Xora Resolve: nhận alert, điều tra, đưa ra nguyên nhân gốc, khuyến nghị, và con người duyệt." |

Lời thoại khoảng 230 từ, đọc với tốc độ vừa phải sẽ vừa khoảng 1 phút 25 giây.

## Bản rút gọn khoảng 45 giây

Giữ các đoạn **0:00–0:08**, **0:08–0:24** (chỉ đọc câu đầu và câu cuối), **0:58–1:15** và câu kết của đoạn **1:15–1:25**. Bỏ phần SNS, incident rule và terminal.

## Không nói trong video

Tài liệu overview ghi rõ các nội dung sau chưa được xác nhận:

- Xora tự khôi phục, tự restart service hoặc tự chạy runbook. Theo phạm vi demo 06/11, Xora chưa có các bước Execution và Outcome verification.
- Phản hồi theo thời gian thực.
- Bất kỳ tỷ lệ chính xác, mức tiết kiệm hay SLA nào.
- "Thay thế CloudWatch/Grafana".

## Sau khi quay

Khôi phục lab bằng `.\scripts\chaos.ps1 -Scenario stop`. Khi không còn dùng lab, chạy `terraform destroy` trong thư mục `terraform\` để không bị tính phí.
