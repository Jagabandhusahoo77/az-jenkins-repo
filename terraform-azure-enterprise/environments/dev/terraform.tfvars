###############################################################################
# terraform.tfvars — dev environment non-sensitive values
#
# NEVER commit sensitive values (passwords, keys) here.
# Sensitive vars are passed via:
#   - Jenkins environment variables (from Azure credentials binding)
#   - Azure Key Vault references
#   - TF_VAR_* environment variables set in Jenkins pipeline
###############################################################################

project_name   = "enterprise-azure"
owner          = "platform-team"
environment    = "dev"
location       = "eastus"
location_short = "eus"
hub_name       = "hub"
workload       = "webapp"

# Hub network CIDRs
hub_address_space        = "10.0.0.0/16"
firewall_subnet_prefix   = "10.0.1.0/26"
gateway_subnet_prefix    = "10.0.0.0/27"
bastion_subnet_prefix    = "10.0.0.64/26"
management_subnet_prefix = "10.0.2.0/24"

# Spoke VNets
spokes = {
  app = {
    address_space      = "10.1.0.0/16"
    app_subnet_prefix  = "10.1.1.0/24"
    data_subnet_prefix = "10.1.2.0/24"
    pe_subnet_prefix   = "10.1.3.0/24"
    delegate_to_web    = false
  }
}

# Database — dev sizing (cheapest tier)
db_sku_name    = "GP_Gen5_2"
db_max_size_gb = 32

# AAD admin (use your AD group object ID)
aad_admin_login     = "terraform-sp"
aad_admin_object_id = "f9f390ab-9e5b-4613-bee3-4d0310d8d45e"

# Security alert emails
security_alert_emails = ["platform-team@company.com"]

# Compute — dev uses minimum sizing
vm_sku         = "Standard_B2s"
instance_count = 2
autoscale_min  = 2
autoscale_max  = 4
lb_frontend_ip = "10.1.1.100"

# Storage containers
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
