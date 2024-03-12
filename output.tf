output "random_pet_name" {
  value = random_pet.random_pet.id
}


output "resource_group_location" {
  value = azurerm_resource_group.resource_group.location
}


output "resource_group_name" {
  value = azurerm_resource_group.resource_group.name

}

output "virtual_hub_name" {
  value = azurerm_virtual_hub.virtual_hub.name
}

output "virtual_wan_name" {
  value = azurerm_virtual_wan.virtual_wan.name
}


output "vm_ip" {
  value = azurerm_linux_virtual_machine.workload_vm.public_ip_address

}
