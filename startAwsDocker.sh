#!/bin/bash
#	awscli must be installed and working
# Required options: 
#	ami-name
#	key-name
# Optional options:
#	Aws region (implies running on AWS)
#	Aws instance type
#       Aws block mapping
# TBD
# create one ebs device per node
# determine instance size based on memory requested * number of nodes

# Sample Invocation with 24x 40GB EBS volumes for MapR
# ./startAwsDocker.sh -a 'alerner Docker CentOS 7.3 MEP 1-3 MapR 5.2.1-2' -k alerner-docker -b 24:40 -i m4.4xlarge
# ./startAwsDocker.sh -a 'MapR521SullexisDocker' -k alerner-sullexis -i m4.4xlarge

# Using AMI named 'alerner Docker CentOS 7.3 MEP 3 MapR 6.0' and 15x 21GB EBS Volumes, start instance named 'alerner-docker-6.0x15x21'
# ./startAwsDocker.sh -n 'alerner-docker-6.0x15x21' -a 'alerner Docker CentOS 7.3 MEP 3 MapR 6.0' -k alerner-docker -b 15:21 -i m4.2xlarge

# ./startAwsDocker.sh -n 'alerner-docker-6.0.20171016x15x21' -a 'alerner Docker CentOS 7.3 MEP 4.0.0 MapR 6.0.0' -k alerner-docker -b 15:21 -i m4.2xlarge
# for i in 1 2 3; do ./startAwsDocker.sh -a 'CentOS 7.3.1611' -k alerner-60cert-partner -n alerner${i}-6.0cert-sec-partner -i m4.4xlarge -s mapr-sg -t 6.0cert:alerner & done

awsRegion=default
awsRegionOpt=""
verbose=false
D_INSTTYPE=t2.xlarge; INSTTYPE=$D_INSTTYPE
D_AWS_SECGROUP=docker-sg; AWS_SECGROUP=$D_AWS_SECGROUP
# AWS_SECGROUP=jsun-sg
tagKeyArray=()
tagValueArray=()
blockMappingsFile=./blockMapTemp.json
subnetOpt=""

usage()
{
  echo " "
  echo "Usage: $(basename $BASH_SOURCE) "
  echo "         -a AMI Name            # AMI Name "
  echo "         -k AWS KeyPair         # AWS KeyPair to be used to access instance"
  echo "       [ -n Instance Name ]	# 'Name' Tag (default: iamuser-key-N)"
  echo "       [ -b drives:GB ]		# Add EBS block mapping (eg 5:100 for 5x 100GB drives)"
  echo "       [ -B Root volume GB]     # AWS /dev/sda1 root volume size (default: 8GB)"
  echo "       [ -i AWS Instance type ] # AWS Instance Type (default: $D_INSTTYPE)"
  echo "       [ -r AWS Region ]        # AWS Region if not using default region"
  echo "       [ -o "instances opts"]   # Additional AWS run-instances options"
  echo "       [ -t key:value ]         # AWS Instance tags (In addition to Name whic is set by default)"
  echo "       [ -s AWS Security Group] # AWS Security Group name (default: $D_AWS_SECGROUP"
  echo "       [ -S AWS Subnet Name/Id] # AWS Subnet Name or Id"
  # echo "       [ -v ]                   # Verbose output"
  echo " "
}


