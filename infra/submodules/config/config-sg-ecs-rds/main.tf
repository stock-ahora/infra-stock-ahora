resource "aws_security_group_rule" "rds_from_app" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        =  var.sg_db_id         # destino
  source_security_group_id = var.sg_app_id      # origen
}

resource "aws_security_group_rule" "rds_from_ecs" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        =  var.sg_db_id         # destino
  source_security_group_id = var.sg_ecs_id     # origen
}

resource "aws_security_group_rule" "config-vpn" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        =  var.sg_db_id         # destino
  source_security_group_id = var.sg_vpn_db     # origen
}