/*=== NAT GW FOR THE PRIVATE SUBNETS ===*/
variable "name"  { default = "nat" }
variable "zones" {
    type    = "list"
    default = []
}
variable "subnet_ids" {
    type    = "list"
    default = []
}

resource "aws_eip" "natgw" {
    count = "${length(var.zones)}"
    vpc   = true
}

resource "aws_nat_gateway" "natgw" {
    #depends_on    = ["module.vpc.aws_internet_gateway.environment", "aws_subnet.public-subnets"]
    count         = "${length(var.zones)}"
    allocation_id = "${element(aws_eip.natgw.*.id, count.index)}"
    subnet_id     = "${element(var.subnet_ids, count.index)}"
}

output "nat_gateway_ids" { value = ["${aws_nat_gateway.natgw.*.id}"] }