while getopts ":a:b:B:i:k:n:o:r:s:S:t:vh" OPTION
do
  case $OPTION in
    a)
      amiName="$OPTARG"
      ;;
    b)
      rm -f $blockMappingsFile
      volumeType=gp2	# Hard coded volume type for now

      blockMapping="$OPTARG"
      driveCnt=${blockMapping%:*}
      driveGb=${blockMapping#*:}


      re='^[0-9]+$'
      if [[ ! $driveCnt =~ $re ]] || [[ ! $driveGb =~ $re ]] ; then
        echo "Invalid -b argument '$blockMapping'"
	exit
      fi
      ;;
    B)
      rm -f $blockMappingsFile
      volumeType=gp2	# Hard coded volume type for now

      rootDriveGb=$OPTARG

      re='^[0-9]+$'
      if [[ ! $rootDriveGb =~ $re ]] ; then
        echo "Invalid -V argument 'rootDriveGb'"
	exit
      fi
      ;;
    i)
      INSTTYPE=$OPTARG
      ;;
    k)
      keyName=$OPTARG
      ;;
    n)
      nameTag=$OPTARG
      ;;
    o)
      otherAwsInstanceOpts="$OPTARG"
      ;;
    r)
      awsRegion=$OPTARG
      awsRegionOpt="--region $awsRegion"
      ;;
    s)
      AWS_SECGROUP=$OPTARG
      ;;
    S)
      AWS_SUBNET="$OPTARG"
      ;;
    t)
      instanceTag="$OPTARG"
      tagKey=${instanceTag%:*}
      tagValue=${instanceTag#*:}
      if [[ -z $tagKey ]] || [[ -z $tagValue ]] || [[ $tagKey = $tagValue ]] ; then
        echo "Invalid tag (-t) argument '$instanceTag'"
	exit
      fi
      tagKeyArray+=("$tagKey")
      tagValueArray+=("$tagValue")
      ;;
    v)
      verbose=true
      ;;
    h)
      usage
      exit
      ;;
    *)
      usage "Invalid argument: $OPTARG"
      exit 1
      ;;
  esac
done

if [[ -z $amiName ]]; then
  echo "No AMI Name specified with -a option.  Select AMI from:"
  aws ec2 describe-images $awsRegionOpt --owners self --query 'Images[*].{Name:Name}' --output text | sort | uniq
  usage
  exit
fi

if [[ -z $keyName ]]; then
  echo "No KeyPair Name specified with -k option.  Select KeyPair from:"
  aws ec2 describe-key-pairs $awsRegionOpt --query 'KeyPairs[*].{KeyName:KeyName}' --output text | sort | uniq
  usage
  exit
fi

blockMappings=" "

if [[ ! -z $blockMapping ]] || [[ ! -z $rootDriveGb ]] ; then
  if [[ ! -z $rootDriveGb ]] ; then
    # Create block mappings file
    echo "[" > $blockMappingsFile
    echo "  {" >> $blockMappingsFile
    echo "    \"DeviceName\": \"/dev/sda1\"," >> $blockMappingsFile
    echo "    \"Ebs\": {" >> $blockMappingsFile
    echo "      \"DeleteOnTermination\": true," >> $blockMappingsFile
    echo "      \"VolumeSize\": $rootDriveGb," >> $blockMappingsFile
    echo "      \"VolumeType\": \"$volumeType\"" >> $blockMappingsFile
    echo "    }" >> $blockMappingsFile
  fi
  # /dev/sda is root volume.  /dev/sdz is docker volume.
  #driveLetter=(a b c d e f g h i j k l m n o p q r s t u v w x y )
  drive=(sda sdb sdc sdd sde xvdf xvdg xvdh sdi sdj sdk sdl sdm sdn sdo sdp sdq sdr sds sdt sdu sdv sdw sdx sdy )
  if [[ ! -z $blockMapping ]] ; then
    if [[ -f $blockMappingsFile ]] ; then
      echo "  }," >> $blockMappingsFile
    else
      echo "[" > $blockMappingsFile
    fi
    for i in $(eval echo {1..$driveCnt}); do
      echo "  {" >> $blockMappingsFile
      echo "    \"DeviceName\": \"/dev/${drive[$i]}\"," >> $blockMappingsFile
      echo "    \"Ebs\": {" >> $blockMappingsFile
      echo "      \"DeleteOnTermination\": true," >> $blockMappingsFile
      echo "      \"VolumeSize\": $driveGb," >> $blockMappingsFile
      echo "      \"VolumeType\": \"$volumeType\"" >> $blockMappingsFile
      echo "    }" >> $blockMappingsFile
  
      if [[ $i -lt $driveCnt ]] ; then
        echo "  }," >> $blockMappingsFile
      fi
    done
  fi

  echo "  }" >> $blockMappingsFile
  echo "]" >> $blockMappingsFile

  blockMappings="--block-device-mappings file://$blockMappingsFile"
