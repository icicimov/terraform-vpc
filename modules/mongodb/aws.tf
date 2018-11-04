/*=== MONGODB INSTANCES ===*/
variable "mydb" {
    type    = "map"
    default = {
        volume_size       = ""
        volume_type       = ""
        volume_device     = ""
        volume_device2    = ""
        volume_mount      = ""
        volume_encrypted  = false
        ephemeral0_device = ""
        rs_name           = ""
    }
}

variable "tag"      {}
variable "vpc_id"   {}
variable "cidr"     {}
variable "region"   {}
variable "image"    {}
variable "instance_type" {}
variable "key_name" {}
variable "zone_id"  {}
variable "domain"   {}
variable "zones" {
    type    = "list"
    default = []
}
variable "subnet_ids" {
    type    = "list"
    default = []
}

/* MONGO INSTANCES IN ASG */
resource "aws_autoscaling_group" "mongo" {
    name                      = "${var.tag}-mongo-${aws_launch_configuration.mongo.name}"
    availability_zones        = ["${var.zones}"]
    vpc_zone_identifier       = ["${var.subnet_ids}"]
    max_size                  = 3
    min_size                  = 3
    health_check_grace_period = 300
    default_cooldown          = 300
    health_check_type         = "EC2"
    desired_capacity          = 3
    force_delete              = true
    launch_configuration      = "${aws_launch_configuration.mongo.name}"
    tag {
      key                 = "Name"
      value               = "MONGO-${var.tag}"
      propagate_at_launch = true
    }
    tag {
      key                 = "Environment"
      value               = "${lower(var.tag)}"
      propagate_at_launch = true
    }
    tag {
      key                 = "Type"
      value               = "mongo"
      propagate_at_launch = true
    }
    tag {
      key                 = "Role"
      value               = "application-db,elasticsearch"
      propagate_at_launch = true
    }
    tag {
      key                 = "ASG"
      value               = "${var.tag}-mongo-asg-${aws_launch_configuration.mongo.name}"
      propagate_at_launch = true
    }
    lifecycle {
      create_before_destroy = true
    }
}

resource "aws_launch_configuration" "mongo" {
    name_prefix          = "${var.tag}-mongo-"
    image_id             = "${var.image}"
    instance_type        = "${var.instance_type}"
    iam_instance_profile = "${aws_iam_instance_profile.mongo.name}"
    key_name             = "${var.key_name}"
    security_groups      = ["${aws_security_group.mongo.id}"]
    user_data            = "${data.template_file.mongo.rendered}"
    ephemeral_block_device {
      device_name  = "${var.mydb["ephemeral0_device"]}"
      virtual_name = "ephemeral0"
    }
    ebs_block_device {
      device_name = "${var.mydb["volume_device"]}"
      volume_type = "${var.mydb["volume_type"]}"
      volume_size = "${var.mydb["volume_size"]}"
      encrypted   = "${var.mydb["volume_encrypted"]}"
    }
    ebs_block_device {
      device_name = "${var.mydb["volume_device2"]}"
      volume_type = "${var.mydb["volume_type"]}"
      volume_size = "${var.mydb["volume_size"]}"
      encrypted   = "${var.mydb["volume_encrypted"]}"
    }
    lifecycle {
      create_before_destroy = true
    }
}

data "template_file" "mongo" {
    template = "${file("${path.module}/userdata.sh")}"
    vars {
        MYDB_RSNAME   = "${var.mydb["rs_name"]}"
        MYDB_VDEVICE  = "${replace(var.mydb["volume_device"], "sd", "xvd")}"
        MYDB_VDEVICE2 = "${replace(var.mydb["volume_device2"], "sd", "xvd")}"
        MYDB_VMOUNT   = "${var.mydb["volume_mount"]}"
        MYDB_EDEVICE  = "${replace(var.mydb["ephemeral0_device"], "sd", "xvd")}"
        MONGOS_REGION = "${var.region}"
        MONGOS_ENV    = "${lower(var.tag)}"
        zone_id       = "${var.zone_id}"
        domain        = "${var.domain}"
    }
}

