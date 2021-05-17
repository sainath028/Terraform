/*====  Admin Password ======*/

variable "admin_password" {
  description = "password for windows instance"
  default     = "KcSLfY-@Ka=4WbYA4o6uK@TF@chUX(QW"
}
variable "type" {
  type = string
}

/*==== The VPC ======*/
resource "aws_vpc" "vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = {
    Name        = "${local.environment}-vpc"
    Environment = "${local.environment}"
  }
}
/*==== Subnets ======*/
/* Internet gateway for the public subnet */
resource "aws_internet_gateway" "ig" {
  vpc_id = "${aws_vpc.vpc.id}"
  tags = {
    Name        = "${local.environment}-igw"
    Environment = "${local.environment}"
  }
}
/* Elastic IP for NAT */
resource "aws_eip" "nat_eip" {
  vpc        = true
  depends_on = [aws_internet_gateway.ig]
}
/* NAT */
resource "aws_nat_gateway" "nat" {
  allocation_id = "${aws_eip.nat_eip.id}"
  subnet_id     = "${element(aws_subnet.public_subnet.*.id, 0)}"
  depends_on    = [aws_internet_gateway.ig]
  tags = {
    Name        = "nat"
    Environment = "${local.environment}"
  }
}
/* Public subnet */
resource "aws_subnet" "public_subnet" {
  vpc_id                  = "${aws_vpc.vpc.id}"
  count                   = length(local.availability_zones)
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${element(local.availability_zones, count.index)}"
  map_public_ip_on_launch = true
  tags = {
    Name        = "${local.environment}-local.availability_zones-public-subnet"
    Environment = "${local.environment}"
  }
}
/* Private subnet */
resource "aws_subnet" "private_subnet" {
  vpc_id                  = "${aws_vpc.vpc.id}"
  count                   = length(local.availability_zones)
//  count                   = length(local.private_subnets_cidr)
  cidr_block              = local.private_subnets_cidr
  availability_zone       = "${element(local.availability_zones, count.index)}"
  map_public_ip_on_launch = false
  tags = {
    Name        = "${local.environment}-local.availability_zones-private-subnet"
    Environment = "${local.environment}"
  }
}
/* Routing table for private subnet */
resource "aws_route_table" "private" {
  vpc_id = "${aws_vpc.vpc.id}"
  tags = {
    Name        = "${local.environment}-private-route-table"
    Environment = "${local.environment}"
  }
}

/* Routing table for public subnet */
resource "aws_route_table" "public" {
  vpc_id = "${aws_vpc.vpc.id}"
  tags = {
    Name        = "${local.environment}-public-route-table"
    Environment = "${local.environment}"
  }
}

resource "aws_route" "public_internet_gateway" {
  route_table_id         = "${aws_route_table.public.id}"
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = "${aws_internet_gateway.ig.id}"
}
resource "aws_route" "private_nat_gateway" {
  route_table_id         = "${aws_route_table.private.id}"
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = "${aws_nat_gateway.nat.id}"
}

/* Route table associations */
resource "aws_route_table_association" "public" {
//  count          = "${length(local.public_subnets_cidr)}"
  subnet_id      = "${element(aws_subnet.public_subnet.*.id, 0)}"
  route_table_id = "${aws_route_table.public.id}"
}
resource "aws_route_table_association" "private" {
// count          = "${length(local.private_subnets_cidr)}"
  subnet_id      = "${element(aws_subnet.private_subnet.*.id, 0)}"
  route_table_id = "${aws_route_table.private.id}"
}

/* alb */
resource "aws_alb" "alb" {
  name            = "alb"
  security_groups = ["${aws_security_group.alb.id}"]
//  count           = length(local.)
//  subnets         = [tolist(aws_subnet.private_subnet.*.id)]
  
  internal = true
}

/* target_group for alb */
resource "aws_alb_target_group" "group" {
  name     = "alb-target"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.vpc.id
  stickiness {
    type = "lb_cookie"
  }
  # Alter the destination of the health check to be the login page.
  health_check {
    path = "/login"
    port = 80
  }
}

/* listener for alb */
resource "aws_alb_listener" "listener_http" {
  load_balancer_arn = aws_alb.alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    target_group_arn = aws_alb_target_group.group.arn
    type             = "forward"
  }
}

