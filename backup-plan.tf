/*
 Define the backup plans:

    * How often are backups created?

    * For how many days are we storing the backups?

 Also define tags for selecting which resources are applied to each
 backup plan.

 Documentation on how to write the cron expressions is here [0], note
 that it uses a slightly different format from linux cron.

 [0] https://docs.aws.amazon.com/AmazonCloudWatch/latest/events/ScheduledEvents.html
*/
resource "aws_backup_plan" "daily_except_sunday" {
  name = "daily_except_sunday"
  rule {
    rule_name = "daily_except_sunday"
    target_vault_name = aws_backup_vault.backup_vault.name

    #
    # every day except sundays (day index 1) at 3am
    #
    # sundays are not included here to prevent duplicates with the
    # weekly backup plan
    #
    schedule = "cron(0 3 ? * 2-7 *)"

    lifecycle {
      # Keep daily backups for 7 days
      delete_after = "7"

      # Can't use cold_storage_after here because data needs to be stored there
      # for at least 90 days
      #
      # cold_storage_after = "..."
    }
  }
}


resource "aws_backup_plan" "weekly_on_sunday" {
  name = "weekly_on_sunday"
  rule {
    rule_name = "weekly_on_sunday"
    target_vault_name = aws_backup_vault.backup_vault.name

    #
    # every week on sundays at 3am
    #
    # TODO: Improve to exclude the first sunday of the month to prevent
    #       duplicates with the monthly aws_backup_plan defined below
    #
    schedule = "cron(0 3 ? * 1 *)"

    lifecycle {
      # Keep weekly backups for a month
      delete_after = "31"

      # Can't use cold_storage_after here because data needs to be stored there
      # for at least 90 days
      #
      # cold_storage_after = "..."
    }
  }
}

resource "aws_backup_plan" "monthly_on_first_day_of_month" {
  name = "monthly_on_first_day_of_month"
  rule {
    rule_name = "monthly_on_first_day_of_month"
    target_vault_name = aws_backup_vault.backup_vault.name

    #
    # every first day of the month at 3am
    #
    # TODO: Improve to exclude July to prevent duplicates with the yearly
    #       aws_backup_plan defined below
    #
    schedule = "cron(0 3 1 * ? *)"

    lifecycle {
      # Keep monthly backups for a year
      delete_after = "365"

      # Move them to cold storage after 7 days of creation
      cold_storage_after = "7"
    }
  }
}

resource "aws_backup_plan" "yearly_on_july_first" {
  name = "yearly_on_july_first"
  rule {
    rule_name = "yearly_on_july_first"
    target_vault_name = aws_backup_vault.backup_vault.name

    #
    # every first of July at 3am
    #
    schedule = "cron(0 3 1 7 ? *)"

    lifecycle {
      # Keep yearly backups for 10 years
      delete_after = "3650"

      # Move them to cold storage after 7 days of creation
      cold_storage_after = "7"
    }
  }
}


resource "aws_backup_selection" "daily_except_sunday_selection" {
  plan_id = aws_backup_plan.daily_except_sunday.id
  name = "daily_except_sunday_selection"
  iam_role_arn = aws_iam_role.AWSBackupServiceRolePolicyForBackup.arn

  selection_tag {
    type = "STRINGEQUALS"
    key = "backup_policy"
    value = "grandfather-father-son"
  }
}

resource "aws_backup_selection" "weekly_on_sunday_selection" {
  plan_id = aws_backup_plan.weekly_on_sunday.id
  name = "weekly_on_sunday_selection"
  iam_role_arn = aws_iam_role.AWSBackupServiceRolePolicyForBackup.arn

  selection_tag {
    type = "STRINGEQUALS"
    key = "backup_policy"
    value = "grandfather-father-son"
  }
}

resource "aws_backup_selection" "monthly_on_first_day_of_month_selection" {
  plan_id = aws_backup_plan.monthly_on_first_day_of_month.id
  name = "monthly_on_first_day_of_month_selection"
  iam_role_arn = aws_iam_role.AWSBackupServiceRolePolicyForBackup.arn

  selection_tag {
    type = "STRINGEQUALS"
    key = "backup_policy"
    value = "grandfather-father-son"
  }
}

resource "aws_backup_selection" "yearly_on_july_first_selection" {
  plan_id = aws_backup_plan.yearly_on_july_first.id
  name = "yearly_on_july_first_selection"
  iam_role_arn = aws_iam_role.AWSBackupServiceRolePolicyForBackup.arn

  selection_tag {
    type = "STRINGEQUALS"
    key = "backup_policy"
    value = "grandfather-father-son"
  }
}
