module "frontend" {
  source = "./terraform/frontend"

  site_domain        = var.site_domain
  source_files       = var.source_files
  custom_domain_name = var.custom_domain_name
  common_tags        = var.common_tags
  naming_prefix      = var.naming_prefix
}

module "backend" {
  source = "./terraform/backend"

  common_tags   = var.common_tags
  naming_prefix = var.naming_prefix
}