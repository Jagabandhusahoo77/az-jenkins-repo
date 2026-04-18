###############################################################################
# Module: networking
#
# Implements Hub-and-Spoke topology per Azure CAF (Cloud Adoption Framework).
# Hub holds shared services (Firewall, VPN Gateway, Bastion).
# Spokes host workloads and peer back to the hub — traffic flows through the
# hub Firewall, giving us a single egress/inspection point.
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
# Hub Virtual Network
###############################################################################
resource "azurerm_virtual_network" "hub" {
  name                = "vnet-${var.hub_name}-${var.environment}-${var.location_short}"
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = [var.hub_address_space]
  dns_servers         = var.dns_servers

  tags = var.tags
}

# AzureFirewallSubnet — name is mandated by Azure, cannot be customised
resource "azurerm_subnet" "firewall" {
  name                 = "AzureFirewallSubnet"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [var.firewall_subnet_prefix]
}

# GatewaySubnet — name is mandated by Azure for VPN/ExpressRoute gateways
resource "azurerm_subnet" "gateway" {
  name                 = "GatewaySubnet"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [var.gateway_subnet_prefix]
}

# AzureBastionSubnet — mandatory name for Azure Bastion
resource "azurerm_subnet" "bastion" {
  name                 = "AzureBastionSubnet"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [var.bastion_subnet_prefix]
}

# Management / jump-box subnet inside the hub
resource "azurerm_subnet" "management" {
  name                 = "snet-mgmt-${var.environment}-${var.location_short}"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [var.management_subnet_prefix]
}

###############################################################################
# Spoke Virtual Networks
###############################################################################
resource "azurerm_virtual_network" "spoke" {
  for_each = var.spokes

  name                = "vnet-${each.key}-${var.environment}-${var.location_short}"
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = [each.value.address_space]
  dns_servers         = var.dns_servers

  tags = merge(var.tags, { spoke = each.key })
}

resource "azurerm_subnet" "spoke_app" {
  for_each = var.spokes

  name                 = "snet-app-${each.key}-${var.environment}-${var.location_short}"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.spoke[each.key].name
  address_prefixes     = [each.value.app_subnet_prefix]

  # Delegate to Microsoft.Web for App Service VNet integration if needed
  dynamic "delegation" {
    for_each = each.value.delegate_to_web ? [1] : []
    content {
      name = "app-service-delegation"
      service_delegation {
        name    = "Microsoft.Web/serverFarms"
        actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
      }
    }
  }
}

resource "azurerm_subnet" "spoke_data" {
  for_each = var.spokes

  name                 = "snet-data-${each.key}-${var.environment}-${var.location_short}"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.spoke[each.key].name
  address_prefixes     = [each.value.data_subnet_prefix]

  # Private endpoint subnet must have this flag disabled
  private_endpoint_network_policies = "Disabled"
}

resource "azurerm_subnet" "spoke_pe" {
  for_each = var.spokes

  name                 = "snet-pe-${each.key}-${var.environment}-${var.location_short}"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.spoke[each.key].name
  address_prefixes     = [each.value.pe_subnet_prefix]

  private_endpoint_network_policies = "Disabled"
}

###############################################################################
# VNet Peering — hub <-> each spoke (bidirectional)
# allow_forwarded_traffic = true so hub Firewall can route spoke-to-spoke
###############################################################################
resource "azurerm_virtual_network_peering" "hub_to_spoke" {
  for_each = var.spokes

  name                      = "peer-hub-to-${each.key}"
  resource_group_name       = var.resource_group_name
  virtual_network_name      = azurerm_virtual_network.hub.name
  remote_virtual_network_id = azurerm_virtual_network.spoke[each.key].id
  allow_forwarded_traffic   = true
  allow_gateway_transit     = true # hub can share its VPN gateway with spokes
  use_remote_gateways       = false
}

resource "azurerm_virtual_network_peering" "spoke_to_hub" {
  for_each = var.spokes

  name                      = "peer-${each.key}-to-hub"
  resource_group_name       = var.resource_group_name
  virtual_network_name      = azurerm_virtual_network.spoke[each.key].name
  remote_virtual_network_id = azurerm_virtual_network.hub.id
  allow_forwarded_traffic   = true
  allow_gateway_transit     = false
  use_remote_gateways       = false
}

###############################################################################
# Network Security Groups
###############################################################################

