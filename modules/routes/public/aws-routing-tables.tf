/*=== ROUTING TABLES AND ASSOCIATIONS ===*/
variable "tag"   {}
variable "igw"   {}
variable "vpc_id" {}
variable "zones" {
    type    = "list"
    default = []
}
variable "subnet_ids" {
    type    = "list"
    default = []
}

resource "aws_route_table" "public-subnet" {
    vpc_id = "${var.vpc_id}"
    route {
        cidr_block = "0.0.0.0/0"
        gateway_id = "${var.igw}"
    }
    tags {
        Name        = "${var.tag}-public-subnet-route-table"
        Environment = "${lower(var.tag)}"
    }
}

resource "aws_route_table_association" "public-subnet" {
    count          = "${length(var.zones)}"
    subnet_id      = "${element(var.subnet_ids, count.index)}"
    route_table_id = "${aws_route_table.public-subnet.id}"
}

output "public_subnets_rt_id" { value = "${aws_route_table.public-subnet.id}" }