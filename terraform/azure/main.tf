terraform {
  required_version = ">= 0.11"

  backend "azurerm" {}
}

# Configure the Microsoft Azure Provider
provider "azurerm" {}

# Create a resource group if it doesn’t exist
resource "azurerm_resource_group" "demo_resource_group" {
  name     = "packerdemocreate"
  location = "Canada Central"

  tags {
    environment = "Packer Demo"
  }
}

# Create virtual network
resource "azurerm_virtual_network" "demo_virtual_network" {
  name                = "packerdemo"
  address_space       = ["10.0.0.0/16"]
  location            = "${azurerm_resource_group.demo_resource_group.location}"
  resource_group_name = "${azurerm_resource_group.demo_resource_group.name}"

  tags {
    environment = "Packer Demo"
  }
}

# Create subnet
resource "azurerm_subnet" "demo_subnet" {
  name                 = "packerdemo"
  resource_group_name  = "${azurerm_resource_group.demo_resource_group.name}"
  virtual_network_name = "${azurerm_virtual_network.demo_virtual_network.name}"
  address_prefix       = "10.0.1.0/24"
}

# Create public IPs
resource "azurerm_public_ip" "demo_public_ip" {
  name                         = "packerpublicip"
  location                     = "${azurerm_resource_group.demo_resource_group.location}"
  resource_group_name          = "${azurerm_resource_group.demo_resource_group.name}"
  public_ip_address_allocation = "static"
  domain_name_label            = "demopackeriac"

  tags {
    environment = "Packer Demo"
  }
}

