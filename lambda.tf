/*
 Create a lambda function that will auto-tag any resources which were
 not tagged by the infrastructure team. The newly applied tags provide
 resource with a minimal backup policy: `daily_two_weeks`

 The lambda function also notifies the ops team via email so that they
 can decide to apply a different tag (for increased backup
 or disabling using the "none" policy)
*/

resource "aws_iam_role" "iam_role_lambda_backup_auto_tagging" {
  name = "iam_role_lambda_backup_auto_tagging"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": "AllowLambdaAssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "iam_policy_lambda_backup_auto_tagging" {
  name = "iam_policy_lambda_backup_auto_tagging"
  role = aws_iam_role.iam_role_lambda_backup_auto_tagging.id

  policy = <<EOF
{
  "Version" : "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["rds:ListTagsForResource",
                 "rds:DescribeDBInstances",
                 "rds:AddTagsToResource",
                 "dynamodb:ListTables",
                 "dynamodb:ListTagsOfResource",
                 "dynamodb:TagResource",
                 "dynamodb:DescribeTable",
                 "elasticfilesystem:DescribeFileSystems",
                 "elasticfilesystem:DescribeTags",
                 "elasticfilesystem:CreateTags",
                 "ec2:DescribeVolumes",
                 "ec2:DescribeRegions",
                 "ec2:CreateTags",
                 "ec2:DescribeTags"],
      "Resource": "*"
    },
    {
        "Effect": "Allow",
        "Action": [
            "secretsmanager:GetResourcePolicy",
            "secretsmanager:GetSecretValue",
            "secretsmanager:DescribeSecret",
            "secretsmanager:ListSecretVersionIds"
        ],
        "Resource": [
            "arn:aws:secretsmanager:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:secret:ses/smtp*"
        ]
    },
    {
        "Effect": "Allow",
        "Action": [
            "logs:CreateLogGroup",
            "logs:CreateLogStream",
            "logs:PutLogEvents"
        ],
        "Resource": "arn:aws:logs:*:*:*"
    }
  ]
}
EOF
}

data "archive_file" "backup_auto_tagging_zip" {
  type        = "zip"
  output_path = "backup_auto_tagging.zip"
  source_file = "lambda.py"
}

resource "aws_lambda_function" "backup_auto_tagging" {
  function_name = "backup_auto_tagging"
  runtime = "python3.6"
  handler = "lambda.handle"

  # Let the function run for 5 minutes max
  timeout = 300

  role = aws_iam_role.iam_role_lambda_backup_auto_tagging.arn

  filename = data.archive_file.backup_auto_tagging_zip.output_path
  source_code_hash = data.archive_file.backup_auto_tagging_zip.output_base64sha256

  environment {
    variables = {
      MAIL_TO = var.mail_to
      MAIL_FROM = var.mail_from
    }
  }
}

resource "aws_cloudwatch_event_rule" "daily_tagging" {
  name = "daily_tagging"
  description = "Every day at 1pm tag newly created instances and alert ops team"
  schedule_expression = "cron(0 13 * * ? *)"
}

resource "aws_cloudwatch_event_target" "daily_tagging" {
  rule = aws_cloudwatch_event_rule.daily_tagging.name
  arn = aws_lambda_function.backup_auto_tagging.arn
}

resource "aws_lambda_permission" "daily_tagging" {
  statement_id = "AllowExecutionFromCloudWatchDailyTagging"
  action = "lambda:InvokeFunction"
  function_name = aws_lambda_function.backup_auto_tagging.function_name
  principal = "events.amazonaws.com"
  source_arn = aws_cloudwatch_event_rule.daily_tagging.arn
}
