###############################################################################
# prod/terraform.tfvars — Production configuration
# Full HA: zone-redundant, geo-replicated, VPN gateway, max autoscale
###############################################################################

project_name   = "enterprise-azure"
owner          = "platform-team"
environment    = "prod"
location       = "eastus"
location_short = "eus"
hub_name       = "hub"
workload       = "webapp"

hub_address_space        = "10.0.0.0/16"
firewall_subnet_prefix   = "10.0.1.0/26"
gateway_subnet_prefix    = "10.0.0.0/27"
bastion_subnet_prefix    = "10.0.0.64/26"
management_subnet_prefix = "10.0.2.0/24"

spokes = {
  app = {
    address_space      = "10.3.0.0/16"
    app_subnet_prefix  = "10.3.1.0/24"
    data_subnet_prefix = "10.3.2.0/24"
    pe_subnet_prefix   = "10.3.3.0/24"
    delegate_to_web    = false
  }
}

# Business Critical tier: in-memory OLTP, faster failover, read replicas
db_sku_name    = "BC_Gen5_8"
db_max_size_gb = 256
# zone_redundant is set in prod main.tf override

aad_admin_login     = "DBA-Admins"
aad_admin_object_id = "00000000-0000-0000-0000-000000000000"

security_alert_emails = ["platform-team@company.com", "security@company.com"]

# Prod: larger VMs, more instances
vm_sku         = "Standard_D8s_v5"
instance_count = 4
autoscale_min  = 4
autoscale_max  = 20
lb_frontend_ip = "10.3.1.100"

storage_containers = {
  app-data          = { immutable = false }
  audit             = { immutable = true }
  backups           = { immutable = false }
  disaster-recovery = { immutable = false }
}

tags = {
  cost_center   = "engineering"
  department    = "platform"
  business_unit = "technology"
  criticality   = "high"
}
