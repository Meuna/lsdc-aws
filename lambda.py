import os
import json
import boto3

INSTANCE_ID = os.environ['INSTANCE_ID']
SQS_URL = os.environ['SQS_URL']

ec2 = boto3.client('ec2')
sqs = boto3.client('sqs')

def lambda_handler(event, context):
    try:
        if event['rawPath'].endswith('start'):
            ec2.start_instances(InstanceIds=[INSTANCE_ID])
            return {
                'statusCode': 200,
                'body': "Instance is starting..."
            }
        elif event['rawPath'].endswith('stop'):
            sqs.send_message(QueueUrl=SQS_URL, MessageBody='stop')
            return {
                'statusCode': 200,
                'body': "Stop message sent !"
            }
        elif event['rawPath'].endswith('status'):
            result = ec2.describe_instances(InstanceIds=[INSTANCE_ID])
            instance = result['Reservations'][0]['Instances'][0]
            state = instance['State']['Name']
            try:
                ip = instance['NetworkInterfaces'][0]['Association']['PublicIp']
                reply = '{} - {}:{}'.format(state, ip, '2456')
            except:
                reply = '{} - no IP yet'.format(state)
            
            return {
                'statusCode': 200,
                'body': reply
            }
        else:
            return {
                'statusCode': 200,
                'body': "start/stop/status plz..."
            }
    except Exception as exc:

        return {
                'statusCode': 404,
                'body': "Caca: {}".format(exc)
            }
