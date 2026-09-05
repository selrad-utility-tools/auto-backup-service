# AWS Setup Instructions

> Run these steps once on the `selrad-warehouse` VPS. Everything here is one-time provisioning of the bucket, the access credentials, and the IAM policy that owns them.

## 1. Share metadata

- Bucket name: `<your-bucket>` (e.g. `selrad-warehouse-backups`)
- Region: `<region>` (e.g. `eu-central-1`)
- The bucket should be **private**.

## 2. Create the bucket

```
aws s3api create-bucket \
  --bucket <your-bucket> \
  --region <region> \
  --create-bucket-configuration LocationConstraint=<region>
```

(If the region is `us-east-1`, omit the `--create-bucket-configuration` flag.)

## 3. Lifecycle rule — Cold Storage tier

Archive objects live 30 days in Standard, then transition to Glacier Deep Archive. Archives **never expire**: the VPS keeps the only rolling copies; S3 is the long-term store.

Create `lifecycle.json`:

```json
{
  "Rules": [
    {
      "Id": "cold-storage-transition",
      "Status": "Enabled",
      "Filter": {},
      "Transitions": [
        {
          "Days": 30,
          "StorageClass": "DEEP_ARCHIVE"
        }
      ]
    }
  ]
}
```

Apply it:

```
aws s3api put-bucket-lifecycle-configuration \
  --bucket <your-bucket> \
  --lifecycle-configuration file://lifecycle.json
```

## 4. IAM policy — least privilege

Create an IAM **user** (or role) named `auto-backup` and attach this policy. It can only list/get/put objects in the backup bucket — nothing else.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:ListBucket"],
      "Resource": "arn:aws:s3:::<your-bucket>"
    },
    {
      "Effect": "Allow",
      "Action": ["s3:PutObject", "s3:GetObject", "s3:HeadObject"],
      "Resource": "arn:aws:s3:::<your-bucket>/*"
    }
  ]
}
```

Create the access key for `auto-backup` and keep the pair somewhere safe — this is the only time the secret is displayed.

## 5. Store credentials on the VPS

```
sudo mkdir -p /etc/auto-backup
sudo tee /etc/auto-backup/aws.env > /dev/null <<'EOF'
AWS_ACCESS_KEY_ID=<access-key-id>
AWS_SECRET_ACCESS_KEY=<secret-access-key>
EOF
sudo chmod 600 /etc/auto-backup/aws.env
```

`chmod 600` means only root can read them. The systemd services load this file via `EnvironmentFile=`; the value never enters the repo or any script.

## 6. Configure the service

Edit `/etc/auto-backup/config` on the VPS (created by `setup.sh`):

```
BUCKET=<your-bucket>
REGION=<region>
WAREHOUSE_INFRA_DIR=/path/to/selrad-warehouse/infra
```

## 7. Verify

From the VPS, as root, a manual one-shot run should upload and confirm an object:

```
/opt/auto-backup/venv/bin/python /opt/auto-backup/service/offload.py --bucket <your-bucket> --region <region> --prefix warehouse /path/to/selrad-warehouse/backups/pg-data
```

(Add `--endpoint-url <url>` if using a custom S3-compatible provider.)

You should see a line like `OFFLOADED 11-05-2026-gz.sql.gz` per file. If the object is genuinely new, remove it again so the nightly run starts clean:

```
aws s3 rm s3://<your-bucket>/warehouse/11-05-2026-gz.sql.gz
```