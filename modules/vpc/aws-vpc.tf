variable "name"   { default = "vpc" }
variable "region" {}
variable "cidr"   {}
variable "domain_int" {}
variable "zones" {
    type = "list"
    default = []
}
variable "env" { default = "production" }
variable "provider" {
    type    = "map"
    default = {
        access_key = "unknown"
        secret_key = "unknown"
        region     = "unknown"
    }
}

/*=== VPC AND GATEWAYS ===*/
resource "aws_vpc" "environment" {
    cidr_block           = "${var.cidr}"
    enable_dns_support   = true
    enable_dns_hostnames = true 
    tags {
        Name        = "VPC-${var.name}"
        Environment = "${lower(var.name)}"
    }
}

resource "aws_internet_gateway" "environment" {
    vpc_id = "${aws_vpc.environment.id}"
    tags {
        Name        = "${var.name}-internet-gateway"
        Environment = "${lower(var.name)}"
    }
}

/*=== DHCP AND DNS ===*/
resource "aws_route53_zone" "environment" {
  name   = "${lower(var.name)}.${var.domain_int}"
  vpc_id = "${aws_vpc.environment.id}"
}

resource "aws_route53_record" "environment" {
    zone_id = "${aws_route53_zone.environment.zone_id}"
    name    = "${lower(var.name)}.${var.domain_int}"
    type    = "NS"
    ttl     = "30"
    records = [
        "${aws_route53_zone.environment.name_servers.0}",
        "${aws_route53_zone.environment.name_servers.1}",
        "${aws_route53_zone.environment.name_servers.2}",
        "${aws_route53_zone.environment.name_servers.3}"
    ]
}

/* Not needed here since the zone is being associated with
   the VPC via vpc_id upon creation
resource "aws_route53_zone_association" "environment" {
  zone_id = "${aws_route53_zone.environment.zone_id}"
  vpc_id  = "${aws_vpc.environment.id}"
}
*/

resource "aws_vpc_dhcp_options" "environment" {
    domain_name         = "${var.provider["region"]}.compute.internal ${lower(var.name)}.${var.domain_int} consul"
    domain_name_servers = ["169.254.169.253", "AmazonProvidedDNS"]
    tags {
        Name        = "${var.name}-dhcp-options"
        Environment = "${lower(var.name)}"
    }
}

resource "aws_vpc_dhcp_options_association" "environment" {
    vpc_id          = "${aws_vpc.environment.id}"
    dhcp_options_id = "${aws_vpc_dhcp_options.environment.id}"
}

output "vpc_id" { value = "${aws_vpc.environment.id}" }
output "igw_id" { value = "${aws_internet_gateway.environment.id}" }
output "route53_zone" { value = "${aws_route53_zone.environment.id}" }
output "vpc_cidr" { value = "${aws_vpc.environment.cidr_block}" }