/* security group for alb */
resource "aws_security_group" "alb" {
  name        = "alb_security_group"
  vpc_id      = aws_vpc.vpc.id

  # ingress {
  #   from_port   = 443
  #   to_port     = 443
  #   protocol    = "tcp"
  #   cidr_blocks = "${var.allowed_cidr_blocks}"
  # }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all outbound traffic.
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

/* security group for MySQL */
resource "aws_security_group" "MySQL-SG" {
  name = "mysql-sg"
  vpc_id = aws_vpc.vpc.id

  # Created an inbound rule for MySQL
  ingress {
    description = "MySQL Access"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    security_groups = [aws_security_group.BH-SG.id]
  }
  ingress {
    description = "RDP"
    from_port   = 3389
    to_port     = 3389
    protocol    = "tcp"
    security_groups = [aws_security_group.BH-SG.id]
  }

  # Created an inbound rule for alb
  ingress {
    description = "alb"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  # Created an inbound rule for WinRM Https
  ingress {
    description = "WinRM Https"
    from_port   = 5986
    to_port     = 5986
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Created an inbound rule for WinRM Http
  ingress {
    description = "WinRM Http"
    from_port   = 5985
    to_port     = 5985
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "output from MySQL"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

/* Security Group for the Bastion Host! */
resource "aws_security_group" "BH-SG" {
  name = "bastion-host-sg"
  vpc_id = aws_vpc.vpc.id

  # Created an inbound rule for Bastion Host SSH
  ingress {
    description = "Bastion Host SG"
    from_port   = 3389
    to_port     = 3389
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Created an inbound rule for WinRM Https
  ingress {
    description = "WinRM Https"
    from_port   = 5986
    to_port     = 5986
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Created an inbound rule for WinRM Http
  ingress {
    description = "WinRM Http"
    from_port   = 5985
    to_port     = 5985
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "output from Bastion Host"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

/* security group for MySQL Bastion Host Access */
resource "aws_security_group" "DB-SG-SSH" {
  name = "mysql-sg-bastion-host"
  vpc_id = aws_vpc.vpc.id

  # Created an inbound rule for MySQL Bastion Host
  ingress {
    description = "Bastion Host SG"
    from_port   = 3389
    to_port     = 3389
    protocol    = "tcp"
    security_groups = [aws_security_group.BH-SG.id]
  }

  # Created an inbound rule for WinRM Https
  ingress {
    description = "WinRM Https"
    from_port   = 5986
    to_port     = 5986
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Created an inbound rule for WinRM Http
  ingress {
    description = "WinRM Http"
    from_port   = 5985
    to_port     = 5985
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "output from MySQL BH"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


/* AWS instance for the Webserver! */
//resource "aws_instance" "webserver" {
//  ami = local.ami
//  instance_type = local.type
//  subnet_id = aws_subnet.public_subnet.id
//  key_name = local.key_name
//  vpc_security_group_ids = [aws_security_group.WS-SG.id]

//  tags = {
//   Name = "Webserver"
//  }
//}


/* AWS instance for the MySQL */
resource "aws_instance" "MySQL" {
  count = 2
  ami = local.ami
  instance_type = local.type
  subnet_id = aws_subnet.private_subnet.*.id
  key_name = local.key_name
  vpc_security_group_ids = [aws_security_group.MySQL-SG.id, aws_security_group.DB-SG-SSH.id]
  tags = {
   Name = "MySQL"
  }
}

/* AWS instance for the Bastion Host */
resource "aws_instance" "Bastion-Host" {
  ami = local.ami
  instance_type = local.type
  subnet_id = aws_subnet.public_subnet.*.id
  key_name = local.key_name
  vpc_security_group_ids = [aws_security_group.BH-SG.id]
  tags = {
   Name = "Bastion_Host"
  }
}

locals {
  environment                = "wind"
  availability_zones         = ["us-east-2a", "us-east-2b"]
  region                     = "us-east-2"
  vpc_cidr                   = "10.0.0.0/16"
  public_subnets_cidr        = "10.0.1.0/24"
  private_subnets_cidr       = "10.0.2.0/24"
//  instance_count             = 1
  ami                        = "ami-0ea03bb5978f0255e"
  key_name                   = "voiceanalyticskeypair"
  use_num_suffix             = false
  num_suffix_format          = "-%d"
  type                       = var.type != "" ? var.type : "t2.micro"
  idle_timeout               = 60
  enable_deletion_protection = false
}






