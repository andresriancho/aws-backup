# AWS Backup
This is an AWS Backup implementation using Terraform with security and operational
best practices in mind.

The following services are supported:
 * RDS
 * EBS
 * EBS
 * DynamoDB

## Workflow

 * [AWS Backup](https://aws.amazon.com/backup/) selects resources to backup
   using resource tags. The resource tags determine the backup plan to use.
   
 * A lambda function identifies resources without the `backup_policy` tag,
   auto-tags those resources with the default backup plan and notifies
   the operations team.

 * Backups are performed using the [AWS Backup](https://aws.amazon.com/backup/) service.
   All backups are stored in a backup vault named `backup_vault`.

## Security

This terraform config adds extra security to the AWS backup vault setup by applying a
resource policy that prevents any user from:
 
 * Removing the recovery points
 * Removing the backup vault
 * Changing or removing the resource policy which imposes the previous restrictions

This means that [only the root account](https://docs.aws.amazon.com/en_pv/general/latest/gr/root-vs-iam.html)
will ever be able to remove this backup vault! The backup vault will survive even
in a scenario where a privileged IAM principal with `*:*` permissions is compromised.

## Backup plan customization

Review the `backup.tf` file and customize the `aws_backup_plan` resources
to match your company policies. This is a resource definition from the latest
implementation:

```
resource "aws_backup_plan" "daily_two_weeks" {
  name = "daily_two_weeks"
  rule {
    rule_name = "daily_two_weeks"
    target_vault_name = "${aws_backup_vault.backup_vault.name}"

    # every day at 3am
    schedule = "cron(0 3 * * ? *)"

    lifecycle {
      delete_after = "14"
    }
  }
}
```

Customize the name (`daily_two_weeks`), `schedule` and `lifecycle` to match
your company requirements. Then create a selector similar to the following:

```
resource "aws_backup_selection" "daily_two_weeks_selection" {
  plan_id = "${aws_backup_plan.daily_two_weeks.id}"
  name = "daily_two_weeks_selection"
  iam_role_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/service-role/AWSBackupDefaultServiceRole"

  selection_tag {
    type = "STRINGEQUALS"
    key = "backup_policy"
    value = "daily_two_weeks"
  }
}
```

The `aws_backup_selection` resource is used to match the resources for the
`aws_backup_plan`. In this case the resources with `backup_policy` tag with
value `daily_two_weeks` are selected and associated with the `plan_id`. 

## Customize notification emails

Edit the `variables.tf` configuration to define the `to` and `from` email
addresses to use by the Lambda function to send notifications.

The `from` email address will require you to perform an [SES verification](https://docs.aws.amazon.com/en_pv/ses/latest/DeveloperGuide/verify-email-addresses.html).
In other words, after applying these terraform configs you will have to go
to the email inbox for the `from` email address and click on a verification link
that will allow the Lambda function to send emails from this address.  

## Installation

After customization, configure your credentials in `~/.aws/credentials` and use
the following commands to deploy:

```
cd aws-backup/ 

terraform init
terraform plan -var profile=awsbackup
terraform apply -var profile=awsbackup
```

Manually tag all resources in your infrastructure using a tag named `backup_policy`
containing one of `aws_backup_plan` as values. Any resources that AWS backup can
manage and were not manually tagged will be notified by the lambda function to
the operations team.

## Disabling backup

It is possible to disable backups for a specific resource using the tag `backup_policy`
with value `none`. This will prevent AWS Backup from running backups on the resource
and the Lambda function from sending notifications.

## Auto-tagging resources

The `backup_auto_tagging` lambda function is run every day and inspects the
infrastructure looking for resources which have no backups enabled (aka. no
`backup_policy` tag). When such a resource is found the lambda function will:

 * *auto tag it* with `backup_policy: daily_two_weeks`
 * Notify the infrastructure team, as they might want to change the backup
   policy and update the terraform configs.

## Restoring a backup

The recommended steps for restoring a backup are in the [AWS documentation](https://docs.aws.amazon.com/aws-backup/latest/devguide/restore-resource.html)

## Development

```
terraform fmt
```