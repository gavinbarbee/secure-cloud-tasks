# -----------------------------------------------------------------------------
# secure-cloud-tasks — root module
# Wires VPC → networking → security → data plane → ALB → EC2 with least-privilege IAM.
# -----------------------------------------------------------------------------

locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

resource "random_password" "db" {
  length  = 24
  special = false # RDS master password constraints (avoid /, @, ", space).
}

module "vpc" {
  source = "./modules/vpc"

  name_prefix      = local.name_prefix
  vpc_cidr         = var.vpc_cidr
  az_count         = var.availability_zone_count
  enable_flow_logs = var.enable_vpc_flow_logs
}

module "networking" {
  source = "./modules/networking"

  name_prefix         = local.name_prefix
  vpc_id              = module.vpc.vpc_id
  internet_gateway_id = module.vpc.internet_gateway_id
  public_subnet_ids   = module.vpc.public_subnet_ids
  private_subnet_ids = concat(
    module.vpc.private_app_subnet_ids,
    module.vpc.private_data_subnet_ids,
  )
  nat_gateway_count = var.enable_nat_ha ? var.availability_zone_count : 1
}

# Private connectivity to S3 + AWS APIs (reduces reliance on NAT for bootstrap).
module "vpc_endpoints" {
  source = "./modules/vpc_endpoints"

  name_prefix             = local.name_prefix
  vpc_id                  = module.vpc.vpc_id
  aws_region              = var.aws_region
  vpc_cidr                = module.vpc.vpc_cidr_block
  private_route_table_ids = module.networking.private_route_table_ids
  interface_subnet_ids    = module.vpc.private_app_subnet_ids

  depends_on = [module.networking]
}

module "security" {
  source = "./modules/security"

  name_prefix               = local.name_prefix
  vpc_id                    = module.vpc.vpc_id
  vpc_cidr                  = module.vpc.vpc_cidr_block
  app_port                  = var.app_port
  public_subnet_ids         = module.vpc.public_subnet_ids
  public_subnet_cidrs       = module.vpc.public_subnet_cidrs
  private_app_subnet_ids    = module.vpc.private_app_subnet_ids
  private_app_subnet_cidrs  = module.vpc.private_app_subnet_cidrs
  private_data_subnet_ids   = module.vpc.private_data_subnet_ids
  private_data_subnet_cidrs = module.vpc.private_data_subnet_cidrs
}

module "app_bundle" {
  source = "./modules/app_bundle"

  name_prefix    = local.name_prefix
  app_source_dir = abspath("${path.module}/../app")
}

module "database" {
  source = "./modules/database"

  name_prefix                = local.name_prefix
  private_data_subnet_ids    = module.vpc.private_data_subnet_ids
  database_security_group_id = module.security.database_security_group_id
  db_name                    = var.db_name
  db_username                = var.db_username
  db_password                = random_password.db.result
  instance_class             = var.db_instance_class
  engine_version             = var.engine_version
}

resource "aws_secretsmanager_secret" "app_database" {
  name                    = "${var.project_name}/${var.environment}/database"
  recovery_window_in_days = 0 # dev-friendly teardown; increase for prod.

  tags = {
    Name = "${local.name_prefix}-secret-database"
  }
}

resource "aws_secretsmanager_secret_version" "app_database" {
  secret_id = aws_secretsmanager_secret.app_database.id
  secret_string = jsonencode({
    username = var.db_username
    password = random_password.db.result
    host     = module.database.address
    port     = module.database.port
    dbname   = var.db_name
    engine   = "postgres"
  })
}

module "iam" {
  source = "./modules/iam"

  name_prefix             = local.name_prefix
  app_artifact_bucket_arn = module.app_bundle.bucket_arn
  app_artifact_object_arn = module.app_bundle.object_arn
  app_artifact_prefix     = "releases/"
  database_secret_arn     = aws_secretsmanager_secret.app_database.arn
}

module "alb" {
  source = "./modules/alb"

  name_prefix           = local.name_prefix
  vpc_id                = module.vpc.vpc_id
  public_subnet_ids     = module.vpc.public_subnet_ids
  alb_security_group_id = module.security.alb_security_group_id
  app_port              = var.app_port
}

module "compute" {
  source = "./modules/compute"

  name_prefix               = local.name_prefix
  aws_region                = var.aws_region
  vpc_id                    = module.vpc.vpc_id
  private_app_subnet_ids    = module.vpc.private_app_subnet_ids
  app_security_group_id     = module.security.app_security_group_id
  iam_instance_profile_name = module.iam.app_instance_profile_name
  alb_target_group_arn      = module.alb.target_group_arn
  database_secret_arn       = aws_secretsmanager_secret.app_database.arn
  app_artifact_bucket       = module.app_bundle.bucket_id
  app_artifact_key          = module.app_bundle.object_key
  app_port                  = var.app_port
  instance_type             = var.ec2_instance_type

  depends_on = [
    module.database,
    aws_secretsmanager_secret_version.app_database,
    module.iam,
    module.app_bundle,
    module.alb,
    module.vpc_endpoints,
  ]
}
