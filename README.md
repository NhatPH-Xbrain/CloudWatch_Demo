# CloudWatch_Demo: lab kiểm thử connector Xora Resolve ↔ AWS CloudWatch

Lab AWS dùng xong rồi xoá (region `ap-southeast-1`, nằm trong free tier). Lab tạo ra **CloudWatch alarm thật** và đẩy chúng qua **SNS** sang **Xora Resolve**. Xora kết nối vào tài khoản AWS bằng cách **assume một IAM role** có quyền đọc.

Mỗi lỗi đều được cố ý gây ra và có nguyên nhân gốc đã biết trước, để kiểm tra rằng Xora Resolve:

1. nhận được alert và gom chúng thành incident,
2. đề xuất **đúng nguyên nhân gốc** (RCA) khi bắt đầu điều tra,
3. cần người duyệt mới chấp nhận đề xuất, và **không bao giờ thay đổi tài nguyên AWS**.

```
VPC xora-test-vpc (1 public subnet + internet gateway)
└─ EC2 t3.micro (Amazon Linux 2023)
    ├─ demo-app (python :8080, /health, /error) ──log──► /xora-test/demo-app ─metric filter─► XoraTest/AppErrorCount
    ├─ CloudWatch Agent ──► CWAgent mem_used_percent, disk_used_percent
    ├─ health timer     ──► XoraTest/AppHealthy (1/0 mỗi phút)
    └─ /opt/chaos/chaos.sh (gây lỗi có chủ đích, điều khiển qua SSM)
                 │
      6 CloudWatch alarm ──ALARM / OK──► SNS xora-test-xora-resolve-alerts ──HTTPS──► Xora Resolve
                                                       ▲
      Xora Resolve ──sts:AssumeRole (External ID)──► IAM role xora-test-xora-resolve-connector
                   (đọc alarm, metric, log; tự subscribe vào SNS topic)
```

| Alarm | Metric | Kích hoạt khi |
|---|---|---|
| `xora-test-cpu-high` | AWS/EC2 CPUUtilization | > 80 % (chu kỳ 5 phút; 1 phút nếu `detailed_monitoring = true`) |
| `xora-test-app-errors` | XoraTest/AppErrorCount | ≥ 5 dòng log ERROR / phút |
| `xora-test-disk-high` | CWAgent disk_used_percent (/) | > 85 % trong 2 phút |
| `xora-test-mem-high` | CWAgent mem_used_percent | > 80 % trong 2 phút |
| `xora-test-app-down` | XoraTest/AppHealthy (dimension `Service=xora-test-app`) | < 1 trong 2 phút |
| `xora-test-status-check` | AWS/EC2 StatusCheckFailed_Instance | ≥ 1 trong 2 phút (chỉ kích hoạt khi host/OS có sự cố thật) |

## Cấu trúc thư mục

| Đường dẫn | Nội dung |
|---|---|
| `terraform/xora_role.tf` | IAM role cho Xora: trust policy (gateway của Xora + External ID) và permissions policy |
| `terraform/sns.tf` | SNS topic nhận alarm; subscription webhook tuỳ chọn |
| `terraform/alarms.tf` | 6 CloudWatch alarm |
| `terraform/ec2.tf`, `user_data.sh.tpl` | EC2 chạy demo-app, CloudWatch Agent và script chaos |
| `terraform/network.tf` | VPC riêng cho lab và security group |
| `terraform/iam.tf` | Role của EC2 (CloudWatch Agent + SSM) |
| `scripts/chaos.ps1` | Gây lỗi trên EC2 qua SSM |
| `scripts/smoke-test.ps1` | Kiểm tra nhanh đường CloudWatch → SNS → Xora |
| `scripts/watch-alarms.ps1` | Theo dõi trạng thái alarm theo thời gian thực |

## 1. Chuẩn bị (Windows)

```powershell
winget install Hashicorp.Terraform
winget install Amazon.AWSCLI
```

Mở terminal mới để PATH nhận lệnh, rồi đăng nhập AWS bằng **một** trong hai cách:

- **`aws login`** (khuyên dùng với IAM user, không cần access key): mở trình duyệt, đăng nhập console, chọn region `ap-southeast-1`.
- **Access key**: Console → tên user → **Security credentials** → **Create access key** (use case *CLI*), rồi chạy `aws configure`.

Kiểm tra: `aws sts get-caller-identity`. User cần quyền tạo IAM role, EC2, VPC, SNS, CloudWatch và Logs. Với tài khoản lab, `AdministratorAccess` là đơn giản nhất.

> **Lưu ý khi dùng `aws login`:** Terraform provider chưa đọc được credentials của `aws login`. Trước mỗi lần chạy `terraform`, xuất credentials tạm ra biến môi trường:
> ```powershell
> $c = aws configure export-credentials --format process | ConvertFrom-Json
> $env:AWS_ACCESS_KEY_ID=$c.AccessKeyId; $env:AWS_SECRET_ACCESS_KEY=$c.SecretAccessKey; $env:AWS_SESSION_TOKEN=$c.SessionToken
> ```
> Credentials này hết hạn sau một thời gian; nếu Terraform báo lỗi credentials thì chạy lại đoạn trên.

