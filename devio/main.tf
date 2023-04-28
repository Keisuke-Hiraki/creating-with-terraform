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
  enable_dns_hostnames = true

  tags = {
    Name = "my-vpc"
  }
}

# サブネットを作成
resource "aws_subnet" "my_subnet1" {
  vpc_id = aws_vpc.my_vpc.id
  cidr_block = "10.0.1.0/24"
  availability_zone = "ap-northeast-1a"

  tags = {
    Name = "my-subnet1"
  }
}

resource "aws_subnet" "my_subnet2" {
  vpc_id = aws_vpc.my_vpc.id
  cidr_block = "10.0.2.0/24"
  availability_zone = "ap-northeast-1c"

  tags = {
    Name = "my-subnet2"
  }
}

# インターネットゲートウェイを作成
resource "aws_internet_gateway" "my_igw" {
  vpc_id = aws_vpc.my_vpc.id

  tags = {
    Name = "my-igw"
  }
}

# ルートテーブルを作成
resource "aws_route_table" "my_rt" {
  vpc_id = aws_vpc.my_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.my_igw.id
  }

  tags = {
    Name = "my-rt"
  }
}

# ルートテーブルとサブネットを関連付ける
resource "aws_route_table_association" "my_rta1" {
  subnet_id = aws_subnet.my_subnet1.id
  route_table_id = aws_route_table.my_rt.id
}

resource "aws_route_table_association" "my_rta2" {
  subnet_id = aws_subnet.my_subnet2.id
  route_table_id = aws_route_table.my_rt.id
}

# セキュリティグループを作成
resource "aws_security_group" "rds_sg" {
  name_prefix = "rds_sg_"
  vpc_id = aws_vpc.my_vpc.id

  ingress {
    from_port = 3306
    to_port = 3306
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_db_subnet_group" "rds_subnet_group" {
  name        = "rds_subnet_group"
  subnet_ids  = [aws_subnet.my_subnet1.id, aws_subnet.my_subnet2.id]
}

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