fi

# Remove counterFile to reset counter to 0.  Auto resets at 100.
counterFile=./counterFile
cntr=0
[[ -f $counterFile ]] && cntr=$(cat $counterFile)
[[ $cntr -gt 99 ]] && cntr=0
echo ${cntr}+1 | bc > $counterFile

iamUserName=$(aws iam get-user | python -c 'import sys, json; print json.load(sys.stdin)["User"]["UserName"]')

#AMI=ami-d2c924b2	# CentOS Linux 7 x86_64 HVM EBS 1602	us-west-2 FROM MARKETPLACE, CANNOT MAKE PUBLIC!
#AMI=ami-c80015b1	# James' CentOS Linux 7.1 x86_64 us-west-2 NOT FROM MARKETPLACE, CAN MAKE PUBLIC!
#AMI=ami-c78666bf		# CentOS Linux 7.3.1611 us-west-2 not from Marketplace.  

#amiName='CentOS 7.3.1611'	# CentOS Linux 7.3.1611 us-west-2 not from Marketplace.  
#AMI=ami-ab01e1d3				# CentOS Linux 7.3.1611 from Packer with Docker setup us-west-2 from ami-c78666bf.  

#amiName='alerner Docker CentOS 7.3.1611'	# CentOS Linux 7.3.1611 from Packer with Docker setup us-west-2 from ami-c78666bf.  
#AMI=ami-bcfbe2c5	# MapR 5.2.1 with MEP 3.0.0 FS 5 nodes SSD

#AMI=ami-59bc5a21	# Sullexis Demo Final - ElasticSearch data symlinked to MapR - Oregon
#AMI=ami-a07e55c0	# Sullexis Demo Final - ElasticSearch data symlinked to MapR - N California
#amiName=MapR521SullexisDocker
#ami-3fc5ee5f

#AMI=ami-6a15760a	# VORA Hortonworks AMI.  Not for use in this script.  Just documented here.
#			# vCPU	Mem	OR$/Hr
#INSTTYPE=t2.xlarge	#   4	 16	0.188
#INSTTYPE=m4.4xlarge	#  16	 64	0.80
#INSTTYPE=c4.8xlarge	#  36	 60	1.591
#INSTTYPE=m4.10xlarge	#  40	160	2.00 (Sullexis)
#INSTTYPE=m4.16xlarge	#  64	256	3.20
#INSTTYPE=r4.16xlarge	#  64	488	4.256
#awsRegion=us-west-2
#awsRegion=us-west-1

#keyName=alerner-docker
#keyName=alerner
#keyName=alerner-vora-sap
#keyName=alerner-sullexis
#keyName=alerner-enterprisedb

# If key pair is not found in region, import it
# aws ec2 describe-key-pairs $awsRegionOpt --key-names $keyName --query 'KeyPairs[*].{KeyName:KeyName}'  --output text

#if ! aws ec2 describe-key-pairs $awsRegionOpt --key-names alerner-docker > /dev/null 2>&1; then 
#  #PUBLIC_KEY=$(openssl rsa -in ${keyName}.pem -pubout 2>/dev/null | grep -v 'PUBLIC KEY')
#  #PUBLIC_KEY=${PUBLIC_KEY//[$'\n']}
#  PUBLIC_KEY=$(ssh-keygen -y -f ${keyName}.pem | cut -f2 -d ' ')
#  aws ec2 import-key-pair $awsRegionOpt --key-name $keyName --public-key-material $PUBLIC_KEY
#fi


# If security group is not found in region, create it.  Only need port 22 for ssh.  Tunnel web proxy port 3128 through ssh:
#	ssh -i ${keyName}.pem -L 3128:localhost:3128 centos@$AWSIP
# aws ec2 describe-security-groups $awsRegionOpt --query 'SecurityGroups[].{Name:GroupName}' --output text | grep "^${AWS_SECGROUP}$" ; then