Cài thêm **Session Manager plugin** nếu muốn mở shell vào EC2 (`aws ssm start-session`). `chaos.ps1` không cần plugin này.

## 2. Lấy thông tin từ Xora Resolve

Trong Xora Resolve, tạo connector CloudWatch và chọn tab **Assume role**. Ghi lại:

- **External ID** (dạng `xora-...`)
- **Gateway principal ARN** (ví dụ `arn:aws:iam::098640806013:role/techx-xora-dev-xora-gateway`)
- **Trust policy** và **Permissions policy** (đã được cài sẵn trong `terraform/xora_role.tf`; chỉ cần sửa nếu Xora thay đổi)

## 3. Triển khai

```powershell
cd terraform
copy terraform.tfvars.example terraform.tfvars
# Mở terraform.tfvars, điền xora_external_id (và xora_gateway_principal_arn nếu khác)
terraform init
terraform plan -out tfplan
terraform apply tfplan
terraform output xora_connector_settings
```

`terraform.tfvars`, `tfplan` và `terraform.tfstate` chứa External ID và thông tin tài khoản, đã nằm trong `.gitignore`. **Không commit các file này.**

Terraform tạo khoảng 22 tài nguyên: VPC riêng cho lab, EC2, 6 alarm, SNS topic, log group, IAM role cho EC2 và IAM role cho Xora.

### Role của Xora

**Trust policy:** chỉ gateway role của Xora được assume, và bắt buộc gửi đúng External ID:

```json
{
  "Effect": "Allow",
  "Principal": { "AWS": "<Gateway principal ARN>" },
  "Action": "sts:AssumeRole",
  "Condition": { "StringEquals": { "sts:ExternalId": "<External ID>" } }
},
{
  "Effect": "Allow",
  "Principal": { "AWS": "<Gateway principal ARN>" },
  "Action": "sts:TagSession"
}
```

**Permissions policy:** chỉ đọc, ngoài quyền subscribe/unsubscribe SNS:

```
cloudwatch:DescribeAlarms, cloudwatch:GetMetricData,
logs:StartQuery, logs:GetQueryResults, logs:StopQuery,
sns:ListTopics, sns:Subscribe, sns:Unsubscribe
```

Nếu Xora yêu cầu policy khác, dán JSON của Xora vào biến `xora_permissions_policy_json` trong `terraform.tfvars` rồi chạy lại `terraform apply`.

## 4. Điền vào form connector của Xora

Lấy giá trị từ `terraform output xora_connector_settings`:

| Trường trong form | Giá trị |
|---|---|
| **AWS region** | `ap-southeast-1` |
| **AWS Cloudwatch SNS Topic [ARN or name]** | `arn:aws:sns:ap-southeast-1:<account-id>:xora-test-xora-resolve-alerts` |
| **Protocol to use for the webhook** | `https` |
| **Role this gateway assumes in your account** | `arn:aws:iam::<account-id>:role/xora-test-xora-resolve-connector` |

Sau khi lưu connector:

- Vào **SNS → Topics → xora-test-xora-resolve-alerts → Subscriptions**, kiểm tra subscription của Xora có trạng thái **Confirmed**.
- Đợi khoảng 5 phút để EC2 cài xong (dnf install + khởi động agent). Kiểm tra bằng `.\scripts\chaos.ps1 -Scenario status`.
- Để `.\scripts\watch-alarms.ps1` chạy ở một terminal khác trong suốt quá trình test.

> **Tuỳ chọn:** nếu muốn gửi thẳng tới một webhook URL thay vì để Xora tự subscribe, đặt `xora_webhook_url = "https://..."` trong `terraform.tfvars`. Nếu subscription kẹt ở *Pending confirmation*, đặt thêm `xora_endpoint_auto_confirms = false`.

## 5. Tạo incident rule trong Xora

Xora lấy trường **Service** của alert CloudWatch từ dimension của alarm. Các alarm EC2 dùng `InstanceId`, nên Service sẽ đổi mỗi khi EC2 bị tạo lại. Riêng alarm demo `xora-test-app-down` dùng dimension cố định `Service = xora-test-app` (biến `service_name`), nên rule dưới đây không phải sửa khi chạy lại `terraform apply`.

| Trường | Giá trị |
|---|---|
| Rule name | `CloudWatch demo - app down` |
| Trigger | At least **1** alerts matching **any** conditions |
| Time window | **20 min** |
| Group by | `service` |
| Environment | **DEV** |
| Priority | `5` |
| Condition key | `cw` |
| Condition description | `demo-app trên lab CloudWatch ngừng chạy` |
| Filter 1 | **Provider** · is equal · `CLOUDWATCH` |
| Filter 2 | **Service** · is equal · `xora-test-app` |

CEL tương ứng:

```
provider.isEqual("CLOUDWATCH") && service.isEqual("xora-test-app")
```

