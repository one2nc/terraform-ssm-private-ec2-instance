provider "aws" {
  region = "ap-south-1"
}

# VPC Endpoints
locals {
  services = {
    "ec2messages" : {
      "name" : "ssm.ap-south-1.amazonaws.com"
    },
    "ssm" : {
      "name" : "ssmmessages.ap-south-1.amazonaws.com"
    },
    "ssmmessages" : {
      "name" : "ec2messages.ap-south-1.amazonaws.com"
    }
  }
}


# VPC
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support = true
}

# Public Subnet
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
}

# Private Subnet
resource "aws_subnet" "private" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.2.0/24"
}

resource "aws_vpc_endpoint" "ssm_endpoint" {
  for_each = local.services
  vpc_id   = aws_vpc.main.id
  service_name        = each.value.name
  vpc_endpoint_type   = "Interface"
  security_group_ids  = [aws_security_group.ssm_https.id]
  private_dns_enabled = true
  ip_address_type     = "ipv4"
  subnet_ids          = [aws_subnet.private.id]
}

resource "aws_security_group" "ssm_https" {
  name        = "allow_ssm"
  description = "Allow SSM traffic"
  vpc_id      = aws_vpc.main.id
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [aws_subnet.private.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Internet Gateway
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id
}

# Public Route Table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
}

resource "aws_route" "public_internet_access" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.gw.id
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# NAT Gateway
resource "aws_eip" "nat" {}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public.id
}

# Private Route Table
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
}

resource "aws_route" "private_nat_access" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat.id
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

# Security Group
resource "aws_security_group" "private_sg" {
  vpc_id = aws_vpc.main.id
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# IAM Role for SSM
resource "aws_iam_role" "ssm_role" {
  name = "EC2SSMRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })
}

# Attach AmazonSSMManagedInstanceCore Policy to IAM Role
resource "aws_iam_policy_attachment" "ssm_policy_attach" {
  name       = "ssm-policy-attachment"
  roles      = [aws_iam_role.ssm_role.name]
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# IAM Instance Profile
resource "aws_iam_instance_profile" "ssm_instance_profile" {
  name = "EC2SSMInstanceProfile"
  role = aws_iam_role.ssm_role.name
}

# EC2 Instance in Private Subnet with SSM Role
resource "aws_instance" "private_ec2" {
  ami                  = "ami-09773b29dffbef1f2" # Ubuntu Noble Numbat AMI (Replace with correct AMI)
  instance_type        = "t4g.micro"
  subnet_id           = aws_subnet.private.id
  security_groups      = [aws_security_group.private_sg.id]
  iam_instance_profile = aws_iam_instance_profile.ssm_instance_profile.name
  user_data = file("./user_data.sh")

  tags = {
    Name = "PrivateWebServer"
  }
}

