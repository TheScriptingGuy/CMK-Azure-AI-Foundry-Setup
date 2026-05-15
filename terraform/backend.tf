# Populate these values from `terraform output backend_config` in ../bootstrap.
# Until you do so, `terraform init` will fail — that's intentional.
terraform {
  backend "azurerm" {
    # resource_group_name  = "rg-cmkfoundry-tfstate-xxxxxx"
    # storage_account_name = "stcmkfoundrytfxxxxxx"
    # container_name       = "tfstate"
    key              = "cmk-azure-ai-foundry.tfstate"
    use_azuread_auth = true
  }
}
