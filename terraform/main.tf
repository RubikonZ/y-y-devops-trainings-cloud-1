terraform {
  required_providers {
    yandex = {
      source = "yandex-cloud/yandex"
    }
  }
  required_version = ">= 0.13"
}

provider "yandex" {
  service_account_key_file = "./ruben-terraform-key1.json"
  folder_id                = local.folder_id
  zone                     = "ru-central1-a"
}

resource "yandex_vpc_network" "foo" {}

resource "yandex_vpc_subnet" "foo" {
  zone           = "ru-central1-a"
  network_id     = yandex_vpc_network.foo.id
  v4_cidr_blocks = ["10.5.0.0/24"]
}

# Creates another registry
resource "yandex_container_registry" "registry1" {
  name = "ruben-devops-registry"
}

# Number of local parameters
locals {
  folder_id = "b1g0sls5tgao4phfnr9f"
  service-accounts = toset([
    "catgpt-sa",
    "instance-group-sa"
  ])
  catgpt-sa-roles = toset([
    "container-registry.images.puller",
    "monitoring.editor",
  ])
  instance-group-sa-roles = toset([
    "editor"
  ])
}

# Creates service account for each key in set local.service-accounts
resource "yandex_iam_service_account" "service-accounts" {
  for_each = local.service-accounts
  name     = "${local.folder_id}-${each.key}"
}

resource "yandex_resourcemanager_folder_iam_member" "catgpt-roles" {
  for_each  = local.catgpt-sa-roles
  folder_id = local.folder_id
  member    = "serviceAccount:${yandex_iam_service_account.service-accounts["catgpt-sa"].id}"
  role      = each.key
}

resource "yandex_resourcemanager_folder_iam_member" "instance-group-roles" {
  for_each  = local.instance-group-sa-roles
  folder_id = local.folder_id
  member    = "serviceAccount:${yandex_iam_service_account.service-accounts["instance-group-sa"].id}"
  role      = each.key
}

data "yandex_compute_image" "coi" {
  family = "container-optimized-image"
}
resource "yandex_compute_instance_group" "ig-1" {
  name                = "fixed-ig-with-balancer"
  folder_id           = "b1g0sls5tgao4phfnr9f"
  service_account_id  = yandex_iam_service_account.service-accounts["instance-group-sa"].id
  deletion_protection = "false"
  instance_template {
    platform_id = "standard-v2"
    resources {
      cores         = 2
      memory        = 1
      core_fraction = 5
    }

    scheduling_policy {
      preemptible = true
    }

    boot_disk {
      initialize_params {
        type = "network-hdd"
        size = "30"
        image_id = data.yandex_compute_image.coi.id
      }
    }

    network_interface {
      network_id = "${yandex_vpc_network.network-1.id}"
      subnet_ids = ["${yandex_vpc_subnet.subnet-1.id}"]
      nat = true
    }

    metadata = {
      docker-compose = file("${path.module}/docker-compose.yaml")
      ssh-keys  = "ubuntu:${file("~/../../Users/r_zurabyan/.ssh/id_ed25519_yandex.pub")}"
    }
  }

    scale_policy {
      fixed_scale {
      size = 2
      }
    }

    allocation_policy {
      zones = ["ru-central1-a"]
    }

    deploy_policy {
      max_unavailable = 5
      max_expansion   = 0
    }

    load_balancer {
      target_group_name        = "target-group"
      target_group_description = "load balancer target group"
    }
}

resource "yandex_lb_network_load_balancer" "lb-1" {
  name = "network-load-balancer-1"

  listener {
    name = "network-load-balancer-1-listener"
    port = 80
    external_address_spec {
      ip_version = "ipv4"
    }
  }

  attached_target_group {
    target_group_id = yandex_compute_instance_group.ig-1.load_balancer.0.target_group_id

    healthcheck {
      name = "http"
      http_options {
        port = 80
        path = "/index.html"
      }
    }
  }
}

resource "yandex_vpc_network" "network-1" {
  name = "network1"
}

resource "yandex_vpc_subnet" "subnet-1" {
  name           = "subnet1"
  zone           = "ru-central1-a"
  network_id     = "${yandex_vpc_network.network-1.id}"
  v4_cidr_blocks = ["192.168.10.0/24"]
}
