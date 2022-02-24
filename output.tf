output "nomad_endpoint" {
  value = "http://${module.alb.lb_dns_name}"
}