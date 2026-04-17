project_name   = "enterprise-azure"
owner          = "platform-team"
environment    = "staging"
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
    address_space      = "10.2.0.0/16"
    app_subnet_prefix  = "10.2.1.0/24"
    data_subnet_prefix = "10.2.2.0/24"
    pe_subnet_prefix   = "10.2.3.0/24"
    delegate_to_web    = false
  }
}

# Staging mirrors prod sizing but no HA features
db_sku_name    = "GP_Gen5_4"
db_max_size_gb = 64

aad_admin_login     = "DBA-Admins"
aad_admin_object_id = "00000000-0000-0000-0000-000000000000"

security_alert_emails = ["platform-team@company.com"]

vm_sku         = "Standard_D4s_v5"
instance_count = 2
autoscale_min  = 2
autoscale_max  = 6
lb_frontend_ip = "10.2.1.100"

storage_containers = {
  app-data = { immutable = false }
  audit    = { immutable = true }
  backups  = { immutable = false }
}

tags = {
  cost_center   = "engineering"
  department    = "platform"
  business_unit = "technology"
}
