# terraform-vpc

Modular Terraform repository to provision a multi-tier VPC in AWS. By default it will create:

* One public and two private subnets in each AZ for the chosen region
* Internal DNS zone associated to the VPC for internal domain resolution (eg. mydomain.internal)
* Internet gateway for the public subnets
* One EC2 NAT gateway per AZ for the private subnets
* One routing table per private subnet associated to the corresponding EC2 NAT gateway
* One Jumphost with internal DNS zone record (eg. bastion.mydomain.internal)

Since it is modular it is easy to add or remove modules depending on preferences and requirements.

## Install Terraform

To install `terraform` follow the steps from the install web page [Getting Started](https://www.terraform.io/intro/getting-started/install.html)

## Quick Start

After setting up the binaries go to the cloned terraform directory and create a `.tfvars` file with your AWS IAM API credentials inside the `tf` subdirectory. For example, `provider-credentials.tfvars` with the following content:  
```
provider = {
  provider.access_key = "<AWS_ACCESS_KEY>"
  provider.secret_key = "<AWS_SECRET_KEY>"
  provider.region     = "<AWS_EC2_REGION>"
}
```
Replace `<AWS_EC2_REGION>` with the region you want to launch the VPC in.

The global VPC variables are in the `variables.tfvars` file so edit this file and adjust the values accordingly. Replace `TFTEST` with appropriate environment (this value is used to tag all the resources created in the VPC) and set the VPC CIDR in the `vpc.cidr_block` variable (defaults to 10.99.0.0/20).

Each `.tf` file in the `tf` subdirectory is Terraform playbook where our VPC resources are being created. The `variables.tf` file contains all the variables being used and their values are being populated by the settings in the `variables.tfvars`.

To begin, start by issuing the following command inside the `tf` directory:  
```
$ terraform plan -var-file variables.tfvars -var-file provider-credentials.tfvars -out vpc.tfplan
```  
This will create lots of output about the resources that are going to be created and a `vpc.tfplan` plan file containing all the changes that are going to be applied. If this goes without any errors then we can proceed to the next step, otherwise we have to go back and fix the errors terraform has printed out. To apply the planned changes then we run:

```
$ terraform apply -var-file variables.tfvars -var-file provider-credentials.tfvars vpc.tfplan
```  

This will take some time to finish but after that we will have a new VPC deployed.

Terraform also puts some state into the `terraform.tfstate` file by default. This state file is extremely important; it maps various resource metadata to actual resource IDs so that Terraform knows what it is managing. This file must be saved and distributed to anyone who might run Terraform against the very VPC infrastructure we created so storing this in GitHub repository is a good way to go in order to share a project.

## Further Infrastructure Updates

After we have provisioned our VPC we have to decide how we want to proceed with its maintenance. Any changes made outside of Terraform, like in the EC2 web console, result in Terraform being unaware of it which in turn means Terraform might revert those changes on the next replay. That's why it is very important to choose the AWS console OR the terraform repository as the **only** way of applying changes to our VPC.  

To make changes, like for example update or create a Security Group, we edit the respective `.tf` file and run the above `terraform plan` and `terraform apply` commands. 

## Deleting the Infrastructure

To destroy the whole VPC we run:  
```
$ terraform destroy -var-file variables.tfvars -var-file provider-credentials.tfvars -force
```
Terraform is smart enough to determine what order things should be destroyed, same as in the case of creating or updating infrastructure.
