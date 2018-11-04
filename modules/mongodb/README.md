To activate the module in the `main.tf` file:

```
module "mongo" {
    source         = "./modules/mongodb"
    tag            = "${var.vpc["tag"]}"
    region         = "${var.provider["region"]}"
    cidr           = "${var.vpc["cidr_block"]}"
    zones          = ["${split(",", lookup(var.azs, var.provider["region"]))}"]
    image          = "${lookup(var.images-ubuntu-trusty, var.provider["region"])}"
    key_name       = "${var.key_name}"
    vpc_id         = "${module.vpc.vpc_id}"
    subnet_ids     = ["${module.private-subnets.subnet_ids}"]
    zone_id        = "${module.vpc.route53_zone}"
    domain         = "${lower(var.vpc["tag"])}.${var.enc_domain_int}"
    data_center    = "${module.consul.consul_dc}"
    mydb           = "${var.mydb}"
}

output "mongo_sg_id"      { value = "${module.mongo.mongo_sg_id}" }
output "mongo_asg_id"     { value = "${module.mongo.mongo_asg_id}" }
output "mongo_lc_id"      { value = "${module.mongo.mongo_lc_id}" }
output "mongo_iam_arn"    { value = "${module.mongo.mongo_iam_arn}" }
```

Set the global var in the `variables.tf` file:

```
/*== MONGO ==*/
variable "mydb" {
    type    = "map"
    default = {
        instance_type     = ""
        volume_size       = ""
        ephemeral0_device = ""
        volume_type       = ""
        volume_device     = ""
        volume_device2    = ""
        volume_mount      = ""
        volume_encrypted  = false
        rs_name           = ""
    }
}
```

And populate the values in the `variables.tfvars` file:

```
mydb = {
    instance_type         = "m4.large"
    volume_size           = "50"
    ephemeral0_device     = "/dev/sdb"
    volume_type           = "standard"
    volume_device         = "/dev/sde"
    volume_device2        = "/dev/sdf"
    volume_mount          = "/var/lib/mydb"
    volume_encrypted      = "true"
    rs_name               = "mydbrs"
}
```

The instances will get enough permissions via IAM instance roles to discover each other as members of an ASG and register themselves to the internal DNS zone created with the VPC. This can serve for dynamic discovery of the instances using DNS ans their A or SRV records. The work is done via the user-data script where an LVM RAID0 volume is also assembled for the DB storage. 