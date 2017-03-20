vpc = {
    tag         = "TFTEST"
    cidr_block  = "10.99.0.0/20"
    subnet_bits = "4"
}
key_name        = "ec2key"
instance_type   = "t2.micro"
enc_domain = {
    name        = "mydomain.com"
}
enc_domain_int  = "mydomain.internal"
