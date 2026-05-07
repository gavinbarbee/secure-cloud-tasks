output "alb_security_group_id" {
  value = aws_security_group.alb.id
}

output "app_security_group_id" {
  value = aws_security_group.app.id
}

output "database_security_group_id" {
  value = aws_security_group.database.id
}

output "network_acl_ids" {
  value = {
    public       = aws_network_acl.public.id
    private_app  = aws_network_acl.private_app.id
    private_data = aws_network_acl.private_data.id
  }
}
