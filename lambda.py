import os
import json
import boto3

INSTANCE_ID = os.environ['INSTANCE_ID']
SQS_URL = os.environ['SQS_URL']

ec2 = boto3.client('ec2')
sqs = boto3.client('sqs')

def lambda_handler(event, context):
    try:
        result = ec2.describe_instances(InstanceIds=[INSTANCE_ID])
        instance = result['Reservations'][0]['Instances'][0]
        state = instance['State']['Name']

        if event['rawPath'].endswith('start'):
            if state != 'stopped':
                reply = "Instance is {}. It can only by started when in the 'stopped' state".format(state)
            else:
                reply = "Instance is starting..."
                ec2.start_instances(InstanceIds=[INSTANCE_ID])

        elif event['rawPath'].endswith('stop'):
            sqs.send_message(QueueUrl=SQS_URL, MessageBody='stop')
            reply = "Stop message sent !"

        elif event['rawPath'].endswith('status'):
            result = ec2.describe_instances(InstanceIds=[INSTANCE_ID])
            instance = result['Reservations'][0]['Instances'][0]
            state = instance['State']['Name']
            try:
                ip = instance['NetworkInterfaces'][0]['Association']['PublicIp']
                reply = '{} - {}:{}'.format(state, ip, '2456')
            except:
                reply = '{} - no IP yet'.format(state)
        else:
            reply = "start/stop/status plz..."

        return {
            'statusCode': 200,
            'body': reply
        }

    except Exception as exc:
        return {
                'statusCode': 404,
                'body': "Caca: {}".format(exc)
            }
