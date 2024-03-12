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
resource "azurerm_resource_group" "rg" {
  name     = "${local.prefix}-spoke-rg"
  location = "australiaeast"
}

resource "azurerm_virtual_network" "azfw_vnet" {
  name                = "vnet-azfw-securehub-eus"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = ["10.10.0.0/16"]
}


resource "azurerm_subnet" "workload_subnet" {
  name                 = "subnet-workload"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.azfw_vnet.name
  address_prefixes     = ["10.10.1.0/24"]
}


resource "azurerm_subnet" "jump_subnet" {
  name                 = "subnet-jump"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.azfw_vnet.name
  address_prefixes     = ["10.10.2.0/24"]
}

resource "azurerm_network_interface" "vm_workload_nic" {
  name                = "nic-workload"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "ipconfig-workload"
    subnet_id                     = azurerm_subnet.workload_subnet.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_public_ip" "vm_jump_pip" {
  name                = "pip-jump"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_network_interface" "vm_jump_nic" {
  name                = "nic-jump"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "ipconfig-jump"
    subnet_id                     = azurerm_subnet.jump_subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.vm_jump_pip.id
  }
}

resource "azurerm_network_security_group" "vm_workload_nsg" {
  name                = "nsg-workload"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_network_security_group" "vm_jump_nsg" {
  name                = "nsg-jump"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  security_rule {
    name                       = "Allow-ssh"
    priority                   = 300
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_interface_security_group_association" "vm_workload_nsg_association" {
  network_interface_id      = azurerm_network_interface.vm_workload_nic.id
  network_security_group_id = azurerm_network_security_group.vm_workload_nsg.id
}

resource "azurerm_network_interface_security_group_association" "vm_jump_nsg_association" {
  network_interface_id      = azurerm_network_interface.vm_jump_nic.id
  network_security_group_id = azurerm_network_security_group.vm_jump_nsg.id
}

resource "azurerm_linux_virtual_machine" "vm_workload" {
  name                = "workload-vm"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  size                = "Standard_B2ts_v2" #"Standard_DS1_v2" #"Standard_A1_v2"

  admin_username        = "adminuser"
  network_interface_ids = [azurerm_network_interface.vm_workload_nic.id]

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

# resource "azurerm_windows_virtual_machine" "vm_workload" {
#   name                  = "workload-vm"
#   resource_group_name   = azurerm_resource_group.rg.name
#   location              = azurerm_resource_group.rg.location
#   size                  = var.windows_vm_size
#   admin_username        = "mukesh"
#   admin_password        = random_password.password.result
#   network_interface_ids = [azurerm_network_interface.vm_workload_nic.id]
#   os_disk {
#     caching              = "ReadWrite"
#     storage_account_type = "Standard_LRS"
#   }
#   source_image_reference {
#     publisher = "MicrosoftWindowsServer"
#     offer     = "WindowsServer"
#     sku       = "2019-Datacenter"
#     version   = "latest"
#   }
# }
#
# resource "azurerm_windows_virtual_machine" "vm_jump" {
#   name                  = "jump-vm"
#   resource_group_name   = azurerm_resource_group.rg.name
#   location              = azurerm_resource_group.rg.location
#   size                  = var.windows_vm_size
#   admin_username        = "mukesh"
#   admin_password        = random_password.password.result
#   network_interface_ids = [azurerm_network_interface.vm_jump_nic.id]
#   os_disk {
#     caching              = "ReadWrite"
#     storage_account_type = "Standard_LRS"
#   }
#   source_image_reference {
#     publisher = "MicrosoftWindowsServer"
#     offer     = "WindowsServer"
#     sku       = "2019-Datacenter"
#     version   = "latest"
#   }
# }


resource "azurerm_linux_virtual_machine" "vm_jump" {
  name                = "jump-vm"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  size                = "Standard_B2ts_v2" #"Standard_DS1_v2" #"Standard_A1_v2"
  admin_username      = "adminuser"

  network_interface_ids = [azurerm_network_interface.vm_jump_nic.id]

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
resource "azurerm_route_table" "rt" {
  name                          = "rt-azfw-securehub-eus"
  location                      = azurerm_resource_group.rg.location
  resource_group_name           = azurerm_resource_group.rg.name
  disable_bgp_route_propagation = false
  route {
    name           = "jump-to-internet"
    address_prefix = "0.0.0.0/0"
    next_hop_type  = "Internet"
  }
}

resource "azurerm_subnet_route_table_association" "jump_subnet_rt_association" {
  subnet_id      = azurerm_subnet.jump_subnet.id
  route_table_id = azurerm_route_table.rt.id
}

resource "random_password" "password" {
  length      = 20
  min_lower   = 1
  min_upper   = 1
  min_numeric = 1
  min_special = 1
  special     = true
}


#------------------------------------------------
# Vhub Route Table
# ------------------------------------------------
resource "azurerm_virtual_hub_route_table" "vhub_rt" {
  name           = "vhub-rt"
  virtual_hub_id = azurerm_virtual_hub.virtual_hub.id

  route {
    name              = "workload-to-firewall"
    destinations_type = "CIDR"
    destinations      = ["10.10.1.0/24"]
    next_hop_type     = "ResourceId"
    next_hop          = azurerm_firewall.firewall.id

  }

  route {
    name              = "jump-to-firewall"
    destinations_type = "CIDR"
    destinations      = ["0.0.0.0/0"]
    next_hop_type     = "ResourceId"
    next_hop          = azurerm_firewall.firewall.id
  }

  labels = ["Vnet"]


}



resource "azurerm_virtual_hub_connection" "azfw_vwan_hub_connection" {
  name                      = "hub-to-spoke"
  virtual_hub_id            = azurerm_virtual_hub.virtual_hub.id
  remote_virtual_network_id = azurerm_virtual_network.azfw_vnet.id
  internet_security_enabled = true

  routing {
    associated_route_table_id = azurerm_virtual_hub_route_table.vhub_rt.id

    propagated_route_table {

      route_table_ids = [azurerm_virtual_hub_route_table.vhub_rt.id]
      labels          = ["VNet"]

    }
  }
}
