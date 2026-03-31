package test

import (
	"fmt"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/aws/session"
	"github.com/aws/aws-sdk-go/service/s3"
	"github.com/aws/aws-sdk-go/service/ssm"
	"github.com/gruntwork-io/terratest/modules/random"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestS3Module(t *testing.T) {
	t.Parallel()

	region := os.Getenv("AWS_DEFAULT_REGION")
	if region == "" {
		region = "us-east-1"
	}

	uniqueID   := strings.ToLower(random.UniqueId())
	namePrefix := fmt.Sprintf("test-%s", uniqueID)

	opts := &terraform.Options{
		// Test the module directly, not the environment root.
		// Environment roots don't accept env/name_prefix as variables.
		TerraformDir: "../terraform/modules/s3",
		Vars: map[string]interface{}{
			"env":         "test",
			"name_prefix": namePrefix,
			"tags":        map[string]string{"Team": "platform"},
		},
		BackendConfig: map[string]interface{}{
			"bucket":         os.Getenv("TF_STATE_BUCKET"),
			"dynamodb_table": os.Getenv("TF_LOCK_TABLE"),
			"key":            fmt.Sprintf("test/%s.tfstate", uniqueID),
			"region":         region,
		},
		RetryableTerraformErrors: map[string]string{
			"RequestError: send request failed": "AWS transient error",
		},
		MaxRetries:         3,
		TimeBetweenRetries: 5 * time.Second,
	}

	defer terraform.Destroy(t, opts)
	terraform.InitAndApply(t, opts)

	bucketName := terraform.Output(t, opts, "bucket_name")
	require.NotEmpty(t, bucketName)

	sess := session.Must(session.NewSession(&aws.Config{Region: aws.String(region)}))
	s3c  := s3.New(sess)
	ssmc := ssm.New(sess)

	t.Run("versioning_enabled", func(t *testing.T) {
		out, err := s3c.GetBucketVersioning(&s3.GetBucketVersioningInput{Bucket: aws.String(bucketName)})
		require.NoError(t, err)
		assert.Equal(t, "Enabled", aws.StringValue(out.Status))
	})

	t.Run("encryption_aes256", func(t *testing.T) {
		out, err := s3c.GetBucketEncryption(&s3.GetBucketEncryptionInput{Bucket: aws.String(bucketName)})
		require.NoError(t, err)
		assert.Equal(t, "AES256", aws.StringValue(out.ServerSideEncryptionConfiguration.Rules[0].ApplyServerSideEncryptionByDefault.SSEAlgorithm))
	})

	t.Run("public_access_blocked", func(t *testing.T) {
		out, err := s3c.GetPublicAccessBlock(&s3.GetPublicAccessBlockInput{Bucket: aws.String(bucketName)})
		require.NoError(t, err)
		cfg := out.PublicAccessBlockConfiguration
		assert.True(t, aws.BoolValue(cfg.BlockPublicAcls))
		assert.True(t, aws.BoolValue(cfg.BlockPublicPolicy))
		assert.True(t, aws.BoolValue(cfg.IgnorePublicAcls))
		assert.True(t, aws.BoolValue(cfg.RestrictPublicBuckets))
	})

	t.Run("lifecycle_abort_mpu", func(t *testing.T) {
		out, err := s3c.GetBucketLifecycleConfiguration(&s3.GetBucketLifecycleConfigurationInput{Bucket: aws.String(bucketName)})
		require.NoError(t, err)
		found := false
		for _, r := range out.Rules {
			if r.AbortIncompleteMultipartUpload != nil {
				assert.Equal(t, int64(7), aws.Int64Value(r.AbortIncompleteMultipartUpload.DaysAfterInitiation))
				found = true
			}
		}
		assert.True(t, found, "abort incomplete MPU lifecycle rule not found")
	})

	t.Run("ssm_parameters", func(t *testing.T) {
		for _, path := range []string{
			fmt.Sprintf("/app/test/s3/%s-bucket-arn", namePrefix),
			fmt.Sprintf("/app/test/s3/%s-bucket-name", namePrefix),
		} {
			out, err := ssmc.GetParameter(&ssm.GetParameterInput{Name: aws.String(path)})
			require.NoError(t, err, "SSM parameter %s not found", path)
			assert.NotEmpty(t, aws.StringValue(out.Parameter.Value))
		}
	})
}