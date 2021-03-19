Le serveur des copains
======================

LSDC (Le serveur des copains - The buddies' server) is an AWS hosted
infrastructure, deployed using [Terraform](https://www.terraform.io/) and
[Ansible](https://www.ansible.com/).

It features:

*   A publicly accessible instance in the default VPC.
*   A lambda to start/stop/status the instance.
*   An API Gateway to invoque the lambda from a URL.
*   A UDP sniffing daemon to stop the instance when no-one is connected on a
    certain port, after a certain timeout.
*   A steamcmd installation role.
*   A Valheim dedicated server role.

What it does not feature: an API Gateway to you function

Usage
-----

Refer to [Terraform tutorial](https://learn.hashicorp.com/collections/terraform/aws-get-started)
to setup your environment with you AWS account.

Clone the repository and init Terraform providers:

    git clone https://github.com/Meuna/lsdc-aws.git
    cd lsdc-aws
    terraform init

Provision the infrastructure, using the variables bellow to customize you setup:

    terraform apply -var='key_name=valheim' -var="instance_type=t3.medium" -var="region=eu-west-3"

Terraform should output a succeding message, with the public IP of the
provisioned EC2.

    Apply complete! Resources: 16 added, 0 changed, 0 destroyed.

    Outputs:

    api_url = "https://xxxxxxx.execute-api.eu-west-3.amazonaws.com/"
    ec2_ip = "xx.xx.xx.xx"

Finally, provision the stack using Ansible and the IP of the provisioned EC2:

    ansible-playbook valheim.yaml -i xx.xx.xx.xx,

Play with your friends !
------------------------

Give the provisioned `api_url` above to your friends, they can now:

*   Query the IP of the running server with the route `api_url/status`
*   Start the instance if it is not running with the route `api_url/start`
*   Stop the instance with the route `api_url/stop`