### echo "aws ec2 describe-security-groups $awsRegionOpt --group-names $AWS_SECGROUP" 
### aws ec2 describe-security-groups $awsRegionOpt --group-names $AWS_SECGROUP
### exit

awsVpcFilter=""
# If a subnet is specified, get the VPC and set vpcFilter
if [[ ! -z $AWS_SUBNET ]]; then
  # If AWS_SUBNET is an ID, set AWS_SUBNET_ID
  if [[ $AWS_SUBNET =~ ^subnet-([0-9a-f]{8})$ ]] ; then
    AWS_SUBNET_ID=$AWS_SUBNET
  else
    # AWS_SUBNET is a Tag Value.  Get the Subnet ID.
    AWS_SUBNET_ID=$(aws ec2 describe-subnets $awsRegionOpt| jq -r ".Subnets[] | select(.Tags[]?.Value==\"$AWS_SUBNET\") | .SubnetId")
  fi
  if [[ -z $AWS_SUBNET_ID ]] ; then
    echo "No Subnet tagged with \"$AWS_SUBNET\" in $awsRegionOpt"
    exit
  fi
  # set vpcOpt
  AWS_VPC_ID=$(aws ec2 describe-subnets $awsRegionOpt | jq -r ".Subnets[] | select(.SubnetId==\"$AWS_SUBNET_ID\") | .VpcId")
  awsVpcFilter="--filters Name=vpc-id,Values=\"$AWS_VPC_ID\""
  subnetOpt="--subnet-id $AWS_SUBNET_ID"
fi

# Get security group Id from name
AWS_SECGROUP_ID=$(aws ec2 describe-security-groups  $awsRegionOpt $awsVpcFilter | jq -r ".SecurityGroups[] | select(.GroupName==\"$AWS_SECGROUP\") | .GroupId ")

if [[ -z $AWS_SECGROUP_ID ]] ; then
  # for now, uses default VPC if sec group is created
  aws ec2 create-security-group $awsRegionOpt --group-name $AWS_SECGROUP --description "Security group for docker hosts (ssh only)"
  aws ec2 authorize-security-group-ingress $awsRegionOpt --group-name $AWS_SECGROUP --protocol tcp --port 22 --cidr 0.0.0.0/0 
  # Get Id and create tag
  AWS_SECGROUP_ID=$(aws ec2 describe-security-groups $awsRegionOpt --group-names $AWS_SECGROUP --query 'SecurityGroups[0].{GroupId:GroupId}' --output text)
  aws ec2 create-tags $awsRegionOpt --resources  $AWS_SECGROUP_ID --tags Key=Name,Value="${iamUserName} $AWS_SECGROUP"
fi

# Get AMI Image ID from amiName
AMI=$(aws ec2 describe-images --owners self --query 'Images[*].{Name:Name,ImageId:ImageId}' --output text \
        | grep "[[:space:]]${amiName}$" \
        | sed -e 's/[[:space:]].*$//')
#AMI=$(aws ec2 describe-images $awsRegionOpt --owners self --query 'Images[*].{Name:Name,ImageId:ImageId}' --output text \
#        | grep "\t${amiName}$" \
#	| cut -f 1 -d $'\t')


# AMIs can have duplicate names.  Warn if multiples found but still start with one anyway.
let amiCount="$(echo $AMI | wc -w)"
if [[ $amiCount -gt 1 ]] ; then
  echo "Warning:  Multiple AMIs in region '$awsRegion' with name '$amiName': "
  for nextAMI in $AMI; do
    echo "            $nextAMI"
  done
  AMI=$(echo $AMI | cut -f1 -d' ')
  echo "          Using AMI '$AMI'"
fi

