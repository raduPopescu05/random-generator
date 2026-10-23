resource "aws_db_subnet_group" "app" {
  name       = var.cluster_name
  subnet_ids = module.network.private_subnet_ids
}

resource "aws_security_group" "database" {
  name_prefix = "${var.cluster_name}-database-"
  description = "MySQL from EKS Fargate pods only"
  vpc_id      = module.network.vpc_id
}

# Fargate pod ENIs use the EKS cluster primary security group.
resource "aws_vpc_security_group_ingress_rule" "mysql" {
  security_group_id            = aws_security_group.database.id
  referenced_security_group_id = module.eks.cluster_primary_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = 3306
  to_port                      = 3306
}

resource "aws_db_instance" "app" {
  identifier                  = var.cluster_name
  engine                      = "mysql"
  engine_version              = "8.4.7"
  instance_class              = "db.t4g.micro"
  allocated_storage           = 20
  storage_type                = "gp3"
  storage_encrypted           = true
  db_name                     = "random_generator"
  username                    = var.db_username
  password                    = var.db_password
  manage_master_user_password = false
  db_subnet_group_name        = aws_db_subnet_group.app.name
  vpc_security_group_ids      = [aws_security_group.database.id]
  publicly_accessible         = false
  multi_az                    = false
  backup_retention_period     = 0
  deletion_protection         = false
  skip_final_snapshot         = true
  delete_automated_backups    = true
  auto_minor_version_upgrade  = false
}
