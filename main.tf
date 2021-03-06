terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.30"
    }
  }
}

variable "key_name" {
  type        = string
  default     = "lsdc"
  description = "The name of the SSH key pair to use"
}

variable "region" {
  type        = string
  default     = "eu-west-3"
  description = "The region to host the service"
}

variable "instance_type" {
  type        = string
  default     = "t3.medium"
  description = "The instance type to host the service"
}

data "http" "ifconfig" {
  url = "https://ifconfig.co/json"
  request_headers = {
    Accept = "application/json"
  }
}

locals {
  service = "lsdc"
  my_ip   = jsondecode(data.http.ifconfig.body).ip
}

provider "aws" {
  profile = "default"
  region  = var.region
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-bionic-18.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_default_vpc" "default" {}

resource "aws_sqs_queue" "queue" {
  name                       = "queue-${local.service}"
  max_message_size           = 1024
  message_retention_seconds  = 300
  visibility_timeout_seconds = 0
}

resource "aws_security_group" "ssh_and_server" {
  name        = "allow_${local.service}"
  description = "Allow SSH and ${local.service} inbound traffic"
  vpc_id      = aws_default_vpc.default.id

  ingress {
    description = "SSH from my ip"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["${local.my_ip}/32"]
  }

  ingress {
    description = "Valheim ports"
    from_port   = 2456
    to_port     = 2458
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Minecraft ports"
    from_port   = 25565
    to_port     = 25565
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

data "aws_iam_policy_document" "ec2-assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "ec2-policy" {
  statement {
    actions = [
      "sqs:ReceiveMessage",
      "sqs:PurgeQueue"
    ]
    resources = [aws_sqs_queue.queue.arn]
  }
  statement {
    actions   = ["ec2:DescribeInstances"]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "ec2_policy" {
  name   = "ec2-policy-${local.service}"
  path   = "/${local.service}/"
  policy = data.aws_iam_policy_document.ec2-policy.json
}

resource "aws_iam_role" "ec2" {
  name                = "ec2-role-${local.service}"
  path                = "/${local.service}/"
  assume_role_policy  = data.aws_iam_policy_document.ec2-assume.json
  managed_policy_arns = [aws_iam_policy.ec2_policy.arn]
}

resource "aws_iam_instance_profile" "ec2" {
  name = "ec2-profile-${local.service}"
  role = aws_iam_role.ec2.name
}

resource "aws_instance" "server" {
  ami                  = data.aws_ami.ubuntu.id
  instance_type        = var.instance_type
  key_name             = var.key_name
  security_groups      = [aws_security_group.ssh_and_server.name]
  iam_instance_profile = aws_iam_instance_profile.ec2.name

  tags = {
    Name    = local.service
    SQS_URL = aws_sqs_queue.queue.id
  }
}

data "aws_iam_policy_document" "lambda-assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "lambda-policy" {
  statement {
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.queue.arn]
  }
  statement {
    actions   = ["ec2:StartInstances"]
    resources = [aws_instance.server.arn]
  }
  statement {
    actions   = ["ec2:DescribeInstances"]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "lambda_policy" {
  name   = "lambda-${local.service}"
  path   = "/${local.service}/"
  policy = data.aws_iam_policy_document.lambda-policy.json
}

resource "aws_iam_role" "lambda_startstop" {
  name                = "lambda-${local.service}"
  path                = "/${local.service}/"
  assume_role_policy  = data.aws_iam_policy_document.lambda-assume.json
  managed_policy_arns = [aws_iam_policy.lambda_policy.arn]
}

data "archive_file" "lambda-code" {
  type        = "zip"
  source_file = "${path.module}/lambda.py"
  output_path = "${path.module}/.terraform/archive_files/lambda.zip"
}

resource "aws_lambda_function" "lambda_startstop" {
  function_name    = "lambda-startstop-${local.service}"
  filename         = data.archive_file.lambda-code.output_path
  source_code_hash = base64sha256(data.archive_file.lambda-code.output_path)
  role             = aws_iam_role.lambda_startstop.arn
  handler          = "lambda.lambda_handler"

  runtime = "python3.8"

  environment {
    variables = {
      INSTANCE_ID = aws_instance.server.id
      SQS_URL     = aws_sqs_queue.queue.id
    }
  }
}

resource "aws_apigatewayv2_api" "startstop" {
  name          = "startstop-${local.service}"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_route" "start" {
  api_id    = aws_apigatewayv2_api.startstop.id
  route_key = "GET /start"
  target    = "integrations/${aws_apigatewayv2_integration.startstop.id}"
}

resource "aws_apigatewayv2_route" "stop" {
  api_id    = aws_apigatewayv2_api.startstop.id
  route_key = "GET /stop"
  target    = "integrations/${aws_apigatewayv2_integration.startstop.id}"
}

resource "aws_apigatewayv2_route" "status" {
  api_id    = aws_apigatewayv2_api.startstop.id
  route_key = "GET /status"
  target    = "integrations/${aws_apigatewayv2_integration.startstop.id}"
}

resource "aws_apigatewayv2_integration" "startstop" {
  api_id           = aws_apigatewayv2_api.startstop.id
  integration_type = "AWS_PROXY"

  connection_type        = "INTERNET"
  integration_method     = "POST"
  integration_uri        = aws_lambda_function.lambda_startstop.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_stage" "startstop" {
  api_id      = aws_apigatewayv2_api.startstop.id
  name        = "$default"
  auto_deploy = true
  depends_on = [aws_apigatewayv2_integration.startstop]
}

output "ec2_ip" {
  value = aws_instance.server.public_ip
}

output "api_url" {
  value = aws_apigatewayv2_stage.startstop.invoke_url
}