/*== MONGO INSTANCE IAM PROFILE ==*/
resource "aws_iam_instance_profile" "mongo" {
    name  = "${var.tag}-mongo-profile"
    role = "${aws_iam_role.mongo.name}"
    lifecycle {
      create_before_destroy = true
    }
}

resource "aws_iam_role" "mongo" {
    name               = "${var.tag}-mongo-role"
    path               = "/"
    assume_role_policy = "${data.aws_iam_policy_document.mongo.json}"
    lifecycle {
      create_before_destroy = true
    }
}

data "aws_iam_policy_document" "mongo" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "mongo-route53" {
  name   = "${var.tag}-mongo-role-policy"
  role   = "${aws_iam_role.mongo.id}"
  policy = "${data.aws_iam_policy_document.mongo-route53.json}"
}

data "aws_iam_policy_document" "mongo-route53" {
  statement {
    sid       = "Route53ListHostedZones"
    effect    = "Allow"
    resources = ["*"]
    actions   = [
      "route53:ListHostedZones"
    ]
  },
  statement {
    sid       = "Route53ChangeRecordSets"
    effect    = "Allow"
    resources = ["arn:aws:route53:::hostedzone/${var.zone_id}"]
    actions   = [
      "route53:ChangeResourceRecordSets",
      "route53:ListResourceRecordSets"
    ]
  },
  statement {
    sid       = "ListEC2andASG"
    effect    = "Allow"
    resources = ["*"]
    actions   = [
        "ec2:DescribeInstances",
        "autoscaling:DescribeAutoScalingInstances",
        "autoscaling:DescribeAutoScalingGroups"
    ]
  }
}

/*== MONGO INSTANCE SECURITY GROUP ==*/
resource "aws_security_group" "mongo" {
    name = "${var.tag}-mongo"
    ingress {
        from_port = 0
        to_port   = 65535
        protocol  = "tcp"
        self      = true
    }
    ingress {
        from_port = 0
        to_port   = 65535
        protocol  = "udp"
        self      = true
    }
    ingress {
        from_port   = 22
        to_port     = 22
        protocol    = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }
    ingress {
        from_port   = 27017
        to_port     = 27017
        protocol    = "tcp"
        cidr_blocks = ["${var.cidr}","${var.manager_cidr_block}"]
    }
    ingress {
        from_port   = 28017
        to_port     = 28017
        protocol    = "tcp"
        cidr_blocks = ["${var.cidr}"]
    }
    egress {
        from_port   = 0
        to_port     = 0
        protocol    = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }
    vpc_id = "${var.vpc_id}"
    tags {
        Name        = "${var.tag}-mongo-security-group"
        Environment = "${var.tag}"
    }
}

output "mongo_sg_id"      { value = "${aws_security_group.mongo.id}" }
output "mongo_asg_id"     { value = "${aws_autoscaling_group.mongo.id}" }
output "mongo_lc_id"      { value = "${aws_launch_configuration.mongo.id}" }
output "mongo_iam_arn"    { value = "${aws_iam_role.mongo.arn}" }

/* Not known when ASG in use, see https://github.com/terraform-providers/terraform-provider-aws/issues/511
output "mongo-servers" {
  value = "${join(",", aws_instance.mongo.*.private_ip)}"
}

output "mongo-ebs-drives" {
  value = "${join(",", aws_ebs_volume.mongo.*.id)}"
}
*/

/* Two years later and this is possible */
data "aws_instances" "mongodbs" {
  instance_tags {
    Name        = "MONGO-${var.tag}"
    Environment = "${lower(var.tag)}"
  }
}

output "private-ips" {
  value = "${data.aws_instances.mongodbs.private_ips}"
}