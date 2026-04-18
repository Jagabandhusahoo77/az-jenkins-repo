###############################################################################
# Module: simulated-onprem
#
# Simulates an on-premises data centre using an Azure VNet in a paired region.
# This is the standard pattern used in:
#   - Microsoft Azure CAF labs
#   - AZ-700 / AZ-305 certification labs
#   - Enterprise POC environments with no physical on-prem hardware
#
# What it creates:
#   - A "corporate DC" VNet (192.168.0.0/16 — RFC1918, typical on-prem range)
#   - A VPN Gateway in that VNet (acts as the on-prem VPN device)
#   - A VNet-to-VNet connection back to the hub VPN gateway
#   - A Windows/Linux jump VM to simulate workloads in the corporate DC
#
# WHY VNet-to-VNet instead of Local Network Gateway?
#   Both sides are Azure-managed so we use the native VNet-to-VNet connection
#   type. The IPSec policies are identical to a real on-prem tunnel — BGP,
#   IKEv2, AES256. The only difference is the "on-prem" device is also Azure.
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
# Resource Group — separate RG keeps simulated on-prem isolated from hub
###############################################################################
resource "azurerm_resource_group" "onprem" {
  name     = "rg-simulated-onprem-${var.environment}"
  location = var.onprem_location
  tags     = var.tags
}

###############################################################################
# Simulated On-Premises VNet
# Using 192.168.0.0/16 — classic RFC1918 corporate range, avoids overlap
# with hub (10.0.0.0/16) and spokes (10.3.0.0/16)
###############################################################################
resource "azurerm_virtual_network" "onprem" {
  name                = "vnet-onprem-${var.environment}"
  location            = azurerm_resource_group.onprem.location
  resource_group_name = azurerm_resource_group.onprem.name
  address_space       = [var.onprem_address_space]
  tags                = var.tags
}

resource "azurerm_subnet" "gateway" {
  name                 = "GatewaySubnet" # must be exactly this name — Azure requirement
  resource_group_name  = azurerm_resource_group.onprem.name
  virtual_network_name = azurerm_virtual_network.onprem.name
  address_prefixes     = [var.onprem_gateway_subnet_prefix]
}

resource "azurerm_subnet" "workload" {
  name                 = "snet-workload"
  resource_group_name  = azurerm_resource_group.onprem.name
  virtual_network_name = azurerm_virtual_network.onprem.name
  address_prefixes     = [var.onprem_workload_subnet_prefix]
}

