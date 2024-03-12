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
resource "azurerm_resource_group" "dev_rg" {
  name     = "${local.prefix}-dev-rg"
  location = "australiaeast"
}

resource "azurerm_virtual_network" "dev_rg_vnet" {
  name                = "${local.prefix}-dev-vnet"
  location            = azurerm_resource_group.dev_rg.location
  resource_group_name = azurerm_resource_group.dev_rg.name
  address_space       = ["172.17.0.0/20"]

}

resource "azurerm_subnet" "workload_subnet" {
  name                 = "${local.prefix}-workload-subnet"
  resource_group_name  = azurerm_resource_group.dev_rg.name
  virtual_network_name = azurerm_virtual_network.dev_rg_vnet.name
  address_prefixes     = ["172.17.0.0/24"]

}

resource "azurerm_network_security_group" "nsg_worload" {
  name                = "${local.prefix}-workload-nsg"
  location            = azurerm_resource_group.dev_rg.location
  resource_group_name = azurerm_resource_group.dev_rg.name

  security_rule {
    name                       = "Allow-HTTP"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Outbound-All"
    priority                   = 200
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "workload_nsg_subnet" {
  subnet_id                 = azurerm_subnet.workload_subnet.id
  network_security_group_id = azurerm_network_security_group.nsg_worload.id

}

resource "azurerm_public_ip" "public_ip_workload_vm" {
  name                = "${local.prefix}-workload-pip"
  location            = azurerm_resource_group.dev_rg.location
  resource_group_name = azurerm_resource_group.dev_rg.name
  allocation_method   = "Dynamic"
  sku                 = "Basic"

}

resource "azurerm_network_interface" "linux_nic" {
  name                = "${local.prefix}-linux-nic"
  location            = azurerm_resource_group.dev_rg.location
  resource_group_name = azurerm_resource_group.dev_rg.name
  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.workload_subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.public_ip_workload_vm.id
  }

}


resource "azurerm_linux_virtual_machine" "workload_vm" {
  name                = "${local.prefix}-workload-vm"
  location            = azurerm_resource_group.dev_rg.location
  resource_group_name = azurerm_resource_group.dev_rg.name
  size                = "Standard_B1s"
  admin_username      = "adminuser"
  network_interface_ids = [
    azurerm_network_interface.linux_nic.id
  ]
  admin_ssh_key {
    username   = "adminuser"
    public_key = file("~/.ssh/id_rsa.pub")
  }
  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }
  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }

}

#------------------------------------------------
# Virtual hub Routing
#------------------------------------------------
resource "azurerm_virtual_hub_connection" "vhub_vnet_connection" {
  name                      = "${local.prefix}-vhub-vnet-connection"
  virtual_hub_id            = azurerm_virtual_hub.virtual_hub.id
  remote_virtual_network_id = azurerm_virtual_network.dev_rg_vnet.id

}

#azurerm_virtual_hub_route_table
resource "azurerm_virtual_hub_route_table" "vhub_route_table" {
  name           = "${local.prefix}-vhub-route-table"
  virtual_hub_id = azurerm_virtual_hub.virtual_hub.id
  labels         = ["Workload"]

  route {
    name              = "Workload-to-firewall"
    destinations_type = "CIDR"
    destinations      = ["172.17.0.0/24"]
    next_hop_type     = "ResourceId"
    next_hop          = azurerm_firewall.firewall.id
  }

  route {
    name              = "Workload-to-internet"
    destinations_type = "CIDR"
    destinations      = ["0.0.0.0/0"]
    next_hop_type     = "ResourceId"
    next_hop          = azurerm_firewall.firewall.id
  }

}


#------------------------------------------------
# Firewall Policy Test
# ------------------------------------------------
resource "azurerm_firewall_policy" "fw_policy" {
  name                = "${local.prefix}-fw-policy"
  resource_group_name = azurerm_resource_group.resource_group.name
  location            = azurerm_resource_group.resource_group.location
  sku                 = "Premium"

}

resource "azurerm_firewall_policy_rule_collection_group" "fw_policy_rule_collection" {
  name               = "${local.prefix}-fw-policy-rule-collection"
  firewall_policy_id = azurerm_firewall_policy.fw_policy.id
  priority           = 100

  application_rule_collection {
    name     = "Allow-HTTP"
    action   = "Deny"
    priority = 100
    rule {
      name = "Allow-HTTP"
      protocols {
        type = "Http"
        port = "80"
      }
      protocols {
        type = "Https"
        port = "443"
      }
      source_addresses  = ["*"]
      destination_fqdns = ["www.bing.com"]
    }
  }

}
