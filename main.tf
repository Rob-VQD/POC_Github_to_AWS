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
    Owner = "Rob"
    Env   = "Sandbox"
    Purpose = "Research"
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
    Owner = "Rob"
    Env   = "Sandbox"
    Purpose = "Research"
  }
}

# 4. Create Public Route Table
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
    Owner = "Rob"
    Env   = "Sandbox"
    Purpose = "Research"
  }
}

# 5. Create first private Subnet 
resource "aws_subnet" "private_subnet_1" {
  vpc_id            = aws_vpc.rds-vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "Private-subnet-1"
    Owner = "Rob"
    Env   = "Sandbox"
    Purpose = "Research"
  }
}

# 6. Create second private Subnet in different AZ  
resource "aws_subnet" "private_subnet_2" {
  vpc_id            = aws_vpc.rds-vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-1b"

  tags = {
    Name = "Private-subnet-2"
    Owner = "Rob"
    Env   = "Sandbox"
    Purpose = "Research"
  }
}

# 7. Create public Subnet
resource "aws_subnet" "public_subnet" {
  vpc_id            = aws_vpc.rds-vpc.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "us-east-1b"

  tags = {
    Name = "Public-subnet-1"
    Owner = "Rob"
    Env   = "Sandbox"
    Purpose = "Research"
  }
}

# 8. Create subnet group for RDS
resource "aws_db_subnet_group" "RDS-subnet-group" {
  name       = "main"
  subnet_ids = [aws_subnet.private_subnet_1.id,aws_subnet.private_subnet_2.id]

  tags = {
    Name = "My DB subnet group"
    Owner = "Rob"
    Env   = "Sandbox"
    Purpose = "Research"
  }
}

# 9.1 Associate private subnet with private Route Table
resource "aws_route_table_association" "a1" {
  subnet_id      = aws_subnet.private_subnet_1.id
  route_table_id = aws_route_table.private-route-table.id
}

# 9.2 Associate private subnet with private Route Table
resource "aws_route_table_association" "a2" {
  subnet_id      = aws_subnet.private_subnet_2.id
  route_table_id = aws_route_table.private-route-table.id
}

# 10. Associate subnet with Route Table
resource "aws_route_table_association" "b" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public-route-table.id
}

# 11. Create Security Group to allow traffic into Bastion host
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
    Owner = "Rob"
    Env   = "Sandbox"
    Purpose = "Research"
  }
}

# 12. Create Security Group to allo traffic from other Security Group
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
    Owner = "Rob"
    Env   = "Sandbox"
    Purpose = "Research"
  }
}

# 13. Create a network interface with an ip in the subnet that was created in step 4
resource "aws_network_interface" "web-server-nic" {
  subnet_id       = aws_subnet.public_subnet.id
  private_ips     = ["10.0.3.50"]
  security_groups = [aws_security_group.Bastion-SG.id]

}

# 14. Assign an elastic IP to the network interface created in step 7
resource "aws_eip" "one" {
  vpc                       = true
  network_interface         = aws_network_interface.web-server-nic.id
  associate_with_private_ip = "10.0.3.50"
  depends_on                = [aws_internet_gateway.gw]
}


# 15. Create RDS instance within VPC
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

  tags = {
    Name = "TF-RDS"
    Owner = "Rob"
    Env   = "Sandbox"
    Purpose = "Research"
  }
}

# 16. Create instance for Bastion Host
resource "aws_instance" "Bastion-Host" {
  ami               = "ami-085925f297f89fce1"
  instance_type     = "t2.micro"
  availability_zone = "us-east-1b"

  # !!!!! This key has to be MANUALLY made in the AWS console under EC2 !!!!
  key_name          = "Terraform_key_Rob"

  network_interface {
    device_index         = 0
    network_interface_id = aws_network_interface.web-server-nic.id
  }
  tags = {
    Name = "Bastion_host"
    Owner = "Rob"
    Env   = "Sandbox"
    Purpose = "Research"
  }
}