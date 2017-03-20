#!/bin/bash -v
set -ex

echo iptables-persistent iptables-persistent/autosave_v4 boolean true | debconf-set-selections
echo iptables-persistent iptables-persistent/autosave_v6 boolean true | debconf-set-selections
rm -rf /var/lib/apt/lists/*
sed -e '/^deb.*security/ s/^/#/g' -i /etc/apt/sources.list
export DEBIAN_FRONTEND=noninteractive
apt-get update -y -m -qq && apt-get upgrade -y -m -qq
apt-get -y --force-yes install awscli conntrack iptables-persistent nfs-common jq unzip curl > /tmp/bastion.log 
[[ -s $(modinfo -n ip_conntrack) ]] && modprobe ip_conntrack && echo ip_conntrack | tee -a /etc/modules
/sbin/sysctl -w net.ipv4.conf.eth0.send_redirects=0
/sbin/sysctl -w net.netfilter.nf_conntrack_max=131072
echo "net.ipv4.conf.eth0.send_redirects=0" >> /etc/sysctl.conf
echo "net.netfilter.nf_conntrack_max=131072" >> /etc/sysctl.conf
/sbin/iptables -A INPUT -m state --state INVALID -j DROP
/sbin/iptables -A FORWARD -m state --state INVALID -j DROP
/sbin/iptables -A INPUT -p tcp --syn -m limit --limit 5/s -i eth0 -j ACCEPT
/sbin/iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
sleep 1

cat > /etc/profile.d/user.sh <<END
HISTSIZE=1000
HISTFILESIZE=40000
HISTTIMEFORMAT="[%F %T %Z] "
export HISTSIZE HISTFILESIZE HISTTIMEFORMAT
END

# Instance Metadata
HOSTNAME=$(hostname -f)
URL="http://169.254.169.254/latest"
ID=$(curl -s $URL/meta-data/instance-id)
REGION=$(curl -s $URL/dynamic/instance-identity/document | jq -r '.region')
IP=$(curl -s $URL/meta-data/local-ipv4)
STS_IAM_ARN=$(curl -s $URL/meta-data/iam/info | jq -c -M -r '.InstanceProfileArn')

# Insert/Update Route53 internal zone DNS record
cat > /root/record.json <<END
{
  "Comment": "Bastion Route53 internal zone record",
  "Changes": [
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "bastion.${domain}",
        "Type": "A",
        "TTL": 30,
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

aws route53 change-resource-record-sets --hosted-zone-id "${zone_id}" --change-batch file:///root/record.json | tee -a /tmp/bastion.log

sed -e '/^#deb.*security/ s/^#//g' -i /etc/apt/sources.list
exit 0
