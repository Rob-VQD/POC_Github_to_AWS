provider "aws" {
    region                  = "us-east-1"
    shared_credentials_file = var.shared_credentials_path
    profile                 = "default"
}

# 1. Create vpc
resource "aws_vpc" "rds-vpc" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "RDS-VPC"
    Purpose = "POC AWS on DevOps"
  }
}

# 2. Create Internet Gateway
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.rds-vpc.id
}

# 3. Create Private Route Table
resource "aws_route_table" "private-route-table" {
  vpc_id = aws_vpc.rds-vpc.id
  tags = {
    Name = "Private-RT"
  }
}

# 3. Create Public Route Table
resource "aws_route_table" "public-route-table" {
  vpc_id = aws_vpc.rds-vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  route {
    ipv6_cidr_block = "::/0"
    gateway_id      = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "Public-RT"
  }
}

# 4. Create first Subnet 
resource "aws_subnet" "private_subnet_1" {
  vpc_id            = aws_vpc.rds-vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "Private-subnet-1"
  }
}

# 4. Create Second subnet in different AZ  
resource "aws_subnet" "private_subnet_2" {
  vpc_id            = aws_vpc.rds-vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-1b"

  tags = {
    Name = "Private-subnet-2"
  }
}

# 5. Create second subnet in different AZ for Availability

resource "aws_subnet" "public_subnet" {
  vpc_id            = aws_vpc.rds-vpc.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "us-east-1b"

  tags = {
    Name = "Public-subnet-1"
  }
}

# 6. Create subnet group

resource "aws_db_subnet_group" "RDS-subnet-group" {
  name       = "main"
  subnet_ids = [aws_subnet.private_subnet_1.id,aws_subnet.private_subnet_2.id]

  tags = {
    Name = "My DB subnet group"
  }
}

# 7. Associate subnet with Route Table
resource "aws_route_table_association" "a1" {
  subnet_id      = aws_subnet.private_subnet_1.id
  route_table_id = aws_route_table.private-route-table.id
}

# 7. Associate subnet with Route Table
resource "aws_route_table_association" "a2" {
  subnet_id      = aws_subnet.private_subnet_2.id
  route_table_id = aws_route_table.private-route-table.id
}

# 7. Associate subnet with Route Table
resource "aws_route_table_association" "b" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public-route-table.id
}

# 8. Create Security Group to allow traffic into Bastion host
resource "aws_security_group" "Bastion-SG" {
  name        = "Bastion-SG_traffic"
  description = "Allow one IP inbound traffic"
  vpc_id      = aws_vpc.rds-vpc.id

  ingress {
      description = "All traffic from VQD IP"
      from_port = 0
      to_port = 0
      protocol    = "-1"
      cidr_blocks = var.IP_address_port_1433
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "Bastion-SG"
  }
}

resource "aws_security_group" "RDS-SG" {
  name        = "RDS-SG_traffic"
  description = "Allow Web inbound traffic"
  vpc_id      = aws_vpc.rds-vpc.id

  ingress {
      description = "All traffic from public SG"
      from_port = 0
      to_port = 0
      protocol    = "-1"
      cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "RDS-SG"
  }
}



# 9. Create a network interface with an ip in the subnet that was created in step 4
resource "aws_network_interface" "web-server-nic" {
  subnet_id       = aws_subnet.public_subnet.id
  private_ips     = ["10.0.3.50"]
  security_groups = [aws_security_group.Bastion-SG.id]

}

# 10. Assign an elastic IP to the network interface created in step 7
resource "aws_eip" "one" {
  vpc                       = true
  network_interface         = aws_network_interface.web-server-nic.id
  associate_with_private_ip = "10.0.3.50"
  depends_on                = [aws_internet_gateway.gw]
}


# 9. Create RDS instance within VPC
resource "aws_db_instance" "First_RDS" {
  allocated_storage    = 5
  engine               = "mysql"
  engine_version       = "5.7"
  instance_class       = "db.t2.micro"
  identifier           = "rdsinvpc"
  name                 = "mydb"
  username             = var.Database_Username
  password             = var.Database_Password
  parameter_group_name = "default.mysql5.7"
  multi_az             = true
  db_subnet_group_name = aws_db_subnet_group.RDS-subnet-group.id
  vpc_security_group_ids = [aws_security_group.RDS-SG.id]
  skip_final_snapshot  = true
}

# 9. Create Linux server and install/enable apache2
resource "aws_instance" "Bastion-Host" {
  ami               = "ami-085925f297f89fce1"
  instance_type     = "t2.micro"
  availability_zone = "us-east-1b"

  # This key has to be made in the AWS console under EC2! 
  key_name          = "Terraform-Key"

  network_interface {
    device_index         = 0
    network_interface_id = aws_network_interface.web-server-nic.id
  }
  tags = {
    Name = "Bastion_host"
  }
}



# module "db" {
#   source = "../../"

#   identifier = "demodb"

#   # All available versions: http://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/CHAP_MySQL.html#MySQL.Concepts.VersionMgmt
#   engine            = "mysql"
#   engine_version    = "5.7.19"
#   instance_class    = "db.t2.large"
#   allocated_storage = 5
#   storage_encrypted = false

#   # kms_key_id        = "arm:aws:kms:<region>:<account id>:key/<kms key id>"
#   name     = "demodb"
#   username = var.Database_Username
#   password = var.Database_Password
#   port     = var.Port_to_connect_to_db

#   vpc_security_group_ids = [aws_security_group.RDS-SG.id]

#   maintenance_window = "Mon:00:00-Mon:03:00"
#   backup_window      = "03:00-06:00"

#   multi_az = true

#   # disable backups to create DB faster
#   backup_retention_period = 0

#   tags = {
#     Owner       = "user"
#     Environment = "dev"
#   }

#   enabled_cloudwatch_logs_exports = ["audit", "general"]

#   # DB subnet group
#   subnet_ids = data.aws_subnet_ids.all.ids

#   # DB parameter group
#   family = "mysql5.7"

#   # DB option group
#   major_engine_version = "5.7"

#   # Snapshot name upon DB deletion
#   final_snapshot_identifier = "demodb"

#   # Database Deletion Protection
#   deletion_protection = false

#   parameters = [
#     {
#       name  = "character_set_client"
#       value = "utf8"
#     },
#     {
#       name  = "character_set_server"
#       value = "utf8"
#     }
#   ]

#   options = [
#     {
#       option_name = "MARIADB_AUDIT_PLUGIN"

#       option_settings = [
#         {
#           name  = "SERVER_AUDIT_EVENTS"
#           value = "CONNECT"
#         },
#         {
#           name  = "SERVER_AUDIT_FILE_ROTATIONS"
#           value = "37"
#         },
#       ]
#     },
#   ]
# }


