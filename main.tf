resource "azapi_resource" "this" {
  type = "Microsoft.Logic/workflows@2019-05-01"
  body = jsonencode({
    properties = {
      parameters = {}
      state      = "Enabled"
      definition = var.logic_app_definition
      #definition                    = [jsondecode(var.logic_app_definition), jsondecode(local.default_logicapp_json)][var.logic_app_definition == "" ? 0 : 1]
      accessControl                 = var.access_control
      endpointsConfiguration        = var.endpoints_configuration
      integrationAccount            = var.integration_account_id != "" ? { id = var.integration_account_id } : null
      integrationServiceEnvironment = var.integration_service_environment_id != "" ? { id = var.integration_service_environment_id } : null
    }
  })
  location  = var.location
  name      = var.name
  parent_id = var.resource_group_id
  tags      = var.tags

  dynamic "identity" {

    for_each = (var.managed_identities.system_assigned || length(var.managed_identities.user_assigned_resource_ids) > 0) ? { this = var.managed_identities } : {}
    content {
      type         = identity.value.system_assigned && length(identity.value.user_assigned_resource_ids) > 0 ? "SystemAssigned, UserAssigned" : length(identity.value.user_assigned_resource_ids) > 0 ? "UserAssigned" : "SystemAssigned"
      identity_ids = identity.value.user_assigned_resource_ids
    }
  }
}

# required AVM resources interfaces
resource "azurerm_management_lock" "this" {
  count = var.lock != null ? 1 : 0

  lock_level = var.lock.kind
  name       = coalesce(var.lock.name, "lock-${var.lock.kind}")
  scope      = azapi_resource.this.id
  notes      = var.lock.kind == "CanNotDelete" ? "Cannot delete the resource or its child resources." : "Cannot delete or modify the resource or its child resources."
}

resource "azurerm_role_assignment" "this" {
  for_each = var.role_assignments

  principal_id                           = each.value.principal_id
  scope                                  = azapi_resource.this.id
  condition                              = each.value.condition
  condition_version                      = each.value.condition_version
  delegated_managed_identity_resource_id = each.value.delegated_managed_identity_resource_id
  role_definition_id                     = strcontains(lower(each.value.role_definition_id_or_name), lower(local.role_definition_resource_substring)) ? each.value.role_definition_id_or_name : null
  role_definition_name                   = strcontains(lower(each.value.role_definition_id_or_name), lower(local.role_definition_resource_substring)) ? null : each.value.role_definition_id_or_name
  skip_service_principal_aad_check       = each.value.skip_service_principal_aad_check
}
