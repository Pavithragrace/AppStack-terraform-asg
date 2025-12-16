output "state_bucket_name" { value = aws_s3_bucket.tfstate.bucket }
output "dynamodb_table_name" { value = aws_dynamodb_table.locks.name }
