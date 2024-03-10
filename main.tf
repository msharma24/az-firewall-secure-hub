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
