terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "4.64.0"
    }
  }
}

resource "aws_iam_role" "ecs_task_role" {
  name = "ecs-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}
resource "aws_iam_policy_attachment" "ecs_task_role_attachment" {
  name       = "ecs-task-role-attachment"
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"

  roles = [
    aws_iam_role.ecs_task_role.name,
  ]
}


provider "aws" {
  # Configuration options
  region = "ap-south-1"
}

# Create VPC
resource "aws_vpc" "pro_vpc" {
  cidr_block = "10.0.0.0/16"
}

# Create Subnet
resource "aws_subnet" "my_subnet_1" {
  vpc_id            = aws_vpc.pro_vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "ap-south-1a"
}

resource "aws_subnet" "my_subnet_2" {
  vpc_id            = aws_vpc.pro_vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "ap-south-1b"
}

resource "aws_internet_gateway" "my_igw" {
  vpc_id = aws_vpc.pro_vpc.id
}

resource "aws_route_table" "my_route_table" {
  vpc_id = aws_vpc.pro_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.my_igw.id
  }

  tags = {
    Name = "my-route-table"
  }
}

resource "aws_security_group" "security_group" {
  name = "my-seq"
  vpc_id      = aws_vpc.pro_vpc.id
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# create Application Load Balancer
resource "aws_lb" "my_alb" {
  name               = "emy-alb"
  internal           = false
  load_balancer_type = "application"
  subnets = [
    aws_subnet.my_subnet_1.id,
    aws_subnet.my_subnet_2.id
  ]
  security_groups = [aws_security_group.security_group.id]
}

# create target group
resource "aws_lb_target_group" "lb-target" {
  name        = "example-tg"
  port        = 5000
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_vpc.pro_vpc.id
}

# register targets
resource "aws_lb_target_group_attachment" "lb-target-at" {
  target_group_arn = aws_lb_target_group.lb-target.arn
  target_id        = "10.0.1.10" # IP address of the target
}


resource "aws_ecs_cluster" "ecs_cluster" {
  name = "my-project"
}

resource "aws_ecr_repository" "ecr_repo" {
  name = "devpro"
}

resource "aws_ecs_task_definition" "tsk_definition" {
  family                   = "my-task"
  network_mode             = "awsvpc"
  cpu                      = "1024"
  memory                   = "2048"
  requires_compatibilities = ["FARGATE"]
  container_definitions    = jsonencode(
[
  {
    "name": "example-container",
    "image": "${aws_ecr_repository.ecr_repo.repository_url}:latest",
    "portMappings": [
      {
        "containerPort": 5000,
        "hostPort": 5000,
        "protocol": "tcp"
      }
    ]
  }
])
  execution_role_arn       = aws_iam_role.ecs_task_role.arn

}

resource "aws_ecs_service" "my_service" {
  name            = "my-service"
  cluster         = "my-project" # replace with your ECS cluster name
  task_definition = aws_ecs_task_definition.tsk_definition.arn
  desired_count   = 1
  launch_type     = "FARGATE"
   network_configuration {
    security_groups = [aws_security_group.security_group.id]
    subnets         = [aws_subnet.my_subnet_1.id, aws_subnet.my_subnet_2.id]
assign_public_ip = true  
}
}
