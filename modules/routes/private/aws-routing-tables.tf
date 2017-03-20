/*=== ROUTING TABLES AND ASSOCIATIONS ===*/
variable "tag"   {}
variable "vpc_id" {}
variable "nat_gateway_ids" {
    type    = "list"
    default = []
}
variable "zones" {
    type    = "list"
    default = []
}
variable "subnet_ids" {
    type    = "list"
    default = []
}

resource "aws_route_table" "private-subnet" {
    count  = "${length(var.zones)}"
    vpc_id = "${var.vpc_id}"
    route {
        cidr_block     = "0.0.0.0/0"
        nat_gateway_id = "${element(var.nat_gateway_ids, count.index)}"
    }
    tags {
        Name        = "${var.tag}-private-subnet-route-table"
        Environment = "${lower(var.tag)}"
    }
}

resource "aws_route_table_association" "private-subnet" {
    count          = "${length(var.zones)}"
    subnet_id      = "${element(var.subnet_ids, count.index)}"
    route_table_id = "${element(aws_route_table.private-subnet.*.id, count.index)}"
}

output "private_subnets_rt_ids" { value = ["${aws_route_table.private-subnet.*.id}"] }