instanceIdFile=./instance_ids.$$
#aws ec2 describe-images --image-ids $AMI
if ! aws ec2 run-instances \
  $awsRegionOpt \
  $otherAwsInstanceOpts \
  --image-id $AMI \
  $subnetOpt \
  --security-group-ids $AWS_SECGROUP_ID \
  --count 1 \
  --instance-type $INSTTYPE \
  --key-name $keyName \
   $blockMappings \
   --query 'Instances[0].InstanceId' > $instanceIdFile
#  --security-groups $AWS_SECGROUP 
then
  echo "run-instances $amiName (amiId='$AMI') in $awsRegion failed"
  usage
  exit
fi

sed -i -e 's/"//g' $instanceIdFile
instanceId=$(cat $instanceIdFile)
cat $instanceIdFile >> ./instance_ids
rm -f $instanceIdFile

#
#

#instanceId=$(tail -1 ./instance_ids)
#aws ec2 create-tags --resources  $instanceId --tags Key=Name,Value=${iamUserName}-dockerhost${cntr}
#aws ec2 create-tags $awsRegionOpt --resources  $instanceId --tags Key=Name,Value=${iamUserName}-${keyName#alerner-}${cntr}
[[ -z $nameTag ]] && nameTag=${iamUserName}-${keyName#${iamUserName}-}-${cntr}
aws ec2 create-tags $awsRegionOpt --resources  $instanceId --tags Key=Name,Value=$nameTag
if [[ ! -z $tagKeyArray ]] ; then
  let tagIdx=0
  while [[ $tagIdx -lt ${#tagKeyArray[@]} ]]; do
    echo aws ec2 create-tags $awsRegionOpt --resources  $instanceId --tags Key=${tagKeyArray[$tagIdx]},Value=${tagValueArray[$tagIdx]}
    aws ec2 create-tags $awsRegionOpt --resources  $instanceId --tags Key=${tagKeyArray[$tagIdx]},Value=${tagValueArray[$tagIdx]}
    let tagIdx+=1
  done
fi

for instanceVolume in $(aws ec2 describe-instances $awsRegionOpt --instance-ids $instanceId | jq -r '.Reservations[].Instances[].BlockDeviceMappings[].Ebs.VolumeId') ; do
  aws ec2 create-tags $awsRegionOpt --resources $instanceVolume --tags Key=Name,Value=$nameTag
done

state=$(aws ec2 describe-instances $awsRegionOpt --instance-ids  $instanceId | python -c 'import sys, json; print json.load(sys.stdin)["Reservations"][0]["Instances"][0]["State"]["Name"]')
echo "$(date): $state"
while [[ $state != "running" ]]; do
  sleep 10
  state=$(aws ec2 describe-instances $awsRegionOpt --instance-ids  $instanceId | python -c 'import sys, json; print json.load(sys.stdin)["Reservations"][0]["Instances"][0]["State"]["Name"]')
  echo "$(date): $state"
done
while [[ $status != "ok" ]]; do
  sleep 10
  status=$(aws ec2 describe-instance-status $awsRegionOpt --instance-ids  $instanceId | python -c 'import sys, json; print json.load(sys.stdin)["InstanceStatuses"][0]["InstanceStatus"]["Status"]')
  echo "$(date): $status"
done
AWSIP=$(aws ec2 describe-instances $awsRegionOpt --instance-ids  $instanceId --query 'Reservations[0].Instances[0].PublicIpAddress' | sed -e 's/"//g')
echo AWSIP=$AWSIP

echo "ssh -i $keyName.pem -L 3128:localhost:3128 centos@\$AWSIP"

#aws ec2 terminate-instances $awsRegionOpt --instance-ids $instanceId


#keyName=sun; aws ec2 describe-instances | jq -r ".\"Reservations\"[].\"Instances\"[] | select(.\"KeyName\"==\"$keyName\")| select(.\"State\".\"Code\"==16) | \"$keyName \" + \" \" +.\"LaunchTime\" +\" \"+ .\"InstanceId\"+ \" \" + .\"Placement\".\"AvailabilityZone\" + \" \" + .\"InstanceType\" "
