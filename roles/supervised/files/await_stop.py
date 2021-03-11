import sys
import os
import time
import urllib2
import json
import boto3

SERVICE = sys.argv[1]

desc_str = urllib2.urlopen('http://169.254.169.254/latest/dynamic/instance-identity/document').read()
desc = json.loads(desc_str)

ec2 = boto3.client('ec2', region_name=desc['region'])
sqs = boto3.client('sqs', region_name=desc['region'])

inst_desc = ec2.describe_instances(InstanceIds=[desc['instanceId']])
tags = inst_desc['Reservations'][0]['Instances'][0]['Tags']
SQS_URL = None
for tag in tags:
    if tag['Key'] == 'SQS_URL':
        SQS_URL = tag['Value']
        break

if not SQS_URL:
    raise ValueError("Tag SQS_URL not found")

while True:
    all_msg = sqs.receive_message(QueueUrl=SQS_URL)
    for msg in all_msg.get('Messages', []):
        if msg['Body'] == 'stop':
            sqs.purge_queue(QueueUrl=SQS_URL)
            os.system('supervisorctl stop ' + SERVICE)
            os.system('shutdown -h now')
    time.sleep(10)
