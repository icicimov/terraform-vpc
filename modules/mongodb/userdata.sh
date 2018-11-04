#!/bin/bash -ex

function nextLetter () {
    local Letters="abcdefghijklmnopqrstuvwxyz"
    echo $${Letters:$$1:1}
}

mongos_region=${MONGOS_REGION}
mongos_env=${MONGOS_ENV}
mydb_rs_name=${mydb_RSNAME}
mydb_volume_device=${mydb_VDEVICE}
mydb_volume_device2=${mydb_VDEVICE2}
mydb_mount_point=${mydb_VMOUNT}
mydb_ephemeral0_device=${mydb_EDEVICE}
es_cluster_name=${ES_CLUSTER_NAME}
es_cluster_setup=${ES_CLUSTER_SETUP}

rm -rf /var/lib/apt/lists/*
sed -e '/^deb.*security/ s/^/#/g' -i /etc/apt/sources.list

export DEBIAN_FRONTEND=noninteractive
apt-get update -y -m -qq && apt-get upgrade -y -m -qq
apt-get -y install build-essential libssl-dev libffi-dev \
  python-setuptools python-dev python-crypto python-markupsafe \
  python-yaml python-jinja2 python-httplib2 python-keyczar \
  python-paramiko python-pkg-resources python-pip git aptitude \
  wget curl software-properties-common jq unzip curl bc xfsprogs

wget https://bootstrap.pypa.io/get-pip.py
python ./get-pip.py

pip install --upgrade --force-reinstall awscli --install-option="--install-scripts=/usr/local/bin"
echo "Python Tools and awscli installed" - `date` >> /tmp/userdata.log

echo "Setting up sudo tty console" >> /tmp/userdata.log
sed -i 's,Defaults    requiretty,#Defaults    requiretty,g' /etc/sudoers

#
# Autodiscover
#
HOSTNAME=$(hostname -f)
URL="http://169.254.169.254/latest/"
ID=$(curl -s $URL/meta-data/instance-id)
REGION=$(curl -s $URL/dynamic/instance-identity/document | jq -r '.region')
IP=$(curl -s $URL/meta-data/local-ipv4)
ZONE=$(curl -s $URL/dynamic/instance-identity/document | jq -r '.availabilityZone')
ZONE_SUFF="$${ZONE:$(($${#ZONE}-1)):1}"
ASG_NAME=$(aws autoscaling describe-auto-scaling-instances \
--region $REGION --instance $ID \
--query 'AutoScalingInstances[0].AutoScalingGroupName' \
--output text)
BOOTSTRAP_EXPECT=$(aws autoscaling describe-auto-scaling-groups --region $REGION | \
   jq -c -M -r '.AutoScalingGroups[] | {name: .AutoScalingGroupName, desired_capacity: .DesiredCapacity}' | \
   grep $ASG_NAME | jq -c -M -r '.desired_capacity' | tr -d "\n")
SERVERS=''

while [ $(echo "$SERVERS" | wc -l) -lt $BOOTSTRAP_EXPECT ]; do
   SERVERS=$(aws ec2 describe-instances --region $REGION --instance-ids $(aws autoscaling describe-auto-scaling-groups \
      --region $REGION --auto-scaling-group-name $ASG_NAME --query 'AutoScalingGroups[0].Instances[].InstanceId' \
      --output text) --query 'Reservations[].Instances[].{PrivateIpAddress:PrivateIpAddress}' --output text); done

echo "MongoDB instances found:" $SERVERS | tee -a /tmp/mongo.log
ngservers=$(echo "$SERVERS" | wc -w)
# elect the first one for master to be
mongo_server_is_master=$(echo $SERVERS | cut -d" " -f1)

#
# Start Mongo installation and setup
#

## Waiting for EBS mounts to become available
while [ ! -e $mydb_volume_device ]; do echo "waiting for $mydb_volume_device to attach" | tee -a /tmp/mongo.log; sleep 10; done
while [ ! -e $mydb_volume_device2 ]; do echo "waiting for $mydb_volume_device2 to attach" | tee -a /tmp/mongo.log; sleep 10; done

## Set read-ahead and the i/o scheduler for each device\n",
blockdev --setra 32 $mydb_volume_device
blockdev --setra 32 $mydb_volume_device2
l1=$${mydb_volume_device:$(($${#mydb_volume_device}-1)):1}
l2=$${mydb_volume_device2:$(($${#mydb_volume_device2}-1)):1}
echo 'ACTION=="add", KERNEL=="xvd['$l1$l2']", ATTR{bdi/read_ahead_kb}="16", ATTR{queue/scheduler}="noop"' | tee -a /etc/udev/rules.d/85-ebs.rules
echo noop | tee /sys/block/xvd{$l1,$l2}/queue/scheduler

## Partition the drives
dd if=/dev/zero of=$mydb_volume_device bs=512 count=1
dd if=/dev/zero of=$mydb_volume_device2 bs=512 count=1
dd if=/dev/zero of=$mydb_ephemeral0_device bs=512 count=1

## Create swap
[[ $mydb_ephemeral0_device ]] && umount -f $mydb_ephemeral0_device \
&& mkswap -f $mydb_ephemeral0_device \
&& swapon $mydb_ephemeral0_device \
&& sed "s,^$mydb_ephemeral0_device.*$,$mydb_ephemeral0_device       none   swap    sw      0       0," -i /etc/fstab

## Create physical and logical volumes
apt-get install -y --force-yes --install-recommends lvm2 xfsprogs
pvcreate $mydb_volume_device $mydb_volume_device2
vgcreate vg_mydb $mydb_volume_device $mydb_volume_device2
lvcreate -i 2 -I 256 --name lv_mydb -l 100%vg vg_mydb

## Create filesystems and mount points
mkfs -t xfs -L mydb /dev/vg_mydb/lv_mydb
[[ ! -d $mydb_mount_point ]] && mkdir -p $mydb_mount_point
echo "LABEL=mydb $mydb_mount_point xfs auto,noatime,noexec,nodiratime 0 0" | tee -a /etc/fstab  
mount LABEL=mydb

## Install Mongodb-3.0
apt-key -y adv --keyserver hkp://keyserver.ubuntu.com:80 --recv 7F0CEB10
echo "deb http://repo.mongodb.org/apt/ubuntu trusty/mongodb-org/3.0 multiverse" | tee /etc/apt/sources.list.d/mongodb-org-3.0.list
apt-get update -y --force-yes
apt-get install -y --force-yes --install-recommends mongodb-org

## Route53 records ##
# Insert/Update Route53 internal zone DNS record
cat > /root/record.json <<END
{
  "Comment": "Mongo Route53 internal zone record",
  "Changes": [
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "mydb$${ZONE_SUFF}.${domain}",
        "Type": "A",
        "TTL": 10,
        "ResourceRecords": [
          {
            "Value": "$${IP}"
          }
        ]
      }
    }
  ]
}
END
cat > /root/record2.json <<END
{
  "Comment": "Mongo Route53 internal zone SRV record",
  "Changes": [
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "mydb.${domain}",
        "Type": "SRV",
        "TTL": 10,
        "ResourceRecords": [
END
i=0
while [[ $i -le $(($${ngservers} - 1)) ]]
do
cat >> /root/record2.json <<END
          {
            "Value": "1 1 27017 mydb$(nextLetter $i).${domain}"
          }
END
if [[ $i -lt $(($${ngservers} - 1)) ]]
then
cat >> /root/record2.json <<END
          ,
END
fi
        i=$((i+1))
done
cat >> /root/record2.json <<END
        ]
      }
    } 
  ]
}
END
cat > /root/record3.json <<END
{
  "Comment": "Mongo Route53 internal zone record",
  "Changes": [
END
i=0
while [[ $i -le $(($${ngservers} - 1)) ]]
do
cat >> /root/record3.json <<END
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "mydb.${domain}",
        "Type": "A",
        "SetIdentifier": "tftest_mydb_wrr_$(nextLetter $i)",
        "Weight": 100,
        "AliasTarget": {
          "HostedZoneId": "${zone_id}",
          "DNSName": "mydb$(nextLetter $i).${domain}",
          "EvaluateTargetHealth": true
        }
      }
    }
END
if [[ $i -lt $(($${ngservers} - 1)) ]]
then
cat >> /root/record3.json <<END
    ,
END
fi
    i=$((i+1))
done
cat >> /root/record3.json <<END
  ]
}
END

aws route53 change-resource-record-sets --hosted-zone-id "${zone_id}" --change-batch file:///root/record.json | tee -a /tmp/userdata.log
aws route53 change-resource-record-sets --hosted-zone-id "${zone_id}" --change-batch file:///root/record2.json | tee -a /tmp/userdata.log
aws route53 change-resource-record-sets --hosted-zone-id "${zone_id}" --change-batch file:///root/record3.json | tee -a /tmp/userdata.log

## PROVISION THE CLUSTER VIA ANSIBLE ##

sed -e '/^#deb.*security/ s/^#//g' -i /etc/apt/sources.list
exit 0