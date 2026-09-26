resource "oci_core_vcn" "this" {
  compartment_id = oci_identity_compartment.this.id
  display_name   = local.name
  cidr_blocks    = [var.settings.vcn_cidr]
  dns_label      = "q1${var.environment}"
}

data "oci_core_services" "this" {
  filter {
    name   = "name"
    values = ["All .* Services In Oracle Services Network"]
    regex  = true
  }
}

resource "oci_core_service_gateway" "this" {
  compartment_id = oci_identity_compartment.this.id
  display_name   = "${local.name}-services"
  vcn_id         = oci_core_vcn.this.id
  services {
    service_id = one(data.oci_core_services.this.services).id
  }
}

resource "oci_core_route_table" "private" {
  compartment_id = oci_identity_compartment.this.id
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${local.name}-private"
  route_rules {
    destination       = one(data.oci_core_services.this.services).cidr_block
    destination_type  = "SERVICE_CIDR_BLOCK"
    network_entity_id = oci_core_service_gateway.this.id
  }
}

# Subnets usam esta lista vazia: as regras efetivas ficam nos NSGs, sem herdar defaults permissivos.
resource "oci_core_security_list" "empty" {
  compartment_id = oci_identity_compartment.this.id
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${local.name}-nsg-only"
}

resource "oci_core_subnet" "this" {
  for_each                   = { api = 0, workers = 1, database = 2 }
  compartment_id             = oci_identity_compartment.this.id
  vcn_id                     = oci_core_vcn.this.id
  display_name               = "${local.name}-${each.key}"
  dns_label                  = each.key
  cidr_block                 = cidrsubnet(var.settings.vcn_cidr, 4, each.value)
  prohibit_public_ip_on_vnic = true
  prohibit_internet_ingress  = true
  route_table_id             = oci_core_route_table.private.id
  security_list_ids          = [oci_core_security_list.empty.id]
}

resource "oci_core_network_security_group" "this" {
  for_each       = toset(["api", "workers", "database"])
  compartment_id = oci_identity_compartment.this.id
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${local.name}-${each.key}"
}

locals {
  # Matriz unica: endpoint e sempre origem (INGRESS) ou destino (EGRESS).
  # Flannel exige trafego entre workers e TCP do control plane aos workers.
  # TCP sem porta para OSN nos workers segue o requisito OKE; nao abre internet.
  # ICMP 3/4 permite descoberta de MTU, inclusive erros gerados fora da VCN.
  network_rules = merge({
    api_from_workers      = { nsg = "api", direction = "INGRESS", type = "NETWORK_SECURITY_GROUP", endpoint = oci_core_network_security_group.this["workers"].id, protocol = "6", port = 6443 }
    api_registration      = { nsg = "api", direction = "INGRESS", type = "NETWORK_SECURITY_GROUP", endpoint = oci_core_network_security_group.this["workers"].id, protocol = "6", port = 12250 }
    workers_to_api        = { nsg = "workers", direction = "EGRESS", type = "NETWORK_SECURITY_GROUP", endpoint = oci_core_network_security_group.this["api"].id, protocol = "6", port = 6443 }
    workers_registration  = { nsg = "workers", direction = "EGRESS", type = "NETWORK_SECURITY_GROUP", endpoint = oci_core_network_security_group.this["api"].id, protocol = "6", port = 12250 }
    api_to_workers        = { nsg = "api", direction = "EGRESS", type = "NETWORK_SECURITY_GROUP", endpoint = oci_core_network_security_group.this["workers"].id, protocol = "6", port = null }
    workers_from_api      = { nsg = "workers", direction = "INGRESS", type = "NETWORK_SECURITY_GROUP", endpoint = oci_core_network_security_group.this["api"].id, protocol = "6", port = null }
    workers_internal_in   = { nsg = "workers", direction = "INGRESS", type = "NETWORK_SECURITY_GROUP", endpoint = oci_core_network_security_group.this["workers"].id, protocol = "all", port = null }
    workers_internal_out  = { nsg = "workers", direction = "EGRESS", type = "NETWORK_SECURITY_GROUP", endpoint = oci_core_network_security_group.this["workers"].id, protocol = "all", port = null }
    database_from_workers = { nsg = "database", direction = "INGRESS", type = "NETWORK_SECURITY_GROUP", endpoint = oci_core_network_security_group.this["workers"].id, protocol = "6", port = 5432 }
    workers_to_database   = { nsg = "workers", direction = "EGRESS", type = "NETWORK_SECURITY_GROUP", endpoint = oci_core_network_security_group.this["database"].id, protocol = "6", port = 5432 }
    api_services          = { nsg = "api", direction = "EGRESS", type = "SERVICE_CIDR_BLOCK", endpoint = one(data.oci_core_services.this.services).cidr_block, protocol = "6", port = 443 }
    # Porta do suporte/observabilidade gerenciados OKE, nao uma stack de Q3.
    api_support      = { nsg = "api", direction = "EGRESS", type = "SERVICE_CIDR_BLOCK", endpoint = one(data.oci_core_services.this.services).cidr_block, protocol = "6", port = 9995 }
    workers_services = { nsg = "workers", direction = "EGRESS", type = "SERVICE_CIDR_BLOCK", endpoint = one(data.oci_core_services.this.services).cidr_block, protocol = "6", port = null }
    api_mtu          = { nsg = "api", direction = "INGRESS", type = "NETWORK_SECURITY_GROUP", endpoint = oci_core_network_security_group.this["workers"].id, protocol = "1", port = null }
    api_mtu_out      = { nsg = "api", direction = "EGRESS", type = "NETWORK_SECURITY_GROUP", endpoint = oci_core_network_security_group.this["workers"].id, protocol = "1", port = null }
    api_services_mtu = { nsg = "api", direction = "EGRESS", type = "SERVICE_CIDR_BLOCK", endpoint = one(data.oci_core_services.this.services).cidr_block, protocol = "1", port = null }
    workers_mtu      = { nsg = "workers", direction = "INGRESS", type = "CIDR_BLOCK", endpoint = "0.0.0.0/0", protocol = "1", port = null }
    workers_mtu_out  = { nsg = "workers", direction = "EGRESS", type = "CIDR_BLOCK", endpoint = "0.0.0.0/0", protocol = "1", port = null }
    }, { for cidr in var.settings.admin_cidrs : "admin-${cidr}" => {
      nsg = "api", direction = "INGRESS", type = "CIDR_BLOCK", endpoint = cidr, protocol = "6", port = 6443
  } })
}

resource "oci_core_network_security_group_security_rule" "this" {
  for_each                  = local.network_rules
  network_security_group_id = oci_core_network_security_group.this[each.value.nsg].id
  direction                 = each.value.direction
  protocol                  = each.value.protocol
  stateless                 = false
  description               = each.key
  source                    = each.value.direction == "INGRESS" ? each.value.endpoint : null
  source_type               = each.value.direction == "INGRESS" ? each.value.type : null
  destination               = each.value.direction == "EGRESS" ? each.value.endpoint : null
  destination_type          = each.value.direction == "EGRESS" ? each.value.type : null
  dynamic "tcp_options" {
    for_each = each.value.port == null ? [] : [each.value.port]
    content {
      destination_port_range {
        min = tcp_options.value
        max = tcp_options.value
      }
    }
  }
  dynamic "icmp_options" {
    for_each = each.value.protocol == "1" ? [1] : []
    content {
      type = 3
      code = 4
    }
  }
}