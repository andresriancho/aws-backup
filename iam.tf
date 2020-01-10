resource "aws_iam_role" "AWSBackupServiceRolePolicyForBackup" {
  name               = "AWSBackupServiceRolePolicyForBackup"
  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": ["sts:AssumeRole"],
      "Effect": "allow",
      "Principal": {
        "Service": ["backup.amazonaws.com"]
      }
    }
  ]
}
POLICY
}

resource "aws_iam_role_policy_attachment" "AWSBackupServiceRolePolicyForBackup" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
  role       = aws_iam_role.AWSBackupServiceRolePolicyForBackup.name
}

resource "aws_iam_role_policy_attachment" "AWSKeyManagementServicePowerUser" {
  policy_arn = "arn:aws:iam::aws:policy/AWSKeyManagementServicePowerUser"
  role       = aws_iam_role.AWSBackupServiceRolePolicyForBackup.name
}