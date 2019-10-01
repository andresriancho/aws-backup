## Backup strategy

The backup strategy for the AWS account is defined in `backup.tf`.

If you want to enable backups for your RDS, DynamoDB, EBS volumes, or EFS file systems you
just need to add a tag named `backup_policy` with one of the following values:

 * `daily_two_weeks`: Daily backups will be performed and stored for two weeks
 * `three_times_a_day_two_weeks`: Backups are performed three times per day and stored for two weeks

It is possible to disable backups using `backup_policy: none`.

Backups are performed using the [AWS Backup](https://aws.amazon.com/backup/) service.
All backups are stored in a backup vault named `backup_vault` (production account).

## Auto-tagging resources

The `backup_auto_tagging` lambda function is run every day and inspects the infrastructure
looking for resources which have no backups enabled (aka. no `backup_policy` tag). When such a 
resource is found the lambda function will:

 * *auto tag it* with `backup_policy: daily_two_weeks`
 * Notify the infrastructure team, as they might want to change the backup policy and update
   the terraform configs.

## Restoring a backup

The recommended steps for restoring a backup are in the [AWS documentation](https://docs.aws.amazon.com/aws-backup/latest/devguide/restore-resource.html)