# App-tier NSG — allow HTTP/S from Application Gateway, block everything else inbound
resource "azurerm_network_security_group" "app" {
  for_each = var.spokes

  name                = "nsg-app-${each.key}-${var.environment}-${var.location_short}"
  location            = var.location
  resource_group_name = var.resource_group_name

  security_rule {
    name                       = "Allow-HTTP-From-AppGW"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["80", "443"]
    source_address_prefix      = "AzureLoadBalancer"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Allow-AppGW-Probe"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "65200-65535"
    source_address_prefix      = "GatewayManager"
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

# Data-tier NSG — only accept traffic from app subnet
resource "azurerm_network_security_group" "data" {
  for_each = var.spokes

  name                = "nsg-data-${each.key}-${var.environment}-${var.location_short}"
  location            = var.location
  resource_group_name = var.resource_group_name

  security_rule {
    name                       = "Allow-SQL-From-App"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "1433"
    source_address_prefix      = each.value.app_subnet_prefix
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Deny-All-Inbound"
    priority                   = 4000
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  tags = var.tags
}

# Bastion NSG — rules are MANDATED by Microsoft for Azure Bastion to function.
# Deviating from these rules breaks Bastion connectivity.
# Ref: https://learn.microsoft.com/en-us/azure/bastion/bastion-nsg
resource "azurerm_network_security_group" "bastion" {
  name                = "nsg-bastion-${var.environment}-${var.location_short}"
  location            = var.location
  resource_group_name = var.resource_group_name

  # --- Inbound ---
  security_rule {
    name                       = "Allow-HTTPS-From-Internet"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }
  security_rule {
    name                       = "Allow-GatewayManager"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "GatewayManager"
    destination_address_prefix = "*"
  }
  security_rule {
    name                       = "Allow-AzureLoadBalancer"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "AzureLoadBalancer"
    destination_address_prefix = "*"
  }
  security_rule {
    name                       = "Allow-BastionDataPlane-Inbound"
    priority                   = 130
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_ranges    = ["8080", "5701"]
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
  }
  security_rule {
    name                       = "Deny-All-Inbound"
    priority                   = 4000
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  # --- Outbound ---
  security_rule {
    name                       = "Allow-SSH-RDP-To-VMs"
    priority                   = 100
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["22", "3389"]
    source_address_prefix      = "*"
    destination_address_prefix = "VirtualNetwork"
  }
  security_rule {
    name                       = "Allow-AzureCloud-Outbound"
    priority                   = 110
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "AzureCloud"
  }
  security_rule {
    name                       = "Allow-BastionDataPlane-Outbound"
    priority                   = 120
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_ranges    = ["8080", "5701"]
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
  }
  security_rule {
    name                       = "Allow-HTTP-SessionInfo"
    priority                   = 130
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "Internet"
  }

  tags = var.tags
}

# Management subnet NSG — jump-box access only from trusted ranges via Bastion or VPN
resource "azurerm_network_security_group" "management" {
  name                = "nsg-mgmt-${var.environment}-${var.location_short}"
  location            = var.location
  resource_group_name = var.resource_group_name

  security_rule {
    name                       = "Allow-SSH-RDP-From-Bastion"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["22", "3389"]
    source_address_prefix      = var.bastion_subnet_prefix
    destination_address_prefix = "*"
  }
  security_rule {
    name                       = "Allow-HTTPS-Outbound"
    priority                   = 100
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "Internet"
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

# Private endpoint subnet NSG — deny direct internet, allow VNet traffic only
resource "azurerm_network_security_group" "pe" {
  for_each = var.spokes

  name                = "nsg-pe-${each.key}-${var.environment}-${var.location_short}"
  location            = var.location
  resource_group_name = var.resource_group_name

  security_rule {
    name                       = "Allow-VNet-Inbound"
    priority                   = 100
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

# NSG associations
resource "azurerm_subnet_network_security_group_association" "app" {
  for_each = var.spokes

  subnet_id                 = azurerm_subnet.spoke_app[each.key].id
  network_security_group_id = azurerm_network_security_group.app[each.key].id
}

resource "azurerm_subnet_network_security_group_association" "data" {
  for_each = var.spokes

  subnet_id                 = azurerm_subnet.spoke_data[each.key].id
  network_security_group_id = azurerm_network_security_group.data[each.key].id
}

resource "azurerm_subnet_network_security_group_association" "bastion" {
  subnet_id                 = azurerm_subnet.bastion.id
  network_security_group_id = azurerm_network_security_group.bastion.id
}

resource "azurerm_subnet_network_security_group_association" "management" {
  subnet_id                 = azurerm_subnet.management.id
  network_security_group_id = azurerm_network_security_group.management.id
}

resource "azurerm_subnet_network_security_group_association" "pe" {
  for_each = var.spokes

  subnet_id                 = azurerm_subnet.spoke_pe[each.key].id
  network_security_group_id = azurerm_network_security_group.pe[each.key].id
}

###############################################################################
# Azure Bastion — secure RDP/SSH without exposing public IPs on VMs
###############################################################################
resource "azurerm_public_ip" "bastion" {
  name                = "pip-bastion-${var.environment}-${var.location_short}"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard" # Standard SKU required for Bastion
  zones               = ["1", "2", "3"]

  tags = var.tags
}

resource "azurerm_bastion_host" "this" {
  name                = "bas-${var.hub_name}-${var.environment}-${var.location_short}"
  location            = var.location
  resource_group_name = var.resource_group_name

  ip_configuration {
    name                 = "configuration"
    subnet_id            = azurerm_subnet.bastion.id
    public_ip_address_id = azurerm_public_ip.bastion.id
  }

  tags = var.tags
}
