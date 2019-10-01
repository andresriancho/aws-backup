import os
import sys
import ssl
import smtplib
import traceback

from time import gmtime, strftime

import boto3

REGION = 'us-east-1'

BACKUP_TAG_NAME = 'backup_policy'
BACKUP_DEFAULT_VALUE = 'daily_two_weeks'
BACKUP_TAG = {
    'Key': BACKUP_TAG_NAME,
    'Value': BACKUP_DEFAULT_VALUE
}

SMTP_PORT = 465
SMTP_HOST = 'email-smtp.us-east-1.amazonaws.com'
SMTP_SECURE = True

SMTP_USER_SECRET_NAME = 'ses/smtp_user'
SMTP_PASS_SECRET_NAME = 'ses/smtp_pass'

MAIL_TO = 'ops-team@intraway.com'
MAIL_FROM = 'ops-team@intraway.com'
MAIL_SUBJECT_FMT = 'Default backup policy set for ARN %s'


def log(message):
    timestamp = strftime("%Y-%m-%d %H:%M:%S", gmtime())
    print('[%s] %s' % (timestamp, message))


def send_email(subject, message):
    subject_message = ('Subject: %s\n'
                       '\n'
                       '%s')
    
    subject_message %= (subject, message)

    secrets_client = boto3.client('secretsmanager')
    smtp_user = secrets_client.get_secret_value(SecretId='ses/smtp_user')['SecretString']
    smtp_pass = secrets_client.get_secret_value(SecretId='ses/smtp_pass')['SecretString']

    context = ssl.create_default_context()
    
    with smtplib.SMTP_SSL(SMTP_HOST, SMTP_PORT, context=context) as server:
        server.login(smtp_user, smtp_pass)
        server.sendmail(MAIL_FROM, MAIL_TO, subject_message)


def tag_rds():
    rds_client = boto3.client('rds', region_name=REGION)

    instances = rds_client.describe_db_instances()

    for instance in instances['DBInstances']:
        db_arn = instance['DBInstanceArn']
        rds_tags = rds_client.list_tags_for_resource(ResourceName=db_arn)['TagList']
        
        rds_tags = [rds_tag['Key'].lower() for rds_tag in rds_tags]
        
        if BACKUP_TAG_NAME in rds_tags:
            # This RDS instance has already been tagged
            continue
        
        #
        # Need to tag this RDS instance and notify the ops team
        #
        rds_client.add_tags_to_resource(
            ResourceName=db_arn,
            Tags=[BACKUP_TAG,]
        )
        notify_missing_tag(db_arn)


def tag_ebs():
    ec2_client = boto3.client('ec2', region_name=REGION)

    volumes = ec2_client.describe_volumes()

    for volume in volumes['Volumes']:
        volume_id = volume['VolumeId']

        volume_tags = ec2_client.describe_tags(Filters=[{'Name': 'resource-id',
                                                         'Values': [volume_id]}])['Tags']
        volume_tags = [volume_tag['Key'].lower() for volume_tag in volume_tags]
        
        if BACKUP_TAG_NAME in volume_tags:
            # This volume has already been tagged
            continue
        
        #
        # Need to tag this volume and notify the ops team
        #
        ec2_client.create_tags(
            Resources=[volume_id],
            Tags=[BACKUP_TAG,]
        )
        notify_missing_tag(volume_id)


def tag_efs():
    efs_client = boto3.client('efs')

    file_systems = efs_client.describe_file_systems()

    for file_system in file_systems['FileSystems']:

        file_system_id = file_system['FileSystemId']

        file_system_tags = efs_client.describe_tags(FileSystemId=file_system_id)['Tags']
        file_system_tags = [file_system_tag['Key'].lower() for file_system_tag in file_system_tags]
        
        if BACKUP_TAG_NAME in file_system_tags:
            # This file system has already been tagged
            continue
        
        #
        # Need to tag this table and notify the ops team
        #
        efs_client.create_tags(
            FileSystemId=file_system_id,
            Tags=[BACKUP_TAG,]
        )
        notify_missing_tag(file_system_id)


def tag_dynamodb():
    dynamodb_client = boto3.client('dynamodb')

    tables = dynamodb_client.list_tables()

    for table_name in tables['TableNames']:
        table_description = dynamodb_client.describe_table(TableName=table_name)
        table_arn = table_description['Table']['TableArn']
        table_tags = dynamodb_client.list_tags_of_resource(ResourceArn=table_arn)['Tags']

        table_tags = [table_tag['Key'].lower() for table_tag in table_tags]
        
        if BACKUP_TAG_NAME in table_tags:
            # This table has already been tagged
            continue
        
        #
        # Need to tag this table and notify the ops team
        #
        dynamodb_client.tag_resource(
            ResourceArn=table_arn,
            Tags=[BACKUP_TAG,]
        )
        notify_missing_tag(table_arn)


def notify_missing_tag(arn):
    message = ('The resource with ARN %s had no %s tags.\n'
               '\n'
               'The default tag "%s: %s" was added to force this resource to have backups.\n'
               '\n'
               'Please review if the default backup policy is adequate for this resource.'
               ' Apply any changes using terraform configuration files by adding tags to'
               ' the newly created resource.')
    args = (arn, BACKUP_TAG_NAME, BACKUP_TAG_NAME, BACKUP_DEFAULT_VALUE)
    log(message % args)
    
    # Send the email notification
    send_email(MAIL_SUBJECT_FMT % arn, message % args)


TAG_FUNCTIONS = {
    tag_rds,
    tag_ebs,
    tag_efs,
    tag_dynamodb
}

def handle(event, context):
    """
    Identify RDS, EBS, EFS and DynamoDB resources in the AWS account which
    do not have a `backup_policy` tag and:
    
        * Notify the ops team
        * Add a tag with `backup_policy: daily_two_weeks`
    
    This tag is used in backup.tf to select which resources to backup using
    AWS Backup.
    """
    log("Start backup_auto_tagging")
    success = True

    for tag_function in TAG_FUNCTIONS:
        try:
            tag_function()
        except Exception as e:
            # Send error message to log
            args = (tag_function.__name__, e)
            log("%s raised an exception: %s" % args)

            # Detailed traceback to log
            exc_type, exc_value, exc_traceback = sys.exc_info()
            traceback.print_tb(exc_traceback, file=sys.stdout)
            
            # Store failure and continue with the next function
            success = False

    log("End backup_auto_tagging")
    return success
