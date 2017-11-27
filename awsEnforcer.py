#!/usr/bin/python3
#
# Validate AWS naming conventions for Alliances Engineering instances and volumes.
#
# Requirements:
#   AWS CLI installed and aws environment set up with key for AWS account
#   Python3
#   AWS boto3 module
#
# Usage: awsEnforcer.py
# Author: Andy Lerner
#
# Examples:
#   Enforce naming convention for all instances and volumes in all regions on AWS account
#     awsEnforcer.py

import boto3

validNames=['abarth','aengel','alerner','greeves','jsun','mmangal','mrabne']

def print_instance_60(instance, 
                   region, 
		   msg='6.0 Certification Instances containing "6.0cert" tag:'):
  if print_instance_60.firstTime:
    print("\n"+msg)
    print_instance_60.firstTime=False
    print(
      "Region".ljust(16), 
      "Name".ljust(24),
      "6.0cert".ljust(16),
      "Instance Id".ljust(24),
      "Launch Date".ljust(12), 
      "Type".ljust(12), 
      "State".ljust(14), 
      "Key".ljust(24)
      )
    print(
      "------".ljust(16), 
      "----".ljust(24),
      "-------".ljust(16),
      "-----------".ljust(24),
      "-----------".ljust(12), 
      "----".ljust(12), 
      "-----".ljust(14), 
      "---".ljust(24)
      )
  print (
    region.ljust(16),
    instance['Name'].ljust(24)[:24],
    instance['6.0cert'].ljust(16)[:16],
    instance['InstanceId'].ljust(24), 
    instance['LaunchTime'].strftime("%Y-%m-%d").ljust(12),
    instance['InstanceType'].ljust(12), 
    instance['State']['Name'].ljust(14),
    instance['KeyName'].ljust(24)
    )
print_instance_60.firstTime=True

def print_instance(instance, 
                   region, 
		   msg='The following instances do not have a valid user name in the "Name" tag:'):
  if print_instance.firstTime:
    print("\n"+msg)
    print_instance.firstTime=False
    print(
      "Region".ljust(16), 
      "Name".ljust(24),
      "Instance Id".ljust(24),
      "Launch Date".ljust(12), 
      "Type".ljust(12), 
      "State".ljust(14), 
      "Key".ljust(24)
      )
    print(
      "------".ljust(16), 
      "----".ljust(24),
      "-----------".ljust(24),
      "-----------".ljust(12), 
      "----".ljust(12), 
      "-----".ljust(14), 
      "---".ljust(24)
      )
  print (
    region.ljust(16),
    instance['Name'].ljust(24)[:24],
    instance['InstanceId'].ljust(24), 
    instance['LaunchTime'].strftime("%Y-%m-%d").ljust(12),
    instance['InstanceType'].ljust(12), 
    instance['State']['Name'].ljust(14),
    instance['KeyName'].ljust(24)
    )
print_instance.firstTime=True

def print_volume(volume, 
                 region, 
		 msg='The following volumes do not have a valid user name in the "Name" tag:'):
  if print_volume.firstTime:
    print("\n"+msg)
    print_volume.firstTime=False
    print(
      "Region".ljust(16), 
      "Name".ljust(24),
      "Volume Id".ljust(24),
      "Create Date".ljust(12),
      #"Attached Instance".ljust(24),
      "State".ljust(16),
      "Size GB".rjust(8)
      )
    print(
      "------".ljust(16), 
      "----".ljust(24),
      "---------".ljust(24),
      "-----------".ljust(12),
      #"-----------------".ljust(24),
      "-----".ljust(16),
      "-------".rjust(8)
      )
  if not volume['Attachments']:
    volume['Attached']='Unattached'
  else:
    instance=ec2resource.Instance(volume['Attachments'][0]['InstanceId'])
    for dict in instance.tags:
      if dict['Key'] == 'Name':
        volume['Attached']=dict['Value']
        break
    if not volume['Attached']:
      volume['Attached']=volume['Attachments'][0]['InstanceId']
  print (
    region.ljust(16),
    volume['Name'].ljust(24)[:24],
    volume['VolumeId'].ljust(24),
    volume['CreateTime'].strftime("%Y-%m-%d").ljust(12),
    #volume['Attached'].ljust(24)[:24], 
    volume['State'].ljust(16),
    "{:>8d}".format(volume['Size'])
    )
print_volume.firstTime=True

def get_region_names():
  global regionNames
  ec2 = boto3.client('ec2')
  regions=ec2.describe_regions()
  regionNames = [ dict['RegionName'] for dict in regions['Regions'] ]


