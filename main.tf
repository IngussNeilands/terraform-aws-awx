module "database" {
  source  = "terraform-aws-modules/rds-aurora/aws"
  version = "~> 2.0"

  name                            = "awx_postgres"

  engine                          = "aurora-postgresql"
  engine_version                  = "10.7"

  vpc_id                          = var.vpc_id
  subnets                         = var.database_subnets

  allowed_security_groups         = [] #TODO
  allowed_security_groups_count   = 0 #TODO
  instance_type                   = var.db_instance_type
  storage_encrypted               = true
  apply_immediately               = true

  db_parameter_group_name         = "default"
  db_cluster_parameter_group_name = "default"

  enabled_cloudwatch_logs_exports = [
    "audit",
    "error",
    "general",
    "slowquery"
  ]

  tags = merge(
    local.common_tags,
    var.tags
  )
}


resource "tls_private_key" "ecs_root" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# resource "aws_secretsmanager_secret" "ecs_root_ssh_key" {
#   name_prefix = "awx-ecs-ssh-key-${var.env}-"
#   description = "ssh key for ec2-user user on ECS Instances"

#   tags = merge(
#     local.common_tags,
#     var.tags,
#     {
#       "Name" = "awx-ecs-root-ssh-key"
#     },
#   )
# }

# resource "aws_secretsmanager_secret_version" "ecs-root-ssh-key-value" {
#   secret_id     = aws_secretsmanager_secret.ecs_root_ssh_key.id
#   secret_string = tls_private_key.ecs_root.private_key_pem
# }

module "ecs-cluster" {
  source                   = "github.com/rhythmictech/terraform-aws-ecs-cluster?ref=1.0.0"
  name                     = "awx-ecs-cluster-${terraform.workspace}"
  instance_policy_document = data.aws_iam_policy_document.ecs-instance-policy-document.json
  vpc_id                   = var.vpc_id
  alb_subnet_ids           = var.public_subnets
  instance_subnet_ids      = var.private_subnets
  ssh_pubkey               = tls_private_key.ecs_root.public_key_openssh
  instance_type            = "t3.micro"
  region                   = local.region
  min_instances            = 0
  max_instances            = 0
  desired_instances        = 0
}

data "aws_iam_policy_document" "ecs-instance-policy-document" {
  statement {
    actions = [
      "rds-db:connect",
    ]

    resources = [
      "arn:aws:rds-db:${local.region}:${local.account_id}:dbuser:${module.database.instance-id}/${module.database.username}",
    ]
  }
}

resource "aws_security_group_rule" "ecs_alb_ingress_80" {
  security_group_id = module.ecs-cluster.alb-sg-id
  type = "ingress"
  from_port = 80
  to_port = 80
  protocol = "tcp"
  cidr_blocks = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "ecs_alb_ingress_443" {
  security_group_id = module.ecs-cluster.alb-sg-id
  type = "ingress"
  from_port = 443
  to_port = 443
  protocol = "tcp"
  cidr_blocks = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "ecs_alb_egress" {
  security_group_id = module.ecs-cluster.alb-sg-id
  type = "egress"
  from_port = 0
  to_port = 0
  protocol = "-1"
  cidr_blocks = [var.cidr_block[terraform.workspace]]
}

resource "aws_security_group_rule" "ecs_ec2_ingress_from_alb" {
  security_group_id = module.ecs-cluster.ec2-sg-id
  type = "ingress"
  from_port = 0
  to_port = 0
  protocol = "-1"
  source_security_group_id = module.ecs-cluster.alb-sg-id
}

resource "aws_security_group_rule" "ecs_ec2_egress" {
  security_group_id = module.ecs-cluster.ec2-sg-id
  type = "egress"
  from_port = 0
  to_port = 0
  protocol = "-1"
  cidr_blocks = ["0.0.0.0/0"]
}