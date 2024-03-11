resource "random_pet" "random_pet" {
  length    = 2
  separator = "-"
}

locals {
  prefix = "${var.env}-${random_pet.random_pet.id}"
}

#------------------------------------------------    
# Resource Group                                     
# ------------------------------------------------   
resource "azurerm_resource_group" "resource_group" {
  name     = "${local.prefix}-rg"
  location = "australiaeast"

}

#------------------------------------------------
# Virtual WAN
# ------------------------------------------------
resource "azurerm_virtual_wan" "virtual_wan" {
  name                = "${local.prefix}-vw"
  location            = azurerm_resource_group.resource_group.location
  resource_group_name = azurerm_resource_group.resource_group.name

}

#------------------------------------------------    
# Virtual Hub
#------------------------------------------------    
resource "azurerm_virtual_hub" "virtual_hub" {
  name                = "${local.prefix}-vh"
  location            = azurerm_resource_group.resource_group.location
  resource_group_name = azurerm_resource_group.resource_group.name
  virtual_wan_id      = azurerm_virtual_wan.virtual_wan.id
  address_prefix      = "10.0.0.0/23" #"10.0.0.0/16"
  sku                 = "Standard"

}

#------------------------------------------------
# Azure Firewall 
# ------------------------------------------------
resource "azurerm_firewall" "firewall" {
  name                = "${local.prefix}-fw"
  location            = azurerm_resource_group.resource_group.location
  resource_group_name = azurerm_resource_group.resource_group.name
  sku_tier            = "Standard"
  sku_name            = "AZFW_Hub"

  virtual_hub {
    virtual_hub_id = azurerm_virtual_hub.virtual_hub.id
  }
}

#------------------------------------------------
# Spoke Networking
# ------------------------------------------------
resource "azurerm_resource_group" "spoke_resource_group" {
  name     = "${local.prefix}-spoke-rg"
  location = "australiaeast"
}


#------------------------------------------------
# Spoke Vnet 1
# ------------------------------------------------
resource "azurerm_virtual_network" "spoke_vnet" {
  name                = "${local.prefix}-spoke-vnet"
  location            = azurerm_resource_group.spoke_resource_group.location
  resource_group_name = azurerm_resource_group.spoke_resource_group.name
  address_space       = ["172.17.0.0/20"]
}

resource "azurerm_subnet" "private_subnet_vnet1" {
  name                 = "private-subnet"
  resource_group_name  = azurerm_resource_group.spoke_resource_group.name
  virtual_network_name = azurerm_virtual_network.spoke_vnet.name
  address_prefixes     = ["172.17.0.0/22"] #"10.0.1.0/24"]
}

#------------------------------------------------
# Spoke Vnet 2
# ------------------------------------------------
resource "azurerm_virtual_network" "spoke_vnet_2" {
  name                = "${local.prefix}-spoke-vnet-2"
  location            = azurerm_resource_group.spoke_resource_group.location
  resource_group_name = azurerm_resource_group.spoke_resource_group.name
  address_space       = ["172.24.16.0/20"]
}

resource "azurerm_virtual_hub_connection" "spoke_vnet_vh_connection" {
  name                      = "${local.prefix}-spoke-vnet-vh-connection"
  virtual_hub_id            = azurerm_virtual_hub.virtual_hub.id
  remote_virtual_network_id = azurerm_virtual_network.spoke_vnet.id

  routing {
    associated_route_table_id = azurerm_virtual_hub_route_table.spoke_route_table_vhub.id
  }

}

resource "azurerm_virtual_hub_connection" "spoke_vnet_vh_connection_2" {
  name                      = "${local.prefix}-spoke-vnet-vh-connection-2"
  virtual_hub_id            = azurerm_virtual_hub.virtual_hub.id
  remote_virtual_network_id = azurerm_virtual_network.spoke_vnet_2.id

  routing {
    associated_route_table_id = azurerm_virtual_hub_route_table.spoke_route_table_vhub.id
  }

}

#------------------------------------------------
# Route Tables
# ------------------------------------------------
resource "azurerm_virtual_hub_route_table" "spoke_route_table_vhub" {
  name           = "${local.prefix}-spoke-route-table-vhub"
  virtual_hub_id = azurerm_virtual_hub.virtual_hub.id
  labels         = ["label1"]

}

resource "azurerm_virtual_hub_route_table" "firewall_spoke_route_table" {
  name           = "${local.prefix}-firewall-spoke-route-table"
  virtual_hub_id = azurerm_virtual_hub.virtual_hub.id
  labels         = ["label2"]


}

#------------------------------------------------
# Virtual Hub Routing Intent
# ------------------------------------------------
resource "azurerm_virtual_hub_routing_intent" "vhub_routing_intent" {
  name           = "${local.prefix}-vhub-routing-intent"
  virtual_hub_id = azurerm_virtual_hub.virtual_hub.id

  routing_policy {
    name         = "PrivateTraffic"
    destinations = ["Internet"]
    next_hop     = azurerm_firewall.firewall.id
  }

  depends_on = [azurerm_firewall.firewall]

}

resource "azurerm_virtual_hub_routing_intent" "vhub_routing_intent_internet" {
  name           = "${local.prefix}-vhub-routing-intent"
  virtual_hub_id = azurerm_virtual_hub.virtual_hub.id

  routing_policy {
    name         = "InternetTraffic"
    destinations = ["Internet"]
    next_hop     = azurerm_firewall.firewall.id
  }

  depends_on = [azurerm_firewall.firewall, azurerm_virtual_hub_routing_intent.vhub_routing_intent]

}


resource "azurerm_virtual_hub_route_table_route" "spoke_rt_spoke_route" {
  route_table_id = azurerm_virtual_hub_route_table.spoke_route_table_vhub.id

  name              = "spoke_route-to-fw"
  destinations_type = "CIDR"
  destinations      = ["0.0.0.0/0"]
  next_hop          = azurerm_firewall.firewall.id


}
