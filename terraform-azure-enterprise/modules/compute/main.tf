###############################################################################
# Module: compute
#
# Deploys a Linux Virtual Machine Scale Set (VMSS) behind an Azure Load
# Balancer. VMSS is preferred over individual VMs for application workloads
# because it provides auto-scaling and rolling upgrade capabilities.
#
# Managed Identity is assigned to the VMSS so application pods can retrieve
# secrets from Key Vault without any credentials in config files.
###############################################################################

terraform {
  required_version = ">= 1.6.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

###############################################################################
# User-Assigned Managed Identity
# We use user-assigned (not system-assigned) so the identity survives VMSS
# deletion and can be pre-granted Key Vault roles before the VMSS exists.
###############################################################################
resource "azurerm_user_assigned_identity" "vmss" {
  name                = "id-vmss-${var.workload}-${var.environment}-${var.location_short}"
  location            = var.location
  resource_group_name = var.resource_group_name

  tags = var.tags
}

# Grant the VMSS identity read access to Key Vault secrets
resource "azurerm_role_assignment" "vmss_kv_secrets_user" {
  scope                = var.key_vault_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.vmss.principal_id
}

# Minimal RBAC for reading own resource group (needed for Azure Instance Metadata)
resource "azurerm_role_assignment" "vmss_rg_reader" {
  scope                = var.resource_group_id
  role_definition_name = "Reader"
  principal_id         = azurerm_user_assigned_identity.vmss.principal_id
}

###############################################################################
# Azure Load Balancer (Internal)
# Internal LB is preferred for app tiers not directly facing the internet —
# traffic arrives via Application Gateway which talks to this internal LB.
###############################################################################
resource "azurerm_lb" "internal" {
  name                = "lbi-${var.workload}-${var.environment}-${var.location_short}"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "Standard" # Standard SKU for zone redundancy and HA ports

  frontend_ip_configuration {
    name                          = "internal-frontend"
    subnet_id                     = var.app_subnet_id
    private_ip_address_allocation = "Static"
    private_ip_address            = var.lb_frontend_ip
    zones                         = ["1", "2", "3"]
  }

  tags = var.tags
}

resource "azurerm_lb_backend_address_pool" "vmss" {
  loadbalancer_id = azurerm_lb.internal.id
  name            = "bepool-${var.workload}"
}

resource "azurerm_lb_probe" "http" {
  loadbalancer_id     = azurerm_lb.internal.id
  name                = "probe-http"
  protocol            = "Http"
  port                = var.app_port
  request_path        = var.health_probe_path
  interval_in_seconds = 15
  number_of_probes    = 3
}

resource "azurerm_lb_rule" "http" {
  loadbalancer_id                = azurerm_lb.internal.id
  name                           = "rule-${var.workload}-http"
  protocol                       = "Tcp"
  frontend_port                  = var.app_port
  backend_port                   = var.app_port
  frontend_ip_configuration_name = "internal-frontend"
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.vmss.id]
  probe_id                       = azurerm_lb_probe.http.id
  enable_tcp_reset               = true # improves connection teardown reliability
  disable_outbound_snat          = true # outbound goes via Firewall, not LB SNAT
}

###############################################################################
# Virtual Machine Scale Set (Linux)
###############################################################################
resource "azurerm_linux_virtual_machine_scale_set" "app" {
  name                = "vmss-${var.workload}-${var.environment}-${var.location_short}"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = var.vm_sku
  instances           = var.instance_count
  admin_username      = var.admin_username

  # Disable password auth; SSH key only
  disable_password_authentication = true
  # encryption_at_host_enabled requires Microsoft.Compute/EncryptionAtHost feature registration
  # Enable after: az feature register --name EncryptionAtHost --namespace Microsoft.Compute
  admin_ssh_key {
    username   = var.admin_username
    public_key = var.ssh_public_key
  }

  # Spread instances across availability zones for HA
  zones        = ["1", "2", "3"]
  zone_balance = true

  upgrade_mode = "Rolling"
  rolling_upgrade_policy {
    max_batch_instance_percent              = 20
    max_unhealthy_instance_percent          = 20
    max_unhealthy_upgraded_instance_percent = 20
    pause_time_between_batches              = "PT0S"
  }

  # Health extension required for rolling upgrades
  health_probe_id = azurerm_lb_probe.http.id

  automatic_os_upgrade_policy {
    enable_automatic_os_upgrade = true
    disable_automatic_rollback  = false
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  os_disk {
    storage_account_type = "Premium_LRS" # Premium SSD for consistent IOPS
    caching              = "ReadWrite"
    disk_size_gb         = 64

    # Encrypt OS disk with platform-managed key + customer-managed key
    disk_encryption_set_id = var.disk_encryption_set_id
  }

  network_interface {
    name    = "nic-${var.workload}"
    primary = true

    ip_configuration {
      name                                   = "ipconfig-${var.workload}"
      primary                                = true
      subnet_id                              = var.app_subnet_id
      load_balancer_backend_address_pool_ids = [azurerm_lb_backend_address_pool.vmss.id]
    }
  }

  # Assign managed identity — no credentials needed in app config
  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.vmss.id]
  }

  # Custom data runs on first boot — installs app, pulls config from Key Vault
  custom_data = base64encode(templatefile("${path.module}/templates/cloud-init.yaml.tpl", {
    key_vault_uri = var.key_vault_uri
    environment   = var.environment
    app_port      = var.app_port
  }))

  # Terminate notification — gracefully drain connections before scale-in
  termination_notification {
    enabled = true
    timeout = "PT10M"
  }

  tags = var.tags

  lifecycle {
    ignore_changes = [instances] # allow autoscale to manage instance count
  }

  depends_on = [azurerm_lb_rule.http] # LB rule must exist before VMSS references the probe
}

###############################################################################
# Autoscale Settings
###############################################################################
resource "azurerm_monitor_autoscale_setting" "vmss" {
  name                = "as-${var.workload}-${var.environment}-${var.location_short}"
  location            = var.location
  resource_group_name = var.resource_group_name
  target_resource_id  = azurerm_linux_virtual_machine_scale_set.app.id
  enabled             = true

  profile {
    name = "default"

    capacity {
      default = var.instance_count
      minimum = var.autoscale_min
      maximum = var.autoscale_max
    }

    rule {
      metric_trigger {
        metric_name        = "Percentage CPU"
        metric_resource_id = azurerm_linux_virtual_machine_scale_set.app.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = 75
      }
      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = "2"
        cooldown  = "PT5M"
      }
    }

    rule {
      metric_trigger {
        metric_name        = "Percentage CPU"
        metric_resource_id = azurerm_linux_virtual_machine_scale_set.app.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT10M"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = 25
      }
      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT10M" # longer cooldown on scale-in to avoid flapping
      }
    }
  }

  tags = var.tags
}