# Create Network Security Group and rule
resource "azurerm_network_security_group" "demo_security_group" {
  name                = "packersecuritygroups"
  location            = "${azurerm_resource_group.demo_resource_group.location}"
  resource_group_name = "${azurerm_resource_group.demo_resource_group.name}"

  security_rule {
    name                       = "HTTP"
    priority                   = 1002
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  tags {
    environment = "Packer Demo"
  }
}

resource "azurerm_lb" "vmss_lb" {
  name                = "vmss-lb"
  location            = "${azurerm_resource_group.demo_resource_group.location}"
  resource_group_name = "${azurerm_resource_group.demo_resource_group.name}"

  frontend_ip_configuration {
    name                 = "PublicIPAddress"
    public_ip_address_id = "${azurerm_public_ip.demo_public_ip.id}"
  }

  tags {
    environment = "Terraform Demo"
  }
}

resource "azurerm_lb_backend_address_pool" "bpepool" {
  resource_group_name = "${azurerm_resource_group.demo_resource_group.name}"
  loadbalancer_id     = "${azurerm_lb.vmss_lb.id}"
  name                = "BackEndAddressPool"
}

resource "azurerm_lb_probe" "vmss_probe" {
  resource_group_name = "${azurerm_resource_group.demo_resource_group.name}"
  loadbalancer_id     = "${azurerm_lb.vmss_lb.id}"
  name                = "ssh-running-probe"
  port                = "8080"
}

resource "azurerm_lb_rule" "lbnatrule" {
  resource_group_name            = "${azurerm_resource_group.demo_resource_group.name}"
  loadbalancer_id                = "${azurerm_lb.vmss_lb.id}"
  name                           = "http"
  protocol                       = "Tcp"
  frontend_port                  = "80"
  backend_port                   = "8080"
  backend_address_pool_id        = "${azurerm_lb_backend_address_pool.bpepool.id}"
  frontend_ip_configuration_name = "PublicIPAddress"
  probe_id                       = "${azurerm_lb_probe.vmss_probe.id}"
}

# Generate random text for a unique storage account name
resource "random_id" "randomId" {
  keepers = {
    # Generate a new ID only when a new resource group is defined
    resource_group = "${azurerm_resource_group.demo_resource_group.name}"
  }

  byte_length = 8
}

# Create storage account for boot diagnostics
resource "azurerm_storage_account" "demo_storage_account" {
  name                     = "diag${random_id.randomId.hex}"
  resource_group_name      = "${azurerm_resource_group.demo_resource_group.name}"
  location                 = "${azurerm_resource_group.demo_resource_group.location}"
  account_tier             = "Standard"
  account_replication_type = "LRS"

  tags {
    environment = "Terraform Demo"
  }
}

# Points to Packer build image 
data "azurerm_image" "image" {
  name                = "${var.manageddiskname}"
  resource_group_name = "${var.manageddiskname-rg}"
}

# Create virtual machine sclae set
resource "azurerm_virtual_machine_scale_set" "vmss" {
  name                = "vmscaleset"
  location            = "${azurerm_resource_group.demo_resource_group.location}"
  resource_group_name = "${azurerm_resource_group.demo_resource_group.name}"
  upgrade_policy_mode = "Automatic"

  sku {
    name     = "Standard_DS1_v2"
    tier     = "Standard"
    capacity = 2
  }

  storage_profile_image_reference {
    id = "${data.azurerm_image.image.id}"
  }

  storage_profile_os_disk {
    name              = ""
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Premium_LRS"
  }

  os_profile {
    computer_name_prefix = "myvm"
    admin_username       = "azureuser"
    admin_password       = "Passwword1234"
  }

  os_profile_linux_config {
    disable_password_authentication = true

    ssh_keys {
      path     = "/home/azureuser/.ssh/authorized_keys"
      key_data = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDSMrivCj84H8JZFFOiWZrzQCqj1MKtkNTEFU+GbEyYa+XF8HkDSBQ2troWGgZ26qRDE5pKcFw6bUQSq43jANfOfviMEzF8xBI5UzGIGL+pzGgf0vxoGGEI0943uvN+KieSj1g4fkomLDIc+9Zy+UeOsH8OACoGUQZeJGvlOx43APhodDklcSZpBczUEvqrWUs2hRShtO+0dHKtNySkiYKebrz6oQ9hA9NUu2KXv5dQneAX/hUHbn1Q15MVeZ8TjkRdgamowI6Yz9l/e0Wq9rfrKGaMQvyPFp/K2qpBsGvlCynDvaKaUwaRZf1PcVD5wS2YQ4tNvi0Rz5mHGtX+Cl2qffBbtXBFz/UBb7YS9ADwBky/TzwYWZ2PFqxzmAIA3uOji99UUI/Ff6CCJyVye4dtUdNVApfnvTI2Ty7Q97ZLA1ORggAh+67Gu52+ivjBPYxWHxK1uAXIu39agF5PQ/qKzFwGqPE0OqcGfta+NIpATE7A26q4BH3KUthJDsCN2P2iSH7gDiFf5TW5ZW0G0eWlffpNro2rffUNiHfU9ASM1WX2PCAqyYn4zstNDINOIsYuKeMqOrM39df1jtm3/TRonYOZZHSNQq8tGvHFLHX2QFlWV0PlFV1CcoU7CwoEahGpEVObu4fXLW5Z1UpVLC2eqLyWdNrOnhVfKDTaL7o+zw== algibbon@microsoft.com"
    }
  }

  network_profile {
    name    = "terraformnetworkprofile"
    primary = true

    ip_configuration {
      name                                   = "IPConfiguration"
      subnet_id                              = "${azurerm_subnet.demo_subnet.id}"
      load_balancer_backend_address_pool_ids = ["${azurerm_lb_backend_address_pool.bpepool.id}"]
      primary = true
    }
  }

  tags {
    environment = "Terraform Demo"
  }
}

output "vm_ip" {
  value = "${azurerm_public_ip.demo_public_ip.ip_address}"
}

output "vm_dns" {
  value = "http://${azurerm_public_ip.demo_public_ip.domain_name_label}.canadacentral.cloudapp.azure.com"
}
