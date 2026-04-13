# `aws_s3_bucket_versioning` — Argument Reference

> Sourced from the [HashiCorp AWS Terraform provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_versioning)
> (hashicorp/terraform-provider-aws, AWS provider ~> 5.x).

Provides a resource for controlling versioning on an S3 bucket.
Deleting this resource will either **suspend** versioning on the associated S3 bucket or simply remove the resource from Terraform state if the associated S3 bucket is unversioned.

> **Note:** This resource cannot be used with S3 directory buckets.

---

## Top-level Arguments

| Argument | Required / Optional | Type | Forces New Resource | Description |
|---|---|---|---|---|
| `bucket` | **Required** | `string` | Yes | Name of the S3 bucket. |
| `versioning_configuration` | **Required** | block | No | Configuration block for the versioning parameters. See [versioning_configuration](#versioning_configuration) below. |
| `expected_bucket_owner` | Optional | `string` | Yes | Account ID of the expected bucket owner. **Deprecated** in favour of provider-level `assume_role`. |
| `mfa` | Optional (Required if `mfa_delete` is `Enabled`) | `string` | No | Concatenation of the MFA device's serial number, a space, and the token value displayed on the device. |
| `region` | Optional | `string` | No | Region where this resource will be managed. Defaults to the region set in the provider configuration. |

---

## `versioning_configuration` Block Arguments

| Argument | Required / Optional | Valid Values | Description |
|---|---|---|---|
| `status` | **Required** | `Enabled`, `Suspended`, `Disabled` | Versioning state of the bucket. `Disabled` should only be used when _creating_ or _importing_ resources that correspond to unversioned S3 buckets. Updating from `Enabled` or `Suspended` back to `Disabled` is not supported by the AWS S3 API. |
| `mfa_delete` | Optional | `Enabled`, `Disabled` | Specifies whether MFA Delete is enabled in the bucket versioning configuration. When `Enabled`, the top-level `mfa` argument is also required. |

---

## Exported Attributes (Read-only)

| Attribute | Description |
|---|---|
| `id` | The `bucket`, or `bucket` and `expected_bucket_owner` joined with a comma if the latter is provided. |

---

## Example Usage

```hcl
resource "aws_s3_bucket" "example" {
  bucket = "example-bucket"
}

resource "aws_s3_bucket_versioning" "example" {
  bucket = aws_s3_bucket.example.id

  versioning_configuration {
    status = "Enabled"
  }
}
```

To enable MFA Delete (requires MFA device):

```hcl
resource "aws_s3_bucket_versioning" "example" {
  bucket = aws_s3_bucket.example.id
  mfa    = "arn:aws:iam::${var.account_id}:mfa/my-device <token>"

  versioning_configuration {
    status     = "Enabled"
    mfa_delete = "Enabled"
  }
}
```

---

## Key Caveats

- AWS recommends waiting **15 minutes** after first enabling versioning before issuing PUT/DELETE operations on objects.
- Once versioning is `Enabled` or `Suspended`, it **cannot** be reverted to `Disabled` via Terraform (AWS API restriction).
- The `expected_bucket_owner` argument is deprecated; use the provider-level `assume_role` configuration instead.
