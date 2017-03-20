variable "tag"   {}
variable "region" {}
variable "cidr"   {}
variable "subnet_bits" { default = "4" }
variable "subnet_start" { default = "0" }
variable "zones" {
    type    = "list"
    default = []
}
variable "env" { default = "production" }
variable "type" { default = "private" }
variable "vpc_id" {}
variable "public_ip" { default = "false" }

resource "aws_subnet" "aws-subnets" {
    vpc_id            = "${var.vpc_id}"
    count             = "${var.env == "production" ? length(var.zones) : 0}"
    cidr_block        = "${cidrsubnet(var.cidr, var.subnet_bits, count.index + (var.subnet_start * length(var.zones)))}"
    availability_zone = "${var.zones[count.index]}"
    tags {
        Name          = "${var.tag}-${var.type}-subnet-${count.index}"
        Environment   = "${lower(var.tag)}"
        Network       = "${lower(var.type)}"
    }
    map_public_ip_on_launch = "${var.public_ip}"
}

output "subnet_ids" { value = ["${aws_subnet.aws-subnets.*.id}"] }