resource "aws_iam_access_key" "aws_backup_ses_email" {
  user = aws_iam_user.aws_backup_ses_email.name
}

resource "aws_iam_user" "aws_backup_ses_email" {
  name = "aws_backup_ses_email"
}

resource "aws_iam_user_policy" "aws_backup_ses_email" {
  name = "aws_backup_ses_email"
  user = aws_iam_user.aws_backup_ses_email.name

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
       "Effect": "Allow",
       "Action": ["ses:SendEmail", "ses:SendRawEmail"],
       "Resource":"*"
     }
  ]
}
EOF
}

/*
  These need to match the secret names in lambda.py:

      SMTP_USER_SECRET_NAME = 'ses/smtp_user'
      SMTP_PASS_SECRET_NAME = 'ses/smtp_pass'
*/
resource "aws_secretsmanager_secret" "ses_smtp_user" {
  name = "ses/smtp_user"
}

resource "aws_secretsmanager_secret" "ses_smtp_pass" {
  name = "ses/smtp_pass"
}

resource "aws_secretsmanager_secret_version" "ses_smtp_user" {
  secret_id     = aws_secretsmanager_secret.ses_smtp_user.id
  secret_string = aws_iam_access_key.aws_backup_ses_email.id
}

resource "aws_secretsmanager_secret_version" "ses_smtp_pass" {
  secret_id     = aws_secretsmanager_secret.ses_smtp_pass.id
  secret_string = aws_iam_access_key.aws_backup_ses_email.ses_smtp_password
}