def check_instance_names():
  global instancesInCompliance
  for regionName in regionNames:
    ec2 = boto3.client('ec2', region_name=regionName)
    # New script or options to filter old running instances...
    # aws ec2 describe-instances --query 'Reservations[].Instances[?LaunchTime>=`2017-01-01`][].{id: InstanceId, type: InstanceType, launched: LaunchTime}'
    instancesList=ec2.describe_instances(
      #Filters=[{'Name': 'instance-state-name', 'Values': ['running']}])['Reservations'] 
      #Filters=[{'Name': 'launch-time', 'Values': ['running']}]
      )['Reservations'] 
    for elem in instancesList:
      for instance in elem['Instances']:
        if 'Tags' in instance:
          for dict in instance['Tags']:
            if dict['Key'] == 'Name':
              #instanceName=dict['Value']
              instance['Name']=dict['Value']
        if 'Name' not in instance:
          instance['Name']='Unnamed'
        nameNotValid=True
        keyNotValid=True
        for name in validNames:
          if name in instance['Name']:
            nameNotValid=False
          if name in instance['KeyName']:
            keyNotValid=False
        if nameNotValid:
          instancesInCompliance=False
          print_instance(instance, regionName)

def check_instance_names_60():
  global instancesInCompliance
  for regionName in regionNames:
    ec2 = boto3.client('ec2', region_name=regionName)
    # New script or options to filter old running instances...
    # aws ec2 describe-instances --query 'Reservations[].Instances[?LaunchTime>=`2017-01-01`][].{id: InstanceId, type: InstanceType, launched: LaunchTime}'
    instancesList=ec2.describe_instances(
      #Filters=[{'Name': 'instance-state-name', 'Values': ['running']}])['Reservations'] 
      #Filters=[{'Name': 'launch-time', 'Values': ['running']}]
      )['Reservations'] 
    for elem in instancesList:
      for instance in elem['Instances']:
        is60CertInstance=False
        if 'Tags' in instance:
          for dict in instance['Tags']:
            if dict['Key'] == 'Name':
              #instanceName=dict['Value']
              instance['Name']=dict['Value']
            if dict['Key'] == '6.0cert':
              instance['6.0cert']=dict['Value']
              is60CertInstance=True
        if 'Name' not in instance:
          instance['Name']='Unnamed'
        instancesInCompliance=False
        if is60CertInstance:
          print_instance_60(instance, regionName)

def check_volume_names():
  global ec2resource
  global volumesInCompliance
  for regionName in regionNames:
    ec2 = boto3.client('ec2', region_name=regionName)
    ec2resource = boto3.resource('ec2', region_name=regionName)
    volumes=ec2.describe_volumes(
      Filters=[{'Name': 'status', 'Values': ['available']}])['Volumes']
    for volume in volumes:
      if 'Tags' in volume:
        for dict in volume['Tags']:
          if dict['Key'] == 'Name':
            volume['Name']=dict['Value']
      if 'Name' not in volume:
        volume['Name'] = 'Unnamed'
      nameNotValid=True
      for name in validNames:
        if name in volume['Name']:
          nameNotValid=False
      if nameNotValid:
        volumesInCompliance=False
        msg='The following available volumes do not have a valid user name in the "Name" tag:'
        print_volume(volume, regionName, msg)

### MAIN ###

volumesInCompliance=True
instancesInCompliance=True

get_region_names()
#Debugging ...
#regionNames = ['us-east-1', 'us-east-2', 'us-west-2']
#regionNames = ['us-east-1']
#regionNames = ['us-west-1']

#import datetime
#today = datetime.datetime.today()
reportName='AWS Instance and Volume Naming Report'
#print (today.strftime(reportName + ' as of %b %d, %Y at %-I:%M %p %Z'))

import os
now=os.popen("date").read()
print (reportName + ' as of '+ now)

#print ("\nINSTANCES")
print ("INSTANCES")
check_instance_names()
if instancesInCompliance:
  print("\nAll AWS instances are tagged with one of these valid user names:\n")
  for validName in validNames:
    print ("  "+validName)

check_instance_names_60()

print ("\nVOLUMES")
check_volume_names()
if volumesInCompliance: 
  print("\nAll AWS available volumes are tagged with one of these valid user names:\n")
  for validName in validNames:
    print ("  "+validName)

'''
if volumesInCompliance and instancesInCompliance:
  print("All AWS instances and available volumes are tagged with one of these valid user names:"+"\n")
  for validName in validNames:
    print ("  "+validName)

'''
