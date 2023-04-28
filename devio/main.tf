terraform {
  required_version = "~> 1.2.6"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.23.0"
    }
  }
  cloud {
    organization = "cm-keisuke-poc-org"
    hostname = "app.terraform.io"

    workspaces {
      name = "terraform-practice"
    }
  }
}

provider "aws" {
  region = "ap-northeast-1"
}

data "aws_ssm_parameter" "rds_username" {
  name = "/rds/mysql/username"
}

data "aws_ssm_parameter" "rds_password" {
  name = "/rds/mysql/password"
  with_decryption = true
}

# VPCを作成
resource "aws_vpc" "my_vpc" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "my-vpc"
  }
}

# パブリックサブネットを作成
resource "aws_subnet" "my_subnet1" {
  vpc_id            = aws_vpc.my_vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "ap-northeast-1a"

  tags = {
    Name = "my-pub-subnet1"
  }
}

# プライベートサブネットを作成
resource "aws_subnet" "my_subnet2" {
  vpc_id            = aws_vpc.my_vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "ap-northeast-1c"

  tags = {
    Name = "my-pri-subnet2"
  }
}

# インターネットゲートウェイを作成
resource "aws_internet_gateway" "my_igw" {
  vpc_id = aws_vpc.my_vpc.id

  tags = {
    Name = "my-igw"
  }
}

# パブリックサブネットにルートテーブルを作成
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.my_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.my_igw.id
  }

  tags = {
    Name = "public-route-table"
  }
}

# パブリックサブネットにルートテーブルを関連付ける
resource "aws_route_table_association" "public_rta" {
  subnet_id      = aws_subnet.my_subnet1.id
  route_table_id = aws_route_table.public_rt.id
}

# プライベートサブネットにルートテーブルを作成
resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.my_vpc.id

  tags = {
    Name = "private-route-table"
  }
}

# プライベートサブネットにNATゲートウェイを経由するルートテーブルを関連付ける
resource "aws_route" "private_route" {
  route_table_id         = aws_route_table.private_rt.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.my_nat_gateway.id
}

resource "aws_route_table_association" "private_rta" {
  subnet_id      = aws_subnet.my_subnet2.id
  route_table_id = aws_route_table.private_rt.id
}

# NATゲートウェイを作成
resource "aws_nat_gateway" "my_nat_gateway" {
  allocation_id = aws_eip.my_eip.id
  subnet_id     = aws_subnet.my_subnet1.id

  tags = {
    Name = "my-nat-gateway"
  }
}

# Elastic IPを作成
resource "aws_eip" "my_eip" {
  vpc = true

  tags = {
    Name = "my-eip"
  }
}

# 踏み台用のEC2をパブリックサブネットに作成
resource "aws_instance" "bastion" {
  ami           = "ami-0c94855ba95c71c99"
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.my_subnet1.id
  vpc_security_group_ids = [aws_security_group.bastion_sg.id]
  user_data = <<-EOF
              #!/bin/bash
              sudo yum update -y
              sudo yum install -y mysql
              EOF

  tags = {
    Name = "bastion"
  }
}

# 踏み台用セキュリティグループを作成
resource "aws_security_group" "bastion_sg" {
  name_prefix = "bastion-sg-"
  vpc_id      = aws_vpc.my_vpc.id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "bastion-sg"
  }
}

# データベースセキュリティグループを作成
resource "aws_security_group" "db_sg" {
  name_prefix = "db-sg-"
  vpc_id      = aws_vpc.my_vpc.id

  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    security_groups = [
      aws_security_group.bastion_sg.id,
    ]
  }

  tags = {
    Name = "db"
  }
}

# サブネットグループの作成
resource "aws_db_subnet_group" "rds_subnet_group" {
  name        = "rds_subnet_group"
  subnet_ids  = [aws_subnet.my_subnet1.id, aws_subnet.my_subnet2.id]
}

# RDS MySQLを作成
resource "aws_db_instance" "rds_instance" {
  identifier            = "myrds"
  db_name		= "myrdsinstance"
  engine                = "mysql"
  engine_version        = "5.7"
  instance_class        = "db.t2.micro"
  username              = data.aws_ssm_parameter.rds_username.value
  password              = data.aws_ssm_parameter.rds_password.value
  allocated_storage     = 10
  storage_type          = "gp2"
  backup_retention_period = 7
  db_subnet_group_name  = aws_db_subnet_group.rds_subnet_group.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  skip_final_snapshot	= true
}

