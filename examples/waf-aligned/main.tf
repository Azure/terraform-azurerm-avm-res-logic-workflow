terraform {
  required_version = ">= 1.9, < 2.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0, >= 4.8.0, >= 4.21.1, < 5.0.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.5.0, < 4.0.0"
    }
  }
}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
  subscription_id = "46427a45-8a0a-4c2e-b5ba-91ba905139f6"
}


## Section to provide a random Azure region for the resource group
# This allows us to randomize the region for the resource group.
module "regions" {
  source  = "Azure/regions/azurerm"
  version = "0.8.2"
}

# This allows us to randomize the region for the resource group.
resource "random_integer" "region_index" {
  max = length(module.regions.regions) - 1
  min = 0
}
## End of section to provide a random Azure region for the resource group

# This ensures we have unique CAF compliant names for our resources.
module "naming" {
  source  = "Azure/naming/azurerm"
  version = "0.4.2"
}
resource "azurerm_user_assigned_identity" "example_identity" {
  location            = azurerm_resource_group.this.location
  name                = module.naming.user_assigned_identity.name_unique
  resource_group_name = azurerm_resource_group.this.name
}

# This is required for resource modules
resource "azurerm_resource_group" "this" {
  location = module.regions.regions[random_integer.region_index.result].name
  name     = module.naming.resource_group.name_unique
}

#Log Analytics Workspace for diagnostic settings
resource "azurerm_log_analytics_workspace" "this" {
  location            = azurerm_resource_group.this.location
  name                = module.naming.log_analytics_workspace.name_unique
  resource_group_name = azurerm_resource_group.this.name
  sku                 = "PerGB2018"
}

# This is the module call
# Do not specify location here due to the randomization above.
# Leaving location as `null` will cause the module to use the resource group location
# with a data source.
module "logicapp_workflow_waf" {
  source = "../../"

  location            = azurerm_resource_group.this.location
  name                = module.naming.logic_app_workflow.name_unique
  resource_group_id   = azurerm_resource_group.this.id
  resource_group_name = azurerm_resource_group.this.name
  access_control = {
    actions = {
      allowedCallerIpAddresses = [
        {
          addressRange = "10.0.0.0/16"
        }
      ]
    }
    contents = {
      allowedCallerIpAddresses = [
        {
          addressRange = "10.1.0.0/16"
        }
      ]
    }
    triggers = {
      allowedCallerIpAddresses = [
        {
          addressRange = "10.2.0.0/16"
        }
      ]
    }
    workflowManagement = {
      allowedCallerIpAddresses = [
        {
          addressRange = "10.3.0.0/16"
        }
      ]
    }
  }
  diagnostic_settings = {
    LogicAppDiagnostics = {
      name                  = "LogicAppDiagnostics"
      workspace_resource_id = azurerm_log_analytics_workspace.this.id
    }
  }
  # source             = "Azure/avm-<res/ptn>-<name>/azurerm"
  # ...
  enable_telemetry     = var.enable_telemetry # see variables.tf
  logic_app_definition = jsondecode(file("./logic_app_definition.json"))["properties"]["definition"]
  managed_identities = {
    system_assigned            = false
    user_assigned_resource_ids = [azurerm_user_assigned_identity.example_identity.id]
  }
  role_assignments = {
    logic_app_contributor = {
      role_definition_id_or_name = "Logic App Contributor"
      principal_id               = azurerm_user_assigned_identity.example_identity.principal_id
    }
  }
  state = "Enabled"
  tags = {
    environment = "production"
  }
  workflowParameters = {
    "WebsiteURL" = {
      type = "String"
      metadata = {
        description = "URL of website to monitor"
      }
      description = "The URL of the website to monitor."
      value       = "https://www.google.com"
    },
    "Products" = {
      type = "Array"
      metadata = {
        description = "Products to include"
      }
      description = "The products to include."
      value = [
        "Azure",
        "Microsoft 365",
        "Dynamics 365"
      ]
    }
  }
}
