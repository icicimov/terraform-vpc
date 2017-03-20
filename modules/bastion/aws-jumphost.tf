variable "tag"      {}
variable "vpc_id"   {}
variable "cidr"     {}
variable "region"   {}
variable "image"    {}
variable "key_name" {}
variable "instance_type" {}
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

/*=== JUMPHOST INSTANCE ASG ===*/
resource "aws_autoscaling_group" "jumphost" {
    name                      = "${var.tag}-jumphost-asg"
    availability_zones        = ["${var.zones}"]
    vpc_zone_identifier       = ["${var.subnet_ids}"]
    max_size                  = 1
    min_size                  = 1
    health_check_grace_period = 60
    default_cooldown          = 60
    health_check_type         = "EC2"
    desired_capacity          = 1
    force_delete              = true
    launch_configuration      = "${aws_launch_configuration.jumphost.name}"
    tag {
      key                 = "Name"
      value               = "JUMPHOST-${var.tag}"
      propagate_at_launch = true
    }
    tag {
      key                 = "Environment"
      value               = "${lower(var.tag)}"
      propagate_at_launch = true
    }
    tag {
      key                 = "Type"
      value               = "jumphost"
      propagate_at_launch = true
    }
    tag {
      key                 = "Role"
      value               = "bastion"
      propagate_at_launch = true
    }
    lifecycle {
      create_before_destroy = true
    }
}

resource "aws_launch_configuration" "jumphost" {
    name_prefix                 = "${var.tag}-jumphost-lc-"
    image_id                    = "${var.image}"
    instance_type               = "${var.instance_type}"
    iam_instance_profile        = "${aws_iam_instance_profile.jumphost.name}"
    key_name                    = "${var.key_name}"
    security_groups             = ["${aws_security_group.jumphost.id}"] 
    associate_public_ip_address = true
    user_data                   = "${data.template_file.jumphost.rendered}"
    lifecycle {
      create_before_destroy = true
    }
}

data "template_file" "jumphost" {
    template = "${file("${path.module}/userdata-jumphost.sh")}"
    vars {
        cidr     = "${var.cidr}"
        zone_id  = "${var.zone_id}"
        domain   = "${var.domain}"
    }
}

/*== JUMPHOST INSTANCES IAM ==*/
resource "aws_iam_instance_profile" "jumphost" {
    name  = "${var.tag}-jumphost-profile"
    roles = ["${aws_iam_role.jumphost.name}"]
    lifecycle {
      create_before_destroy = true
    }
}

resource "aws_iam_role" "jumphost" {
    name               = "${var.tag}-jumphost-role"
    path               = "/"
    assume_role_policy = "${data.aws_iam_policy_document.jumphost.json}"
    lifecycle {
      create_before_destroy = true
    }
}

data "aws_iam_policy_document" "jumphost" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "jumphost-route53" {
  name   = "${var.tag}-jumphost-role-policy"
  role   = "${aws_iam_role.jumphost.id}"
  policy = "${data.aws_iam_policy_document.jumphost-route53.json}"
}

data "aws_iam_policy_document" "jumphost-route53" {
  statement {
    sid       = "BastionListHostedZones"
    effect    = "Allow"
    resources = ["*"]
    actions   = [
      "route53:ListHostedZones"
    ]
  },
  statement {
    sid       = "BastionChangeRecordSets"
    effect    = "Allow"
    resources = ["arn:aws:route53:::hostedzone/${var.zone_id}"]
    actions   = [
      "route53:ChangeResourceRecordSets",
      "route53:ListResourceRecordSets"
    ]
  }
}

/*== JUMPHOST INSTANCES SECURITY GROUP ==*/
resource "aws_security_group" "jumphost" {
    name = "${var.tag}-jumphost"
    ingress {
        from_port   = 22
        to_port     = 22
        protocol    = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }
    ingress {
        from_port   = -1
        to_port     = -1
        protocol    = "icmp"
        cidr_blocks = ["0.0.0.0/0"]
    }
    egress {
        from_port   = 22
        to_port     = 22
        protocol    = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }
    egress {
        from_port   = -1
        to_port     = -1
        protocol    = "icmp"
        cidr_blocks = ["0.0.0.0/0"]
    }
    egress {
        from_port   = 80
        to_port     = 80
        protocol    = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }
    egress {
        from_port   = 443 
        to_port     = 443 
        protocol    = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }
    vpc_id = "${var.vpc_id}"
    tags {
        Name        = "${var.tag}-jumphost-security-group"
        Environment = "${lower(var.tag)}"
    }
}

output "bastion_sg_id"   { value = "${aws_security_group.jumphost.id}" }
output "bastion_asg_id"  { value = "${aws_autoscaling_group.jumphost.id}" }
output "bastion_lc_id"   { value = "${aws_launch_configuration.jumphost.id}" }
output "bastion_iam_arn" { value = "${aws_iam_role.jumphost.arn}" }

