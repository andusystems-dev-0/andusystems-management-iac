resource "aws_kms_key" "tf_state_kms_key" {
    description             = "KMS key for encrypting tf state s3 bucket"
    deletion_window_in_days = 10
}

resource "aws_s3_bucket" "tf_state_s3" {
    bucket          = "andusystems-management-tf-state"
    force_destroy   = true

    tags = {
        Name = "andusystems-management-tf-state"
        Environment = "Dev"
    }
}

resource "aws_s3_bucket_ownership_controls" "tf_state_s3_ownership_controls" {
    bucket                  = aws_s3_bucket.tf_state_s3.id 
    
    rule {
        object_ownership    = "BucketOwnerPreferred"
    }
}

resource "aws_s3_bucket_acl" "tf_state_acl" {
    depends_on  = [aws_s3_bucket_ownership_controls.tf_state_s3_ownership_controls]

    bucket      = aws_s3_bucket.tf_state_s3.id
    acl         = "private"
}

resource "aws_s3_bucket_versioning" "tf_state_versioning" {
    bucket = aws_s3_bucket.tf_state_s3.id
    
    versioning_configuration {
        status = "Enabled"
    }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tf_state_sse_config"{
    bucket  = aws_s3_bucket.tf_state_s3.id 
    
    rule {
        apply_server_side_encryption_by_default {
            kms_master_key_id = aws_kms_key.tf_state_kms_key.arn 
            sse_algorithm     = "aws:kms"
        }
    }
}