Kiểm tra: `.\scripts\chaos.ps1 -Scenario service-down` (lỗi thật, alarm sau khoảng 2–3 phút) hoặc `.\scripts\smoke-test.ps1 -AlarmName xora-test-app-down` (ép trạng thái ngay). Khôi phục bằng `.\scripts\chaos.ps1 -Scenario stop`.

## 6. Các kịch bản kiểm thử

Chạy trong thư mục `scripts\`. **Chạy `-Scenario stop` và đợi mọi alarm về OK trước khi sang kịch bản tiếp theo.** Mỗi lần chạy chaos được ghi vào `results/timeline.csv` để đo thời gian alert tới Xora.

| UC | Lệnh | Alarm mong đợi | Nguyên nhân gốc Xora cần đề xuất | Bằng chứng Xora cần dẫn ra |
|---|---|---|---|---|
| **UC0 Smoke** | `.\smoke-test.ps1` (hoặc `-Mode RawPublish`) | cpu-high bị ép sang ALARM | Không áp dụng: chỉ cần alert tới nơi | Bản tin SNS |
| **UC1 CPU tăng vọt** | `.\chaos.ps1 -Scenario cpu` | cpu-high | CPU bị một process chạy mất kiểm soát (`stress-ng`) chiếm hết, không phải do traffic | CPUUtilization ~100 % |
| **UC2 Lỗi ứng dụng** | `.\chaos.ps1 -Scenario errors` | app-errors | demo-app không kết nối được database (`db connection refused host=orders-db`) | Các dòng ERROR trong `/xora-test/demo-app` |
| **UC3 Đầy ổ đĩa** | `.\chaos.ps1 -Scenario disk` | disk-high | Ổ root bị lấp đầy bởi một file lớn (`/var/tmp/xora-fill.bin`) | disk_used_percent nhảy lên ~92 % |
| **UC4 Bộ nhớ** | `.\chaos.ps1 -Scenario memory` | mem-high | Một process chiếm phần lớn RAM | mem_used_percent > 80 % |
| **UC5 Dịch vụ ngừng** | `.\chaos.ps1 -Scenario service-down` | app-down | demo-app bị dừng; host vẫn khoẻ (CPU, status check bình thường) | AppHealthy = 0, status check OK |
| **UC6 Tương quan** | `.\chaos.ps1 -Scenario correlated` | cpu-high + app-errors | Gom nhóm: hai alert có nằm trong **một** incident không? RCA cần tách được hai nguyên nhân (hoặc giải thích mối liên hệ) | Cả hai metric |
| **UC7 Phục hồi** | `.\chaos.ps1 -Scenario stop` sau bất kỳ UC nào | Thông báo OK | Incident được cập nhật hoặc đóng khi có OK | Bản tin OK |
| **UC8 Dao động** | `.\chaos.ps1 -Scenario flap` (≈36 phút) | cpu-high ALARM→OK ×3 | Loại bỏ trùng lặp, chỉ một incident thay vì ba | Các lần chuyển trạng thái lặp lại |

Kiểm tra an toàn bổ sung (tuỳ chọn):

- **UC9 Chỉ đọc:** sau khi test xong, vào **CloudTrail → Event history**, lọc theo role `xora-test-xora-resolve-connector`. Ngoài `Subscribe`/`Unsubscribe` SNS, không được có API ghi nào.
- **UC10 Người duyệt:** xác nhận không RCA nào được coi là chấp nhận khi chưa có người duyệt.
- **UC11 Payload sai:** chạy `.\smoke-test.ps1 -Mode RawPublish` với nội dung đã sửa. Xora cần từ chối hoặc bỏ qua một cách gọn gàng.

## 7. Ghi kết quả

Chép bảng sau vào `results/results.md` và điền cho từng UC:

| UC | Thời điểm gây lỗi (UTC) | Alarm sang ALARM (UTC) | Alert tới Xora (UTC) | Gom incident đúng? | RCA đúng? | Người duyệt chấp nhận? | Ghi chú |
|---|---|---|---|---|---|---|---|
| UC1 | | | | | | | |

## 8. Dọn dẹp (đừng bỏ qua)

```powershell
.\scripts\chaos.ps1 -Scenario stop
cd terraform
terraform destroy
```

Trước khi destroy, gỡ connector trong Xora (hoặc để Xora tự `Unsubscribe`) để tránh subscription mồ côi. `terraform destroy` xoá cả VPC lab và IAM role của Xora; sau đó Xora sẽ không assume được nữa.

## Chi phí

- t3.micro và ổ gp3 8 GB nằm trong free tier (750 giờ/tháng, 12 tháng đầu hoặc gói free dạng credit).
- `cpu_credits = "standard"` để bài stress CPU không phát sinh phí T3 Unlimited.
- VPC lab không có NAT gateway, nên không có phí theo giờ.
- 6 alarm, các lần gửi SNS qua HTTPS và vài MB log tốn rất ít. Mỗi custom metric (AppHealthy, AppErrorCount, 2 metric CWAgent và các metric tổng hợp) khoảng 0,30 USD/tháng **sau** 10 metric miễn phí, tính theo giờ.
- `detailed_monitoring = true` tốn thêm khoảng 2 USD/tháng khi lab đang chạy.
