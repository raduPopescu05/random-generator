# Provider configuration is inherited from the calling root module.
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

# Discover two standard availability zones in the requested region.
data "aws_availability_zones" "available" {
  state = "available"
  filter {
    name   = "zone-type"
    values = ["availability-zone"]
  }
}

# The VPC contains the public ALB/NAT and private Fargate pods.
resource "aws_vpc" "app" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = var.cluster_name }
}

# The ALB requires public subnets in two different availability zones.
resource "aws_subnet" "public" {
  count             = 2
  vpc_id            = aws_vpc.app.id
  cidr_block        = var.public_subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]
  tags = {
    Name                     = "${var.cluster_name}-public-${count.index + 1}"
    "kubernetes.io/role/elb" = "1"
  }
}

# Fargate pods use private subnets across two availability zones.
resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.app.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]
  tags = {
    Name                              = "${var.cluster_name}-private-${count.index + 1}"
    "kubernetes.io/role/internal-elb" = "1"
  }
}

# Internet access for the ALB and the NAT gateway.
resource "aws_internet_gateway" "app" {
  vpc_id = aws_vpc.app.id
}

# Public subnet default route.
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.app.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.app.id
  }
}

# Apply the public routes to both ALB subnets.
resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Stable outbound address for the NAT gateway, not for pods.
resource "aws_eip" "nat" {
  domain = "vpc"
}

# One NAT gateway provides private outbound internet access for this example.
resource "aws_nat_gateway" "app" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id
  depends_on    = [aws_internet_gateway.app, aws_route_table_association.public]
}

# Pods reach ECR, Docker Hub, and AWS APIs through NAT.
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.app.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.app.id
  }
}

# Apply the NAT route to the private subnet.
resource "aws_route_table_association" "private" {
  count          = 2
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}