###############################################################################
# VPN Gateway — acts as the simulated on-prem VPN device
# VpnGw1 is the minimum SKU; use VpnGw1AZ for zone-redundancy
###############################################################################
resource "azurerm_public_ip" "onprem_gw" {
  name                = "pip-onprem-vpngw-${var.environment}"
  location            = azurerm_resource_group.onprem.location
  resource_group_name = azurerm_resource_group.onprem.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

resource "azurerm_virtual_network_gateway" "onprem" {
  name                = "vpngw-onprem-${var.environment}"
  location            = azurerm_resource_group.onprem.location
  resource_group_name = azurerm_resource_group.onprem.name
  type                = "Vpn"
  vpn_type            = "RouteBased"
  sku                 = "VpnGw1" # cheaper than hub's VpnGw2AZ — on-prem doesn't need HA
  enable_bgp          = true

  ip_configuration {
    name                          = "onprem-gw-ipconfig"
    public_ip_address_id          = azurerm_public_ip.onprem_gw.id
    private_ip_address_allocation = "Dynamic"
    subnet_id                     = azurerm_subnet.gateway.id
  }

  bgp_settings {
    asn = 65000 # on-prem ASN — must differ from hub's 65515
  }

  tags = var.tags
}

###############################################################################
# VNet-to-VNet Connections (bidirectional — both sides must have a connection)
#
# Hub → On-Prem
###############################################################################
resource "azurerm_virtual_network_gateway_connection" "hub_to_onprem" {
  name                = "cn-hub-to-onprem-${var.environment}"
  location            = var.hub_location
  resource_group_name = var.hub_resource_group_name

  type                            = "Vnet2Vnet"
  virtual_network_gateway_id      = var.hub_vpn_gateway_id
  peer_virtual_network_gateway_id = azurerm_virtual_network_gateway.onprem.id

  shared_key = var.vpn_shared_key
  enable_bgp = true

  ipsec_policy {
    dh_group         = "DHGroup14"
    ike_encryption   = "AES256"
    ike_integrity    = "SHA256"
    ipsec_encryption = "AES256"
    ipsec_integrity  = "SHA256"
    pfs_group        = "PFS14"
  }

  tags = var.tags
}

# On-Prem → Hub (return leg of the bidirectional connection)
resource "azurerm_virtual_network_gateway_connection" "onprem_to_hub" {
  name                = "cn-onprem-to-hub-${var.environment}"
  location            = azurerm_resource_group.onprem.location
  resource_group_name = azurerm_resource_group.onprem.name

  type                            = "Vnet2Vnet"
  virtual_network_gateway_id      = azurerm_virtual_network_gateway.onprem.id
  peer_virtual_network_gateway_id = var.hub_vpn_gateway_id

  shared_key = var.vpn_shared_key
  enable_bgp = true

  ipsec_policy {
    dh_group         = "DHGroup14"
    ike_encryption   = "AES256"
    ike_integrity    = "SHA256"
    ipsec_encryption = "AES256"
    ipsec_integrity  = "SHA256"
    pfs_group        = "PFS14"
  }

  tags = var.tags
}

###############################################################################
# Simulated Workload VM — represents a corporate DC server
# Apps in Azure spokes connect back to this as if it were an on-prem database
# or file server
###############################################################################
resource "azurerm_network_interface" "onprem_vm" {
  name                = "nic-onprem-vm-${var.environment}"
  location            = azurerm_resource_group.onprem.location
  resource_group_name = azurerm_resource_group.onprem.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.workload.id
    private_ip_address_allocation = "Static"
    private_ip_address            = var.onprem_vm_ip
  }

  tags = var.tags
}

resource "azurerm_linux_virtual_machine" "onprem_dc" {
  name                = "vm-onprem-dc-${var.environment}"
  location            = azurerm_resource_group.onprem.location
  resource_group_name = azurerm_resource_group.onprem.name
  size                = "Standard_B2s" # cheap — this is just a simulation VM
  admin_username      = "azureuser"

  network_interface_ids = [azurerm_network_interface.onprem_vm.id]

  admin_ssh_key {
    username   = "azureuser"
    public_key = var.ssh_public_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  # Cloud-init: install common corporate DC simulation tools
  custom_data = base64encode(<<-EOF
    #!/bin/bash
    apt-get update -y
    apt-get install -y nginx nfs-kernel-server samba
    echo "Simulated on-prem DC — ${var.environment}" > /var/www/html/index.html
    systemctl enable nginx && systemctl start nginx
  EOF
  )

  tags = var.tags
}

###############################################################################
# NSG for workload subnet — allow traffic from hub/spokes, deny internet
###############################################################################
resource "azurerm_network_security_group" "onprem_workload" {
  name                = "nsg-onprem-workload-${var.environment}"
  location            = azurerm_resource_group.onprem.location
  resource_group_name = azurerm_resource_group.onprem.name

  security_rule {
    name                       = "Allow-SSH-From-Hub"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = var.hub_address_space
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Allow-VNet-Inbound"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Deny-Internet-Inbound"
    priority                   = 4000
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }

  tags = var.tags
}

resource "azurerm_subnet_network_security_group_association" "onprem_workload" {
  subnet_id                 = azurerm_subnet.workload.id
  network_security_group_id = azurerm_network_security_group.onprem_workload.id
}
