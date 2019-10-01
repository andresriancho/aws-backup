/*

 Backup strategy for multiple resource types, including RDS and DynamoDB,
 usign AWS Backup.

 See: README.md in this directory for a summary on how this works

*/
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

resource "aws_backup_vault" "backup_vault" {
  name = "backup_vault"
}

/*

 Add extra security to the AWS backup vault by applying a resource policy
 that prevents anyone from:
 
    * Removing the recovery points
    * Deleting the backup vault
    * Change or delete the resource policy for the vault (which imposes the
      previous restrictions)

 This means that only the root account will ever be able to remove this
 backup vault! [0]

 Terraform doesn't have support for creating a backup vault access policy
 so we need to use local-exec and run the `aws cli` to create it.

 [0] https://docs.amazonaws.cn/en_us/general/latest/gr/root-vs-iam.html

*/

resource "local_file" "vault_access_policy" {
  filename = "vault-access-policy.json"
  content  = <<EOT
    {
      "Version": "2012-10-17",
      "Statement": [
          {
            "Effect": "Deny",
            "Principal": "*",
            "Action": ["backup:DeleteRecoveryPoint",
                       "backup:DeleteBackupVault",
                       "backup:PutBackupVaultAccessPolicy",
                       "backup:DeleteBackupVaultAccessPolicy"],
            "Resource": "${aws_backup_vault.backup_vault.arn}"
          }
      ]
    }
    EOT
}

resource "null_resource" "put-backup-vault-access-policy" {
  triggers = {
    policy = local_file.vault_access_policy.content
  }

  provisioner "local-exec" {
    command = "aws backup put-backup-vault-access-policy --region ${data.aws_region.current.name} --backup-vault-name ${aws_backup_vault.backup_vault.name} --policy file://vault-access-policy.json"
  }
  depends_on = ["aws_backup_vault.backup_vault",
  "local_file.vault_access_policy"]
}

/*
 Define the backup plans:

    * How often are backups created?
    
    * For how many days are we storing the backups?

 Also define tags for selecting which resources are applied to each
 backup plan.
*/
resource "aws_backup_plan" "daily_two_weeks" {
  name = "daily_two_weeks"
  rule {
    rule_name = "daily_two_weeks"
    target_vault_name = aws_backup_vault.backup_vault.name

    # every day at 3am
    schedule = "cron(0 3 * * ? *)"

    lifecycle {
      delete_after = "14"
    }
  }
}

resource "aws_backup_selection" "daily_two_weeks_selection" {
  plan_id = aws_backup_plan.daily_two_weeks.id
  name = "daily_two_weeks_selection"
  iam_role_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/service-role/AWSBackupDefaultServiceRole"

  selection_tag {
    type = "STRINGEQUALS"
    key = "backup_policy"
    value = "daily_two_weeks"
  }
}

resource "aws_backup_plan" "three_times_a_day_two_weeks" {
  name = "three_times_a_day_two_weeks"
  rule {
    rule_name = "three_times_a_day_two_weeks"
    target_vault_name = aws_backup_vault.backup_vault.name

    # every day at 0:00, 8:00 and 16:00
    schedule = "cron(0 0/8 * * ? *)"

    lifecycle {
      delete_after = "14"
    }
  }
}

resource "aws_backup_selection" "three_times_a_day_two_weeks_selection" {
  plan_id = aws_backup_plan.three_times_a_day_two_weeks.id
  name = "three_times_a_day_two_weeks_selection"
  iam_role_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/service-role/AWSBackupDefaultServiceRole"

  selection_tag {
    type = "STRINGEQUALS"
    key = "backup_policy"
    value = "three_times_a_day_two_weeks"
  }
}

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

  source {
    content  = "1"
    filename = "lambda.py"
  }
}

resource "aws_lambda_function" "backup_auto_tagging" {
  function_name = "backup_auto_tagging"
  runtime = "python3.6"
  handler = "lambda.handler"

  role = aws_iam_role.iam_role_lambda_backup_auto_tagging.arn

  filename = data.archive_file.backup_auto_tagging_zip.output_path
  source_code_hash = data.archive_file.backup_auto_tagging_zip.output_base64sha256
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
