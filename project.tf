terraform {
  required_providers {
    scaleway = {
      source = "scaleway/scaleway"
    }
  }
  required_version = ">= 0.13"
}

variable "access_key" { default = "top-level" }
variable "secret_key" { default = "top-level" }
variable "project_id" { default = "top-level" }
variable "db_username" { default = "top-level" }
variable "db_password" { default = "top-level" }

provider "scaleway" {
  access_key = var.access_key
  secret_key = var.secret_key
  zone = "fr-par-1"
}

### VPC Creation
resource "scaleway_vpc_private_network" "vpn01"{
  project_id = var.project_id
  name = "my_private_network"
}

# Public gateway
resource "scaleway_vpc_public_gateway_ip" "gateway01"{
  project_id = var.project_id
}

resource "scaleway_vpc_public_gateway_dhcp" "main"{
  project_id = var.project_id
  subnet = "192.168.1.0/24"
  push_default_route = true
}

resource "scaleway_vpc_public_gateway" "main"{
  project_id = var.project_id
  name = "Public Gateway"
  type = "VPC-GW-M"
  ip_id = scaleway_vpc_public_gateway_ip.gateway01.id
  depends_on = [scaleway_vpc_public_gateway_ip.gateway01]
}

resource "scaleway_vpc_gateway_network" "main"{
  gateway_id = scaleway_vpc_public_gateway.main.id
  private_network_id = scaleway_vpc_private_network.vpn01.id
  dhcp_id = scaleway_vpc_public_gateway_dhcp.main.id
  cleanup_dhcp = true
  enable_masquerade = true
  depends_on = [scaleway_vpc_public_gateway.main,scaleway_vpc_private_network.vpn01, scaleway_vpc_public_gateway_dhcp.main]
}


# Web Server
resource "scaleway_instance_server" "web"{
  project_id = var.project_id
  name = "web"
  image = "ubuntu_focal"
  type = "DEV1-S"
  user_data = { 
    cloud-init = templatefile("${path.module}/cloud-init-user-data.yml", {PGHOST = scaleway_rdb_instance.database.endpoint_ip , PGPORT = scaleway_rdb_instance.database.endpoint_port , PGDATABASE = "rdb" , PGUSER = var.db_username , PGPASSWORD = var.db_password })
  }

  depends_on = [scaleway_rdb_instance.database]

  private_network{
    pn_id = scaleway_vpc_private_network.vpn01.id
  }
}


# database
resource "scaleway_rdb_instance" "database" {
  project_id = var.project_id
  name           = "test-rdb"
  node_type      = "DB-DEV-S"
  engine         = "PostgreSQL-14"
  is_ha_cluster  = true
  disable_backup = true
  user_name      = var.db_username
  password       = var.db_password
  private_network {
    ip_net = "192.168.1.254/24" #pool high
    pn_id = scaleway_vpc_private_network.vpn01.id
  }
}

# port forwarding
resource "scaleway_vpc_public_gateway_pat_rule" "web_server_http"{
  gateway_id = scaleway_vpc_public_gateway.main.id
  private_ip = scaleway_vpc_public_gateway_dhcp.main.address
  private_port = 3000
  public_port = 3000
  protocol = "both"
  depends_on = [scaleway_vpc_gateway_network.main, scaleway_instance_server.web]
}