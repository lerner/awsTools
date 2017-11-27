#!/opt/local/bin/python3
#
# List aws instances and let user select one to log in to
# Assumes:
#  User centos
#  .pem file name matches instance key 
#  Instance name includes string in validNames list
#
# Requirements:
#   AWS CLI installed and aws environment set up with key for AWS account
#   Python3
#   AWS boto3 module
#
# Usage: awsConnect.py
# Author: Andy Lerner
#
# Examples:
#

import boto3

validNames=['alerner','other']

def get_region_names():
  global regionNames
  ec2 = boto3.client('ec2')
  regions=ec2.describe_regions()
  regionNames = [ dict['RegionName'] for dict in regions['Regions'] ]


def list_instances():
  global instancesInCompliance
  for regionName in regionNames:
    # Skipping non-US regions for speed
    if regionName[:2] != 'us':
      continue
    print(regionName)
    ec2 = boto3.client('ec2', region_name=regionName)
    # New script or options to filter old running instances...
    # aws ec2 describe-instances --query 'Reservations[].Instances[?LaunchTime>=`2017-01-01`][].{id: InstanceId, type: InstanceType, launched: LaunchTime}'
    instancesList=ec2.describe_instances(
      Filters=[{'Name': 'instance-state-name', 'Values': ['running']}]
      #Filters=[{'Name': 'launch-time', 'Values': ['running']}]
      )['Reservations'] 
    instanceKeys=['Name', 'PublicIpAddress','InstanceId','KeyName']
    instanceIndex=0
    sshcmd={}
    sshcmdN={}
    for elem in instancesList:
          for instance in elem['Instances']:
              if 'Tags' in instance:
                for dict in instance['Tags']:
                  if dict['Key'] == 'Name':
                    instance['Name']=dict['Value']
              if 'Name' not in instance:
                instance['Name']='Unnamed'
              for name in validNames:
                if name in instance['Name']:
                  instanceIndex+=1
                  sshcmd[instanceIndex]="ssh -i "+(instance['KeyName']+".pem").ljust(30)+" centos@"+instance['PublicIpAddress']
                  sshcmdN[instance['Name']]="ssh -i "+(instance['KeyName']+".pem").ljust(30)+" centos@"+instance['PublicIpAddress']
                  print(str(instanceIndex).rjust(2),end=" ")
                  for nextKey in instanceKeys:
                      print(instance[nextKey].ljust(35),end="\t")
                  print("")
    for i in range(1,instanceIndex+1):
      print(str(i).rjust(2)+" "+sshcmd[i])
    for name in sshcmdN:
      print((name+":").ljust(35)+sshcmdN[name])

### MAIN ###

get_region_names()
#Debugging ...
#regionNames = ['us-east-1', 'us-east-2', 'us-west-2']
#regionNames = ['us-east-1']
#regionNames = ['us-west-2']

list_instances()
