# Network and ALB example

This independent Terraform example creates AWS networking and an HTTP Application
Load Balancer. It was previously stored in `infra/` and keeps its own local state.

It does not deploy the random-generator application, EC2 instances, MySQL, or ECR
repositories. For the application infrastructure, see the
[modular Terraform example](../infrastructure/terraform/modular/README.md).

## Resources

- A VPC with DNS support and DNS hostnames enabled.
- Two public subnets in different availability zones and one private subnet.
- An internet gateway, public routes, and subnet route-table associations.
- One NAT gateway with an Elastic IP, providing outbound access for the private subnet.
- An internet-facing ALB with a security group allowing inbound HTTP on port 80.
- An HTTP listener forwarding to an instance target group on port 80.

The target group has no registered instances, and the ALB security group has no
outbound rules configured. This example alone cannot serve application traffic.
It also has no HTTPS listener or certificate configuration.

## Folder layout

```text
infra-example/
├── main.tf                 # AWS provider and module wiring
├── variables.tf            # Root configuration inputs
├── modules/
│   ├── network/            # VPC, subnets, gateways, and routes
│   └── alb/                # Load balancer, listener, target group, security group
└── README.md
```

The network module exposes VPC and subnet IDs to the ALB module. There are no
root-level outputs, so `terraform output` does not expose an application URL.

## Configuration

Install Terraform and configure AWS credentials through your normal AWS profile
or environment. The modules require the AWS provider `~> 6.0`; this example does
not declare a Terraform CLI version constraint. The selected region needs at
least two available standard availability zones.

| Input | Default | Purpose |
| --- | --- | --- |
| `REGION_EU_CENTRAL_1` | `eu-central-1` | Region used by the AWS provider |
| `VPC_CIDR` | `10.42.0.0/16` | VPC address range |
| `PUBLIC_SUBNET_CIDRS` | `["10.42.1.0/24", "10.42.2.0/24"]` | Exactly two public subnet ranges |
| `PRIVATE_SUBNET_CIDR` | `10.42.10.0/24` | Private subnet range |
| `REGION_US_EAST_1` | `us-east-1` | Currently unused; does not create a second deployment |

Use non-overlapping subnet ranges within the VPC range. Optional overrides can
be saved in the ignored `infra-example/tf.vars` file, for example:

```hcl
REGION_EU_CENTRAL_1 = "eu-central-1"
VPC_CIDR           = "10.42.0.0/16"
PUBLIC_SUBNET_CIDRS = ["10.42.1.0/24", "10.42.2.0/24"]
PRIVATE_SUBNET_CIDR = "10.42.10.0/24"
```

Terraform does not automatically load `tf.vars`; pass `-var-file=tf.vars` to
plan and destroy commands when using it. AWS authentication is configured
separately; do not put credentials into these Terraform source files.

## Validate and deploy

From the repository root:

```sh
terraform -chdir=infra-example init
terraform -chdir=infra-example fmt -check -recursive
terraform -chdir=infra-example validate
terraform -chdir=infra-example plan -out=deployment.tfplan
```

With a local overrides file, replace the plan command with:

```sh
terraform -chdir=infra-example plan -var-file=tf.vars -out=deployment.tfplan
```

Review the saved plan before applying it:

```sh
terraform -chdir=infra-example apply deployment.tfplan
```

The ALB, NAT gateway, and public IPv4 allocation incur AWS charges even without
an application deployed. A single NAT gateway is shared by this example.

## State and cleanup

No remote backend is configured. Preserve this directory's local
`terraform.tfstate` and any backups; do not copy state between this example and
the other Terraform configurations. Local state, `tf.vars`, provider caches,
saved plans, and the lockfile are ignored by the repository's current Git rules.

To review and remove resources created by this example:

```sh
terraform -chdir=infra-example plan -destroy
terraform -chdir=infra-example destroy
```

Add `-var-file=tf.vars` to both commands if you deployed with that file. Destroy
removes this example's managed infrastructure; keep its state until cleanup is
complete.
